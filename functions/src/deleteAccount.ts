import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, type DocumentReference} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {requestSumsubApplicantDeletion} from "./sumsub/sumsubApplicantLifecycle.js";
import {safeLogMeta} from "./security/logHygiene.js";

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
    // A Spotify account is reachable under its legacy user id and its
    // immutable account_id. Both index documents have to go, or the
    // account stays 'owned' by a uid that no longer exists.
    const spotifyIndexKeys =
      (userSnap.data()?.spotifyIndexKeys as string[] | undefined) ?? [];
    const verificationSnap = await db.doc(`users/${uid}/verification/sumsub`).get();
    const sumsubApplicantId = verificationSnap.data()?.sumsubApplicantId as string | undefined;
    const musicSnap = await db.doc(`users/${uid}/music/summary`).get();
    const musicSpotifyId = musicSnap.data()?.spotifyUserId as string | undefined;
    const musicSpotifyAccountId =
      musicSnap.data()?.spotifyAccountId as string | undefined;

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
      deleteCollectionDocs(`users/${uid}/photoModeration`),
      deleteCollectionDocs(`users/${uid}/rateLimits`),
    ]);

    await deleteQuery("notifications", "userId", uid);
    await deleteQuery("likes", "fromUserId", uid);
    await deleteQuery("likes", "toUserId", uid);

    const presenceRef = db.doc(`users/${uid}/presence/current`);
    await presenceRef.delete().catch(() => undefined);

    const matches = await db.collection("matches").where("userIds", "array-contains", uid).get();
    for (const match of matches.docs) {
      const [messages, meta] = await Promise.all([
        match.ref.collection("messages").get(),
        match.ref.collection("meta").get(),
      ]);
      await batchDelete([
        ...messages.docs.map((d) => d.ref),
        ...meta.docs.map((d) => d.ref),
      ]);
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

    await deleteQuery("reports", "reporterId", uid);
    await deleteQuery("reports", "reportedUserId", uid);
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

    await deletePrefix(`users/${uid}/`);
    await deletePrefix(`profiles/${uid}/`);

    for (const key of new Set(
      [spotifyId, ...spotifyIndexKeys].filter(Boolean) as string[],
    )) {
      await db.doc(`spotifyIndex/${key}`).delete().catch(() => undefined);
    }
    for (const key of new Set(
      [musicSpotifyId, musicSpotifyAccountId].filter(Boolean) as string[],
    )) {
      await db.doc(`musicSpotifyIndex/${key}`).delete().catch(() => undefined);
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

    await auth.deleteUser(uid);

    // Post-delete verification job (Auth already gone). Processed by automation drain.
    try {
      const {enqueueJob} = await import("./automation/jobs.js");
      const {JobKind} = await import("./automation/types.js");
      const {enqueueCloudTask} = await import("./automation/tasksEnqueue.js");
      const {jobId} = await enqueueJob({
        kind: JobKind.accountDeletionVerify,
        idempotencyKey: `deletion_verify_${uid}`,
        payload: {uid},
        createdBy: "deleteUserAccount",
      });
      await enqueueCloudTask(jobId);
    } catch (error) {
      logger.warn("deletion verify enqueue skipped", safeLogMeta({uid, error: String(error)}));
    }

    return {ok: true, deleted: true};
  },
);
