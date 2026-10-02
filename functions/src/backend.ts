import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {logger} from "firebase-functions";
import {canonicalMatchId} from "./ids.js";
import {
  consumeDistanceQuota,
  coarseDistanceLabel,
  distanceDisclosureDecision,
} from "./geo/coarseDistance.js";
import {isAccountEligible} from "./profileSafety.js";
import {assertCallerAccountEligible} from "./accountGuard.js";
import {
  loadActiveMatchPartnerIds,
  passesDiscoveryProfileFilters,
  passesGenderPreferences,
} from "./discoveryMatching.js";
import {attributeBoostEvent} from "./boost/measurement.js";
import {userLanguage} from "./language.js";
import {ensureMatchScore, preservedMatchScoreFields} from "./matchScore.js";
import {haversineKm, isBlocked as isBlockedPair} from "./discoveryPool.js";
import {attributePickMatch, recordPickDecision} from "./picks/service.js";
import {assertDecisionOffered, offeredDecisionSource} from "./picks/decisionScope.js";
import {dailyStreakDocPath, streakExportView} from "./streak/service.js";
import {processPendingProfilePhoto, retryStaleProcessingPhotos} from "./moderation/photoModerationService.js";
import {buildMatchCompatibilityFields} from "./compatibility/compatibilitySnapshot.js";
import {
  cleanupOldCalls,
  cleanupOldNotifications,
} from "./automation/cleanup.js";
import {FcmTypes, sendUserPush} from "./notifications.js";
import {assertAppFeatureAvailable} from "./appOperations/appOperationsGate.js";
import {withoutExactLocation} from "./privacy/exportLocation.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

// Distance disclosure now goes through geo/coarseDistance.ts. The old
// 1 km-resolution formatter is gone: every emitted distance is quantised so a
// caller who moves their own userLocation cannot trilaterate a target.

function isBlocked(a: string, b: string): Promise<boolean> {
  return isBlockedPair(db, a, b);
}

function parsePendingPhotoPath(name: string): {uid: string; imageId: string} | null {
  const match = name.match(/^users\/([^/]+)\/profile\/pending\/([^/]+)$/);
  if (!match) {
    return null;
  }
  const [, uid, rawId] = match;
  const imageId = rawId.replace(/\.(jpg|jpeg|png|webp)$/i, "");
  if (!uid || !imageId) {
    return null;
  }
  return {uid, imageId};
}

/**
 * Retired: the open-ended Discover deck.
 *
 * Mevora is not an endless profile feed. People arrive as the finite daily
 * Mevora Picks batch (`getMevoraPicks`), and deciding quickly never buys more
 * of them. This callable paged the whole pool by cursor with no daily cap, so
 * even with no screen left that calls it, a hand-made request (or an old
 * build) could page through everyone — a way around the daily limit.
 *
 * It stays exported so such a caller gets a clear refusal instead of a 404,
 * and maintenance mode still answers first. The pool scan itself lives on in
 * discoveryPool.ts, where Picks uses it.
 */
export const getDiscoveryCandidates = onCall(callableOptions, async (request) => {
  requireUid(request);
  await assertAppFeatureAvailable(db, null);
  throw new HttpsError("failed-precondition", "discovery-deck-retired");
});

export const getDiscoveryFeed = getDiscoveryCandidates;

