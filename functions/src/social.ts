import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";
import {AccessToken} from "livekit-server-sdk";
import {blockId, canonicalMatchId, likeId, previewText} from "./ids.js";
import {
  loadActiveMatchPartnerIds,
  passesDiscoveryProfileFilters,
  passesGenderPreferences,
} from "./discoveryMatching.js";
import {isAccountEligible} from "./profileSafety.js";
import {markProfilePhotosForManualReview} from "./moderation/photoModerationService.js";
import {
  applyMessageSideEffects,
  preservedMatchScoreFields,
  queuePostMatchFeedback,
} from "./matchScore.js";
import {enforceMessageRateLimit} from "./messageRateLimit.js";
import {FcmTypes, sendUserPush} from "./notifications.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const livekitApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");
const livekitUrl = defineSecret("LIVEKIT_URL");
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const socialCallable = {enforceAppCheck, region: "europe-west1" as const};

const REPORT_REASONS = new Set([
  "spam",
  "harassment",
  "inappropriate_content",
  "scam",
  "fake_profile",
  "underage",
  "other",
]);
const MAX_REPORTS_PER_DAY = 20;

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

async function isBlocked(a: string, b: string): Promise<boolean> {
  const [first, second, subA, subB] = await Promise.all([
    db.doc(`blocks/${blockId(a, b)}`).get(),
    db.doc(`blocks/${blockId(b, a)}`).get(),
    db.doc(`users/${a}/blockedUsers/${b}`).get(),
    db.doc(`users/${b}/blockedUsers/${a}`).get(),
  ]);
  return first.exists || second.exists || subA.exists || subB.exists;
}

async function profilePreview(uid: string): Promise<{name: string; photoUrl?: string; isVerified: boolean}> {
  const [profileSnap, userSnap] = await Promise.all([
    db.doc(`profiles/${uid}`).get(),
    db.doc(`users/${uid}`).get(),
  ]);
  const data = profileSnap.data() ?? {};
  const account = userSnap.data() ?? {};
  return {
    name: String(data.displayName ?? account.displayName ?? account.name ?? "Mevora"),
    photoUrl: (data.photoUrl ?? account.photoUrl) as string | undefined,
    isVerified: account.isVerified === true,
  };
}

async function endActiveCallsForMatch(matchId: string): Promise<void> {
  const ringing = await db
    .collection("calls")
    .where("matchId", "==", matchId)
    .where("status", "in", ["ringing", "calling", "connecting", "connected"])
    .get();
  if (ringing.empty) {
    return;
  }
  const batch = db.batch();
  ringing.docs.forEach((doc) => batch.update(doc.ref, {status: "ended", endedAt: FieldValue.serverTimestamp()}));
  await batch.commit();
}

