import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, type DocumentReference} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {requestSumsubApplicantDeletion} from "./sumsub/sumsubApplicantLifecycle.js";
import {safeLogMeta} from "./security/logHygiene.js";
import {
  MAX_MATCHES_PER_PASS,
  anonymizeDeletedUserMessages,
  clearLastMessagePreviewIfAuthored,
  deleteSupportAttachmentsForUser,
  deleteUserScopedRemnants,
  flagModerationRecordsForDeletedUser,
} from "./automation/accountDataCleanup.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const auth = getAuth();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const BATCH_LIMIT = 400;

async function deleteQuery(path: string, field: string, uid: string): Promise<void> {
  const snap = await db.collection(path).where(field, "==", uid).get();
  if (snap.empty) {
    return;
  }
  await batchDelete(snap.docs.map((doc) => doc.ref));
}

async function batchDelete(refs: DocumentReference[]): Promise<void> {
  if (!refs.length) {
    return;
  }
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const slice = refs.slice(i, i + BATCH_LIMIT);
    const chunk = db.batch();
    for (const ref of slice) {
      chunk.delete(ref);
    }
    await chunk.commit();
  }
}

async function deleteCollectionDocs(path: string): Promise<void> {
  const snap = await db.collection(path).get();
  await batchDelete(snap.docs.map((d) => d.ref));
}

async function deletePrefix(prefix: string): Promise<void> {
  try {
    await getStorage().bucket().deleteFiles({prefix});
  } catch (error) {
    logger.warn("Storage cleanup skipped", safeLogMeta({prefix, error: String(error)}));
  }
}

function bucketForCleanup() {
  return getStorage().bucket();
}