export const recordDiscoveryDecision = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, null);
  const candidateUid = String(request.data?.candidateUid ?? request.data?.targetUserId ?? "");
  const action = String(request.data?.action ?? "like");
  if (!candidateUid || candidateUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid candidate.");
  }
  const [callerAccount, callerProfileSnap, callerPrefsSnap, candidateProfile, candidatePrefsSnap, candidateAccountSnap, activeMatches, offeredBy] =
    await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${candidateUid}`).get(),
    db.doc(`userPreferences/${candidateUid}`).get(),
    db.doc(`users/${candidateUid}`).get(),
    loadActiveMatchPartnerIds(db, uid),
    offeredDecisionSource({db, viewerUid: uid, candidateUid}),
  ]);
  if (!isAccountEligible(callerAccount.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  if (activeMatches.has(candidateUid)) {
    throw new HttpsError("failed-precondition", "already-matched");
  }
  // Only someone Picks or Likes You actually showed — checked before any
  // eligibility gate, so a refusal says nothing about a stranger.
  assertDecisionOffered(offeredBy);
  const callerPrefs = callerPrefsSnap.data() ?? {};
  const minAge = Number(callerPrefs.minAge ?? 18);
  const maxAge = Number(callerPrefs.maxAge ?? 99);
  if (
    !candidateProfile.exists ||
    !passesDiscoveryProfileFilters({
      candidateProfile: candidateProfile.data(),
      candidateAccount: candidateAccountSnap.data(),
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
      candidatePrefs: candidatePrefsSnap.data() ?? {},
      candidateProfile: candidateProfile.data() ?? {},
    })
  ) {
    throw new HttpsError("failed-precondition", "preference-mismatch");
  }
  if (await isBlocked(uid, candidateUid)) {
    throw new HttpsError("failed-precondition", "blocked");
  }
  if (action === "pass") {
    await db.doc(`users/${uid}/passedUsers/${candidateUid}`).set({
      toUserId: candidateUid,
      createdAt: FieldValue.serverTimestamp(),
    });
    await db.doc(`likes/${uid}_${candidateUid}`).set({
      fromUserId: uid,
      toUserId: candidateUid,
      action: "pass",
      createdAt: FieldValue.serverTimestamp(),
    });
    await recordPickDecision({db, viewerUid: uid, candidateUid, decision: "passed"});
    return {matched: false};
  }
  await db.doc(`likes/${uid}_${candidateUid}`).set({
    fromUserId: uid,
    toUserId: candidateUid,
    action: action === "superLike" ? "superLike" : "like",
    createdAt: FieldValue.serverTimestamp(),
  });
  // Counted once per (viewer, Boost session), and only when a reach row shows
  // this viewer was actually served the boosted profile while it was running.
  await attributeBoostEvent({db, viewerUid: uid, boostedUid: candidateUid, kind: "like"});
  // Whatever screen the like came from, a liked Pick leaves the active set.
  await recordPickDecision({db, viewerUid: uid, candidateUid, decision: "liked"});

  const reverse = await db.doc(`likes/${candidateUid}_${uid}`).get();
  const reverseAction = reverse.data()?.action as string | undefined;
  const matched = reverse.exists && reverseAction !== "pass";
  if (!matched) {
    await sendUserPush({
      uid: candidateUid,
      type: FcmTypes.incomingLike,
      data: {},
      prefKey: "likeNotifications",
      idempotencyKey: `incomingLike_${uid}_${candidateUid}`,
    });
    return {matched: false};
  }
  const matchId = [uid, candidateUid].sort().join("_");
  const matchRef = db.doc(`matches/${matchId}`);
  let wroteMatch = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    if (snap.exists && snap.data()?.isActive === true) {
      wroteMatch = false;
      return;
    }
    const existing = snap.data();
    wroteMatch = true;
    tx.set(matchRef, {
      userIds: [uid, candidateUid].sort(),
      createdAt: existing?.createdAt ?? FieldValue.serverTimestamp(),
      lastMessage: null,
      lastMessageAt: FieldValue.serverTimestamp(),
      isActive: true,
      unmatchedBy: null,
      unmatchedAt: null,
      unreadCounts: {[uid]: 0, [candidateUid]: 0},
      isNewFor: {[uid]: true, [candidateUid]: true},
      ...preservedMatchScoreFields(existing),
    });
  });
  if (wroteMatch) {
    // wroteMatch is already the idempotent transition, so a retried callable
    // or a replayed trigger cannot count the same match twice. Either side may
    // have been boosted: the one who was seen gets the credit.
    await Promise.all([
      attributeBoostEvent({db, viewerUid: uid, boostedUid: candidateUid, kind: "match"}),
      attributeBoostEvent({db, viewerUid: candidateUid, boostedUid: uid, kind: "match"}),
    ]);
    const fields = await buildMatchCompatibilityFields(uid, candidateUid);
    if (Object.keys(fields).length > 0) {
      await matchRef.set(fields, {merge: true});
    }
    await attributePickMatch({db, matchRef, uidA: uid, uidB: candidateUid});
  }
  return {matched: true, matchId};
});


/**
 * Coarse distance to a user the caller is actually connected to.
 *
 * Previously any authenticated caller could name any otherUid and receive a
 * distance rounded to 1 km. Because a user controls their own userLocation,
 * three queries from three self-chosen positions recovered the target's
 * coordinates — a trilateration oracle over the whole user base.
 *
 * Two independent controls now apply: the target must be an active,
 * non-blocked match, and the disclosed value is quantised to a 5 km band with
 * no raw kilometre figure in the response.
 */
export const getDistanceLabel = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertCallerAccountEligible(db, uid);
  const otherUid = String(request.data?.otherUid ?? "");
  if (!otherUid || otherUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid user.");
  }

  const matchSnap = await db.doc(`matches/${canonicalMatchId(uid, otherUid)}`).get();
  const decision = distanceDisclosureDecision({
    uid,
    otherUid,
    matchData: matchSnap.data(),
    matchExists: matchSnap.exists,
    blocked: await isBlocked(uid, otherUid),
  });
  if (decision === "invalid-target") {
    throw new HttpsError("invalid-argument", "Invalid user.");
  }
  if (decision !== "allow") {
    // One error for both not-matched and blocked: distinguishing them would
    // turn the endpoint into a relationship oracle of its own.
    throw new HttpsError("permission-denied", "not-matched");
  }

  const quota = await consumeDistanceQuota(
    db,
    uid,
    Date.now(),
    FieldValue.serverTimestamp(),
  );
  if (quota === "rate-limited") {
    throw new HttpsError("resource-exhausted", "distance-rate-limit");
  }

  const [mine, other] = await Promise.all([
    db.doc(`userLocation/${uid}`).get(),
    db.doc(`userLocation/${otherUid}`).get(),
  ]);
  const a = mine.data();
  const b = other.data();
  if (!a || !b) {
    return {label: null, labelEn: null, bucketKm: null};
  }
  const km = haversineKm(
    Number(a.latitude),
    Number(a.longitude),
    Number(b.latitude),
    Number(b.longitude),
  );
  const lang = await userLanguage(uid);
  const labels = coarseDistanceLabel(km, lang);
  // No raw kilometre value: the band IS the disclosure budget.
  return {label: labels.label, labelEn: labels.labelEn, bucketKm: labels.bucketKm};
});

export {deleteUserAccount} from "./deleteAccount.js";

export const exportMyData = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const [
    account,
    profile,
    prefs,
    settings,
    privacy,
    location,
    matches,
    likesFrom,
    likesTo,
    blocks,
    reportsFiled,
    purchases,
    supportTickets,
    devices,
    notifSettings,
    subscription,
    music,
    verification,
    questionAnswers,
    personalization,
    dailyStreak,
    relationshipLearning,
    relationshipDaily,
    photoLedger,
    faceAnchorState,
  ] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`userSettings/${uid}`).get(),
    db.doc(`userPrivacy/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.collection("matches").where("userIds", "array-contains", uid).limit(200).get(),
    db.collection("likes").where("fromUserId", "==", uid).limit(200).get(),
    db.collection("likes").where("toUserId", "==", uid).limit(50).get(),
    db.collection("blocks").where("blockerId", "==", uid).limit(100).get(),
    db.collection("reports").where("reporterId", "==", uid).limit(50).get(),
    db.collection("purchases").where("userId", "==", uid).limit(50).get(),
    db.collection("supportTickets").where("userId", "==", uid).limit(50).get(),
    db.collection(`users/${uid}/devices`).limit(20).get(),
    db.doc(`users/${uid}/settings/notifications`).get(),
    db.doc(`users/${uid}/subscription/current`).get(),
    db.doc(`users/${uid}/music/summary`).get(),
    db.doc(`users/${uid}/verification/identity`).get(),
    db.collection(`users/${uid}/questionAnswers`).limit(100).get(),
    db.doc(`users/${uid}/personalization/profile`).get(),
    db.doc(dailyStreakDocPath(uid)).get(),
    db.doc(`users/${uid}/relationshipLearning/state`).get(),
    db.collection(`users/${uid}/relationshipDaily`).limit(400).get(),
    db.collection(`users/${uid}/photoModeration`).limit(50).get(),
    db.doc(`users/${uid}/faceAnchor/state`).get(),
  ]);

  // Never include exact GPS, Spotify secrets, private keys, or message ciphertext bodies.
  const loc = location.data();
  const verificationData = verification.data();
  const musicData = music.data();

  // The account document mirrors the member's position (`location.latitude` /
  // `location.longitude`, written by the app), and the sections below copy
  // whole documents. The finished export is filtered rather than each field,
  // so no section can carry a coordinate or geohash out. City and country stay.
  return withoutExactLocation({
    exportedAt: new Date().toISOString(),
    uid,
    schemaVersion: 2,
    notice:
      "KVKK/GDPR technical export. Exact coordinates, E2EE message bodies, and third-party secrets are omitted. Not a legal compliance certificate.",
    account: sanitizeAccountExport(account.data()),
    profile: profile.data() ?? null,
    preferences: prefs.data() ?? null,
    settings: settings.data() ?? null,
    privacy: privacy.data() ?? null,
    notificationSettings: notifSettings.data() ?? null,
    // Learned recommendation weights: per-dimension adjustments and evidence
    // totals only. They contain no other member's data.
    recommendationPersonalization: personalization.data() ?? null,
    // Engagement only: streak counters and the last local day counted.
    dailyStreak: streakExportView(dailyStreak.data()),
    // The member's own Relationship Learning answers and progress.
    relationshipLearning: relationshipLearning.data() ?? null,
    // One record per daily question set they completed.
    relationshipDailyCompletions: relationshipDaily.docs.map((d) => ({id: d.id, ...d.data()})),
    location: loc
      ? {
        present: true,
        updatedAt: loc.updatedAt ?? null,
        // Coarse only — no lat/lng/geohash in export file left on device shares.
        hasCoordinates: typeof loc.latitude === "number",
      }
      : {present: false},
    subscription: subscription.data()
      ? {
        isPremium: subscription.data()?.isPremium === true,
        expiresAt: subscription.data()?.expiresAt ?? null,
        productId: subscription.data()?.productId ?? null,
      }
      : null,
    music: musicData
      ? {
        spotifyConnected: musicData.spotifyConnected === true,
        displayName: musicData.displayName ?? null,
        // No access/refresh tokens.
      }
      : null,
    verification: verificationData
      ? {
        status: verificationData.status ?? null,
        provider: verificationData.provider ?? null,
        reason: verificationData.reason ?? null,
        verifiedAt: verificationData.verifiedAt ?? null,
        updatedAt: verificationData.updatedAt ?? null,
        // Everything MEVORA holds about identity verification is above.
        // The provider session id is backend-only correlation, not user
        // data, and the document images, selfie, liveness video and
        // extracted identity fields were never stored here to export.
      }
      : null,
    // Face Anchor: which profile photos were verified as the member, when the
    // member agreed to the selfie check, and how the last attempt ended.
    // There is nothing else to export: the verification selfie is deleted when
    // the check finishes and no score, face template or provider response is
    // ever stored.
    faceAnchor: {
      verifiedPhotos: photoLedger.docs
        .filter((d) => d.get("faceAnchor.status") === "verified")
        .map((d) => ({photoId: d.id, verifiedAt: d.get("faceAnchor.verifiedAt") ?? null})),
      lastAttempt: faceAnchorState.exists
        ? {
          status: faceAnchorState.get("status") ?? null,
          reason: faceAnchorState.get("reason") ?? null,
          photoId: faceAnchorState.get("photoId") ?? null,
          consentVersion: faceAnchorState.get("consentVersion") ?? null,
          consentAt: faceAnchorState.get("consentAt") ?? null,
          updatedAt: faceAnchorState.get("updatedAt") ?? null,
        }
        : null,
    },
    questionAnswers: questionAnswers.docs.map((d) => ({id: d.id, ...d.data()})),
    matchIds: matches.docs.map((d) => d.id),
    likesSent: likesFrom.docs.map((d) => ({
      id: d.id,
      toUserId: d.data().toUserId ?? null,
      action: d.data().action ?? null,
      createdAt: d.data().createdAt ?? null,
    })),
    likesReceivedCount: likesTo.size,
    blocks: blocks.docs.map((d) => ({
      blockedUserId: d.data().blockedUserId ?? null,
      createdAt: d.data().createdAt ?? null,
    })),
    reportsFiled: reportsFiled.docs.map((d) => ({
      id: d.id,
      reportedUserId: d.data().reportedUserId ?? null,
      reason: d.data().reason ?? null,
      status: d.data().status ?? null,
      createdAt: d.data().createdAt ?? null,
    })),
    purchases: purchases.docs.map((d) => ({
      id: d.id,
      productId: d.data().productId ?? null,
      platform: d.data().platform ?? null,
      status: d.data().status ?? null,
      createdAt: d.data().createdAt ?? null,
    })),
    supportTickets: supportTickets.docs.map((d) => ({
      id: d.id,
      subject: d.data().subject ?? null,
      status: d.data().status ?? null,
      createdAt: d.data().createdAt ?? null,
    })),
    devices: devices.docs.map((d) => ({
      id: d.id,
      platform: d.data().platform ?? null,
      updatedAt: d.data().updatedAt ?? d.data().createdAt ?? null,
      // FCM token omitted.
    })),
  });
});