export const recordSwipe = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const targetUserId = String(request.data?.targetUserId ?? "");
  const action = String(request.data?.action ?? "like");
  if (!targetUserId || targetUserId === uid) {
    throw new HttpsError("invalid-argument", "self");
  }
  const [
    callerAccount,
    callerProfileSnap,
    callerPrefsSnap,
    targetProfileSnap,
    targetPrefsSnap,
    targetAccountSnap,
    activeMatches,
  ] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${targetUserId}`).get(),
    db.doc(`userPreferences/${targetUserId}`).get(),
    db.doc(`users/${targetUserId}`).get(),
    loadActiveMatchPartnerIds(db, uid),
  ]);
  if (!isAccountEligible(callerAccount.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  if (activeMatches.has(targetUserId)) {
    throw new HttpsError("failed-precondition", "already-matched");
  }
  const callerPrefs = callerPrefsSnap.data() ?? {};
  const minAge = Number(callerPrefs.minAge ?? 18);
  const maxAge = Number(callerPrefs.maxAge ?? 99);
  if (
    !targetProfileSnap.exists ||
    !passesDiscoveryProfileFilters({
      candidateProfile: targetProfileSnap.data(),
      candidateAccount: targetAccountSnap.data(),
      minAge,
      maxAge,
    })
  ) {
    throw new HttpsError("failed-precondition", "candidate-unavailable");
  }
  if (
    !passesGenderPreferences({
      viewerPrefs: callerPrefs,
      viewerProfile: callerProfileSnap.data() ?? {},
      candidatePrefs: targetPrefsSnap.data() ?? {},
      candidateProfile: targetProfileSnap.data() ?? {},
    })
  ) {
    throw new HttpsError("failed-precondition", "preference-mismatch");
  }
  if (await isBlocked(uid, targetUserId)) {
    throw new HttpsError("failed-precondition", "blocked");
  }
  const forwardId = likeId(uid, targetUserId);
  const reverseId = likeId(targetUserId, uid);
  const matchId = canonicalMatchId(uid, targetUserId);
  return db.runTransaction(async (tx) => {
    const forwardRef = db.doc(`likes/${forwardId}`);
    const existing = await tx.get(forwardRef);
    if (existing.exists) {
      throw new HttpsError("already-exists", "already-swiped");
    }
    tx.set(forwardRef, {
      fromUserId: uid,
      toUserId: targetUserId,
      action,
      createdAt: FieldValue.serverTimestamp(),
    });
    if (action === "pass") {
      return {matched: false};
    }
    const reverse = await tx.get(db.doc(`likes/${reverseId}`));
    const reverseAction = reverse.data()?.action as string | undefined;
    const positive = reverse.exists && reverseAction !== "pass";
    if (!positive) {
      return {matched: false};
    }
    const matchRef = db.doc(`matches/${matchId}`);
    const matchSnap = await tx.get(matchRef);
    if (matchSnap.exists && matchSnap.data()?.isActive === true) {
      return {matched: true, matchId};
    }
    const actor = await profilePreview(uid);
    const other = await profilePreview(targetUserId);
    const previousMatch = matchSnap.data();
    tx.set(matchRef, {
      userIds: [uid, targetUserId].sort(),
      createdAt: previousMatch?.createdAt ?? FieldValue.serverTimestamp(),
      lastMessage: null,
      lastMessageAt: FieldValue.serverTimestamp(),
      isActive: true,
      unmatchedBy: null,
      unmatchedAt: null,
      unreadCounts: {[uid]: 0, [targetUserId]: 0},
      isNewFor: {[uid]: true, [targetUserId]: true},
      participantNames: {[uid]: actor.name, [targetUserId]: other.name},
      participantPhotos: {
        ...(actor.photoUrl ? {[uid]: actor.photoUrl} : {}),
        ...(other.photoUrl ? {[targetUserId]: other.photoUrl} : {}),
      },
      participantVerified: {
        [uid]: actor.isVerified,
        [targetUserId]: other.isVerified,
      },
      ...preservedMatchScoreFields(previousMatch),
      source: "mutual_like",
    });
    return {matched: true, matchId};
  });
});

export const unmatchUser = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const matchId = String(request.data?.matchId ?? "");
  const ref = db.doc(`matches/${matchId}`);
  const snap = await ref.get();
  if (!snap.exists || !((snap.data()?.userIds as string[]) ?? []).includes(uid)) {
    throw new HttpsError("permission-denied", "not-matched");
  }
  const userIds = (snap.data()?.userIds as string[]) ?? [];
  await ref.update({
    isActive: false,
    unmatchedBy: uid,
    unmatchedAt: FieldValue.serverTimestamp(),
    endedReason: "unmatch",
  });
  await queuePostMatchFeedback({
    matchId,
    endedBy: uid,
    reason: "unmatch",
    userIds,
  });
  await endActiveCallsForMatch(matchId);
  return {ok: true};
});

export const blockUser = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const userId = String(request.data?.userId ?? "");
  if (!userId || userId === uid) {
    throw new HttpsError("invalid-argument", "self");
  }
  await db.doc(`blocks/${blockId(uid, userId)}`).set({
    blockerId: uid,
    blockedUserId: userId,
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`users/${uid}/blockedUsers/${userId}`).set({
    blockedUserId: userId,
    createdAt: FieldValue.serverTimestamp(),
  });
  const matchId = canonicalMatchId(uid, userId);
  const matchRef = db.doc(`matches/${matchId}`);
  const match = await matchRef.get();
  if (match.exists) {
    const userIds = (match.data()?.userIds as string[]) ?? [];
    await matchRef.update({
      isActive: false,
      unmatchedBy: uid,
      unmatchedAt: FieldValue.serverTimestamp(),
      endedReason: "block",
    });
    await queuePostMatchFeedback({
      matchId,
      endedBy: uid,
      reason: "block",
      userIds,
    });
  }
  await endActiveCallsForMatch(matchId);
  return {ok: true};
});

export const reportUser = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const userId = String(request.data?.userId ?? "").trim();
  const reason = String(request.data?.reason ?? "other").trim();
  if (!userId || userId === uid) {
    throw new HttpsError("invalid-argument", "invalid-target");
  }
  if (!REPORT_REASONS.has(reason)) {
    throw new HttpsError("invalid-argument", "invalid-reason");
  }
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const recent = await db
    .collection("reports")
    .where("reporterId", "==", uid)
    .where("createdAt", ">=", since)
    .limit(MAX_REPORTS_PER_DAY)
    .get();
  if (recent.size >= MAX_REPORTS_PER_DAY) {
    throw new HttpsError("resource-exhausted", "report-rate-limit");
  }
  await db.collection("reports").add({
    reporterId: uid,
    reportedUserId: userId,
    matchId: request.data?.matchId ?? null,
    messageId: request.data?.messageId ?? null,
    reason,
    description: request.data?.description ?? null,
    createdAt: FieldValue.serverTimestamp(),
    status: "open",
  });
  await markProfilePhotosForManualReview(db, userId, `report:${reason}`);
  return {ok: true};
});

async function mintLivekitToken(identity: string, roomName: string): Promise<{token: string; url: string}> {
  const key = livekitApiKey.value();
  const secret = livekitApiSecret.value();
  const url = livekitUrl.value();
  if (!key || !secret || !url) {
    throw new HttpsError("failed-precondition", "not-configured");
  }
  const token = new AccessToken(key, secret, {identity, ttl: "2m"});
  token.addGrant({roomJoin: true, room: roomName, canPublish: true, canSubscribe: true});
  return {token: await token.toJwt(), url};
}

export const createVideoCall = onCall(
  {region: "europe-west1", secrets: [livekitApiKey, livekitApiSecret, livekitUrl]},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const matchId = String(request.data?.matchId ?? "");
    const receiverId = String(request.data?.receiverId ?? "");
    const match = await db.doc(`matches/${matchId}`).get();
    const userIds = (match.data()?.userIds as string[]) ?? [];
    if (!match.exists || match.data()?.isActive !== true || !userIds.includes(uid) || !userIds.includes(receiverId)) {
      throw new HttpsError("permission-denied", "not-matched");
    }
    if (await isBlocked(uid, receiverId)) {
      throw new HttpsError("failed-precondition", "blocked");
    }
    const busy = await db
      .collection("calls")
      .where("receiverId", "==", receiverId)
      .where("status", "in", ["ringing", "connecting", "connected"])
      .limit(1)
      .get();
    if (!busy.empty) {
      throw new HttpsError("failed-precondition", "busy");
    }
    const callRef = db.collection("calls").doc();
    const roomName = `call_${callRef.id}`;
    const minted = await mintLivekitToken(uid, roomName);
    const actor = await profilePreview(uid);
    await callRef.set({
      callerId: uid,
      receiverId,
      matchId,
      participantIds: [uid, receiverId],
      type: "video",
      status: "ringing",
      roomName,
      createdAt: FieldValue.serverTimestamp(),
      remoteName: actor.name,
      remotePhotoUrl: actor.photoUrl ?? null,
    });
    return {callId: callRef.id, token: minted.token, url: minted.url, roomName};
  },
);

export const respondToVideoCall = onCall(
  {region: "europe-west1", secrets: [livekitApiKey, livekitApiSecret, livekitUrl]},
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const callId = String(request.data?.callId ?? "");
    const accept = request.data?.accept === true;
    const ref = db.doc(`calls/${callId}`);
    const snap = await ref.get();
    if (!snap.exists || snap.data()?.receiverId !== uid) {
      throw new HttpsError("permission-denied", "not-found");
    }
    if (!accept) {
      await ref.update({status: "declined", endedAt: FieldValue.serverTimestamp()});
      await db.doc(`callHistory/${callId}`).set({
        callerId: snap.data()?.callerId,
        receiverId: snap.data()?.receiverId,
        participantIds: [snap.data()?.callerId, snap.data()?.receiverId],
        matchId: snap.data()?.matchId,
        type: "video",
        status: "declined",
        endedAt: FieldValue.serverTimestamp(),
        duration: 0,
      });
      return {ok: true};
    }
    const roomName = String(snap.data()?.roomName ?? `call_${callId}`);
    const minted = await mintLivekitToken(uid, roomName);
    await ref.update({status: "connecting"});
    return {
      token: minted.token,
      url: minted.url,
      roomName,
      matchId: snap.data()?.matchId,
      callerId: snap.data()?.callerId,
    };
  },
);

export const endVideoCall = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const callId = String(request.data?.callId ?? "");
  const ref = db.doc(`calls/${callId}`);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || (data?.callerId !== uid && data?.receiverId !== uid)) {
    throw new HttpsError("permission-denied", "not-found");
  }
  const ringing = data?.status === "ringing" || data?.status === "calling";
  const cancelledByCaller = ringing && data?.callerId === uid;
  const status = cancelledByCaller ? "cancelled" : "ended";
  await ref.update({status, endedAt: FieldValue.serverTimestamp()});
  await db.doc(`callHistory/${callId}`).set({
    callerId: data?.callerId,
    receiverId: data?.receiverId,
    participantIds: [data?.callerId, data?.receiverId],
    matchId: data?.matchId,
    type: "video",
    status: cancelledByCaller ? "cancelled" : "completed",
    startedAt: data?.createdAt ?? FieldValue.serverTimestamp(),
    endedAt: FieldValue.serverTimestamp(),
    duration: 0,
  });
  return {ok: true};
});

export const expireVideoCall = onCall(socialCallable, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const callId = String(request.data?.callId ?? "");
  const ref = db.doc(`calls/${callId}`);
  const snap = await ref.get();
  const data = snap.data();
  if (!snap.exists || (data?.callerId !== uid && data?.receiverId !== uid)) {
    throw new HttpsError("permission-denied", "not-found");
  }
  if (data?.status !== "ringing" && data?.status !== "calling") {
    return {ok: true};
  }
  await ref.update({status: "missed", endedAt: FieldValue.serverTimestamp()});
  await db.doc(`callHistory/${callId}`).set({
    callerId: data.callerId,
    receiverId: data.receiverId,
    participantIds: [data.callerId, data.receiverId],
    matchId: data.matchId,
    type: "video",
    status: "missed",
    startedAt: data.createdAt,
    endedAt: FieldValue.serverTimestamp(),
    duration: 0,
  });
  return {ok: true};
});

export const sendMessageNotification = onDocumentCreated(
  {
    document: "matches/{matchId}/messages/{messageId}",
    region: "europe-west1",
  },
  async (event) => {
    const snap = event.data;
    const data = snap?.data();
    const matchId = event.params.matchId;
    if (!snap || !data) {
      return;
    }
    const senderId = String(data.senderId ?? "");
    const receiverId = String(data.receiverId ?? "");
    const allowed = await enforceMessageRateLimit({
      matchId,
      messageId: event.params.messageId,
      senderId,
      type: String(data.type ?? "text"),
      messageRef: snap.ref,
    });
    if (!allowed) {
      return;
    }
    if (await isBlocked(senderId, receiverId)) {
      return;
    }
    const type = String(data.type ?? "text");
    const lastMessage = data.deleted === true
      ? ""
      : type === "image"
        ? "📷"
        : type === "voice"
          ? "🎤"
          : previewText(String(data.text ?? ""));
    await applyMessageSideEffects({
      matchId,
      senderId,
      receiverId,
      lastMessage,
    });
    await sendUserPush({
      uid: receiverId,
      type: type === "image"
        ? FcmTypes.newPhoto
        : type === "voice"
          ? FcmTypes.newVoice
          : FcmTypes.newMessage,
      data: {matchId},
      prefKey: "messageNotifications",
    });
  },
);

export const sendMatchNotification = onDocumentCreated(
  {
    document: "matches/{matchId}",
    region: "europe-west1",
  },
  async (event) => {
    const data = event.data?.data();
    const userIds = (data?.userIds as string[]) ?? [];
    for (const uid of userIds) {
      await sendUserPush({
        uid,
        type: FcmTypes.newMatch,
        data: {matchId: event.params.matchId},
        prefKey: "matchNotifications",
      });
    }
  },
);
