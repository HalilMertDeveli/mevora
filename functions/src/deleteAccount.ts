import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, type DocumentReference} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {requestSumsubApplicantDeletion} from "./sumsub/sumsubApplicantLifecycle.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const auth = getAuth();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

async function deleteQuery(path: string, field: string, uid: string): Promise<void> {
  const snap = await db.collection(path).where(field, "==", uid).get();
  if (snap.empty) {
    return;
  }
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

async function batchDelete(refs: DocumentReference[]): Promise<void> {
  if (!refs.length) {
    return;
  }
  const chunk = db.batch();
  for (const ref of refs) {
    chunk.delete(ref);
  }
  await chunk.commit();
}

async function deletePrefix(prefix: string): Promise<void> {
  try {
    await getStorage().bucket().deleteFiles({prefix});
  } catch (error) {
    logger.warn("Storage cleanup skipped", {prefix, error});
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
    const verificationSnap = await db.doc(`users/${uid}/verification/sumsub`).get();
    const sumsubApplicantId = verificationSnap.data()?.sumsubApplicantId as string | undefined;
    const musicSnap = await db.doc(`users/${uid}/music/summary`).get();
    const musicSpotifyId = musicSnap.data()?.spotifyUserId as string | undefined;

    const [devices, tokens, blocked, notifs, likesFrom, likesTo, boosts, wallet, scoreHistory, feedback, pendingFeedback, relationshipAnswers] = await Promise.all([
      db.collection(`users/${uid}/devices`).get(),
      db.collection(`users/${uid}/fcmTokens`).get(),
      db.collection(`users/${uid}/blockedUsers`).get(),
      db.collection("notifications").where("userId", "==", uid).get(),
      db.collection("likes").where("fromUserId", "==", uid).get(),
      db.collection("likes").where("toUserId", "==", uid).get(),
      db.collection(`users/${uid}/boosts`).get(),
      db.collection(`users/${uid}/boostWallet`).get(),
      db.collection(`users/${uid}/matchScoreHistory`).get(),
      db.collection(`users/${uid}/matchFeedback`).get(),
      db.collection(`users/${uid}/pendingMatchFeedback`).get(),
      db.collection(`users/${uid}/relationshipAnswers`).get(),
    ]);
    await batchDelete([
      ...devices.docs.map((d) => d.ref),
      ...tokens.docs.map((d) => d.ref),
      ...blocked.docs.map((d) => d.ref),
      ...notifs.docs.map((d) => d.ref),
      ...likesFrom.docs.map((d) => d.ref),
      ...likesTo.docs.map((d) => d.ref),
      ...boosts.docs.map((d) => d.ref),
      ...wallet.docs.map((d) => d.ref),
      ...scoreHistory.docs.map((d) => d.ref),
      ...feedback.docs.map((d) => d.ref),
      ...pendingFeedback.docs.map((d) => d.ref),
      ...relationshipAnswers.docs.map((d) => d.ref),
    ]);

    const matches = await db.collection("matches").where("userIds", "array-contains", uid).get();
    for (const match of matches.docs) {
      const messages = await match.ref.collection("messages").get();
      await batchDelete(messages.docs.map((d) => d.ref));
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
    await deleteQuery("blocks", "blockerId", uid);
    await deleteQuery("blocks", "blockedUserId", uid);
    await deleteQuery("calls", "callerId", uid);
    await deleteQuery("purchases", "userId", uid);

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
      (error) => logger.warn("Sumsub applicant cleanup skipped", {uid, error: String(error)}),
    );

    await auth.deleteUser(uid);
    return {ok: true, deleted: true};
  },
);