function sanitizeAccountExport(data: DocumentData | undefined): Record<string, unknown> | null {
  if (!data) {
    return null;
  }
  const {
    // strip nothing critical except we avoid copying unknown secret-looking keys
    ...rest
  } = data;
  const out: Record<string, unknown> = {...rest};
  for (const key of Object.keys(out)) {
    if (/token|secret|password|private/i.test(key)) {
      delete out[key];
    }
  }
  return out;
}

export const onProfilePhotoUploaded = onObjectFinalized(
  {region: "us-east1"},
  async (event) => {
    const name = event.data.name ?? "";
    const parsed = parsePendingPhotoPath(name);
    if (!parsed) {
      return;
    }
    const {uid, imageId} = parsed;
    const bucket = getStorage().bucket(event.data.bucket);
    await processPendingProfilePhoto({
      db,
      bucket,
      uid,
      imageId,
      pendingPath: name,
      contentType: event.data.contentType,
      sizeBytes: Number(event.data.size ?? 0),
    });
  },
);

export const retentionCleanup = onSchedule(
  {schedule: "every 24 hours", region: "europe-west1"},
  async () => {
    // Kept for backward-compatible deploy name; prefer automationDailySchedule for full suite.
    const notif = await cleanupOldNotifications({
      dryRun: false,
      limit: 400,
      requireAdminApproval: false,
    });
    const calls = await cleanupOldCalls({
      dryRun: false,
      limit: 200,
      requireAdminApproval: false,
    });
    const retriedPhotos = await retryStaleProcessingPhotos(db, getStorage().bucket());
    logger.info("Retention cleanup complete", {
      notifications: notif.deleted,
      calls: calls.deleted,
      retriedPhotos,
    });
  },
);

export const health = onCall(callableOptions, async () => {
  const [failedJobs, openReports, openReviews] = await Promise.all([
    db.collection("automationJobs").where("status", "==", "failed").limit(1).get(),
    db.collection("reports").where("status", "==", "open").limit(1).get(),
    db.collection("adminReviewQueue").where("status", "==", "open").limit(1).get(),
  ]);
  return {
    status: "ok",
    service: "mevora",
    region: "europe-west1",
    signals: {
      hasFailedJobs: !failedJobs.empty,
      hasOpenReports: !openReports.empty,
      hasOpenReviews: !openReviews.empty,
    },
    checkedAt: new Date().toISOString(),
  };
});

export const syncAuthAccount = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const record = await getAuth().getUser(uid);
  const phoneNumber = record.phoneNumber ?? null;
  await db.doc(`users/${uid}`).set(
    {
      uid,
      phoneNumber,
      phoneVerified: Boolean(phoneNumber),
      lastLoginAt: FieldValue.serverTimestamp(),
      lastActiveAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await ensureMatchScore(uid);
  return {ok: true};
});