/// True account deletion: Auth user + Firestore + Storage. isActive=false is not enough.
export const deleteUserAccount = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "unauthenticated");
    }

    const userSnap = await db.doc(`users/${uid}`).get();
    const spotifyId = userSnap.data()?.spotifyId as string | undefined;
    const verificationSnap = await db.doc(`users/${uid}/verification/sumsub`).get();
    const sumsubApplicantId = verificationSnap.data()?.sumsubApplicantId as string | undefined;
    const musicSnap = await db.doc(`users/${uid}/music/summary`).get();
    const musicSpotifyId = musicSnap.data()?.spotifyUserId as string | undefined;

    await Promise.all([
      deleteCollectionDocs(`users/${uid}/devices`),
      deleteCollectionDocs(`users/${uid}/fcmTokens`),
      deleteCollectionDocs(`users/${uid}/blockedUsers`),
      deleteCollectionDocs(`users/${uid}/passedUsers`),
      deleteCollectionDocs(`users/${uid}/boosts`),
      deleteCollectionDocs(`users/${uid}/boostWallet`),
      deleteCollectionDocs(`users/${uid}/matchScoreHistory`),
      deleteCollectionDocs(`users/${uid}/matchFeedback`),
      deleteCollectionDocs(`users/${uid}/pendingMatchFeedback`),
      deleteCollectionDocs(`users/${uid}/relationshipAnswers`),
      deleteCollectionDocs(`users/${uid}/relationshipSeen`),
      deleteCollectionDocs(`users/${uid}/questionAnswers`),
      deleteCollectionDocs(`users/${uid}/subscription`),
      deleteCollectionDocs(`users/${uid}/crypto`),
      deleteCollectionDocs(`users/${uid}/settings`),
      deleteCollectionDocs(`users/${uid}/music`),
      deleteCollectionDocs(`users/${uid}/humor`),
      deleteCollectionDocs(`users/${uid}/humorInteractions`),
      deleteCollectionDocs(`users/${uid}/verification`),
      deleteCollectionDocs(`users/${uid}/rateLimits`),
    ]);

    await deleteQuery("notifications", "userId", uid);
    await deleteQuery("likes", "fromUserId", uid);
    await deleteQuery("likes", "toUserId", uid);

    const presenceRef = db.doc(`users/${uid}/presence/current`);
    await presenceRef.delete().catch(() => undefined);

    // DL-2: the peer is a party to this conversation too. Only the departing
    // user's own messages are erased (tombstoned in place); the peer's are left
    // untouched, and the match resolves to an anonymized deleted-user state.
    const matches = await db
      .collection("matches")
      .where("userIds", "array-contains", uid)
      .limit(MAX_MATCHES_PER_PASS)
      .get();
    for (const match of matches.docs) {
      await anonymizeDeletedUserMessages(db, uid, match.ref);
      await clearLastMessagePreviewIfAuthored(uid, match.ref);
      // Typing indicators only — ephemeral, owned by neither party's history.
      const meta = await match.ref.collection("meta").get();
      await batchDelete(meta.docs.map((d) => d.ref));
      await match.ref.set(
        {
          isActive: false,
          unmatchedBy: uid,
          unmatchedAt: FieldValue.serverTimestamp(),
          participantNames: {[uid]: "Deleted account"},
          participantPhotos: {[uid]: null},
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    // DL-3: reports are moderation evidence — retained and flagged, never deleted
    // with the account they concern. See accountDataCleanup for the reasoning.
    await flagModerationRecordsForDeletedUser(db, uid);

    // Support attachments live outside the users/ and profiles/ prefixes, so they
    // need ownership-resolved cleanup before the ticket documents are removed.
    const support = await deleteSupportAttachmentsForUser(db, bucketForCleanup(), uid);
    await deleteQuery("supportTickets", "userId", uid);
    await deleteQuery("blocks", "blockerId", uid);
    await deleteQuery("blocks", "blockedUserId", uid);
    await deleteQuery("calls", "callerId", uid);
    await deleteQuery("calls", "receiverId", uid);
    await deleteQuery("callHistory", "callerId", uid);
    await deleteQuery("callHistory", "receiverId", uid);
    await deleteQuery("purchases", "userId", uid);

    // Ops queue remnants (best-effort, capped).
    const [reviewQueue, failedNotifs] = await Promise.all([
      db.collection("adminReviewQueue").where("reportedUserId", "==", uid).limit(50).get(),
      db.collection("failedNotifications").where("uid", "==", uid).limit(50).get(),
    ]);
    await batchDelete([
      ...reviewQueue.docs.map((d) => d.ref),
      ...failedNotifs.docs.map((d) => d.ref),
      db.doc(`adminReviewQueue/${uid}`),
    ]);

    await deleteUserScopedRemnants(db, uid);

    await deletePrefix(`users/${uid}/`);
    await deletePrefix(`profiles/${uid}/`);

    if (spotifyId) {
      await db.doc(`spotifyIndex/${spotifyId}`).delete().catch(() => undefined);
    }
    if (musicSpotifyId) {
      await db.doc(`musicSpotifyIndex/${musicSpotifyId}`).delete().catch(() => undefined);
    }

    await batchDelete([
      db.doc(`users/${uid}`),
      db.doc(`users/${uid}/music/summary`),
      db.doc(`users/${uid}/humor/summary`),
      db.doc(`users/${uid}/relationshipMatch/summary`),
      db.doc(`users/${uid}/verification/sumsub`),
      db.doc(`spotifySecrets/${uid}`),
      db.doc(`profiles/${uid}`),
      db.doc(`userPreferences/${uid}`),
      db.doc(`userSettings/${uid}`),
      db.doc(`userPrivacy/${uid}`),
      db.doc(`userLocation/${uid}`),
    ]);

    await requestSumsubApplicantDeletion({uid, applicantId: sumsubApplicantId}).catch(
      (error) => logger.warn("Sumsub applicant cleanup skipped", safeLogMeta({uid, error: String(error)})),
    );

    // A retried deletion reaches here with the Auth record already gone. Treating
    // that as fatal would abort the pass before the verification job is enqueued,
    // and hand the user a failure for an account that is in fact deleted.
    try {
      await auth.deleteUser(uid);
    } catch (error) {
      if ((error as {code?: string}).code !== "auth/user-not-found") {
        throw error;
      }
      logger.info("auth user already deleted", safeLogMeta({uid}));
    }

    // Post-delete verification job (Auth already gone). Processed by
    // processAutomationTask, with automationJobDrain as the fallback.
    try {
      const {enqueueJob, rearmTerminalJob} = await import("./automation/jobs.js");
      const {JobKind} = await import("./automation/types.js");
      const {enqueueCloudTask} = await import("./automation/tasksEnqueue.js");
      const payload = {uid, supportTicketIds: support.ticketIds};
      const {jobId, created} = await enqueueJob({
        kind: JobKind.accountDeletionVerify,
        idempotencyKey: `deletion_verify_${uid}`,
        payload,
        createdBy: "deleteUserAccount",
      });
      if (!created) {
        // A retried deletion must be re-verified: the previous run's verdict
        // describes the state before this pass, not after it.
        await rearmTerminalJob(jobId, payload);
      }
      await enqueueCloudTask(jobId);
    } catch (error) {
      logger.warn("deletion verify enqueue skipped", safeLogMeta({uid, error: String(error)}));
    }

    return {ok: true, deleted: true};
  },
);
