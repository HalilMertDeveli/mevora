import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentData,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {logger} from "firebase-functions";
import {blockId} from "./ids.js";
import {
  isAccountEligible,
  publicProfileProjection,
  resolveProfileAge,
} from "./profileSafety.js";
import {
  loadActiveMatchPartnerIds,
  loadPreferencesByUid,
  passesDiscoveryProfileFilters,
  passesGenderPreferences,
} from "./discoveryMatching.js";
import {loadActiveBoostedUserIds, sortByBoostVisibility} from "./boost/ranking.js";
import {userLanguage} from "./language.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {musicRankingBonus} from "./musicCompatibility.js";
import {ensureMatchScore, preservedMatchScoreFields} from "./matchScore.js";
import {musicScoreForPair} from "./spotifyMusic.js";
import {relationshipScoreForPair} from "./relationshipMatch.js";
import {processPendingProfilePhoto, retryStaleProcessingPhotos} from "./moderation/photoModerationService.js";
import {calculateCompatibility} from "./compatibility/compatibilityEngine.js";
import {passesSmokeDiscoveryIsolation} from "./smoke/smokeTestUsers.js";

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

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const sLat = Math.sin(dLat / 2);
  const sLng = Math.sin(dLng / 2);
  const h =
    sLat * sLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sLng * sLng;
  return 2 * 6371 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

function distanceLabel(km: number, lang: "tr" | "en"): {label: string; labelEn: string} {
  const labelEn =
    km < 1 ? "Less than 1 km away" : km >= 100 ? "100+ km away" : `${Math.round(km)} km away`;
  const labelTr =
    km < 1 ? "1 km'den yakın" : km >= 100 ? "100+ km uzakta" : `${Math.round(km)} km uzakta`;
  return {label: lang === "tr" ? labelTr : labelEn, labelEn};
}

async function isBlocked(a: string, b: string): Promise<boolean> {
  const [subA, subB, topA, topB] = await Promise.all([
    db.doc(`users/${a}/blockedUsers/${b}`).get(),
    db.doc(`users/${b}/blockedUsers/${a}`).get(),
    db.doc(`blocks/${blockId(a, b)}`).get(),
    db.doc(`blocks/${blockId(b, a)}`).get(),
  ]);
  return subA.exists || subB.exists || topA.exists || topB.exists;
}

async function loadUserAccounts(uids: string[]): Promise<Map<string, DocumentData>> {
  const unique = [...new Set(uids.filter(Boolean))];
  const entries = await Promise.all(
    unique.map(async (uid) => {
      const snap = await db.doc(`users/${uid}`).get();
      return [uid, snap.data()] as const;
    }),
  );
  return new Map(entries.filter(([, data]) => data != null) as Array<[string, DocumentData]>);
}

async function loadBlockedUserIds(uid: string): Promise<Set<string>> {
  const [subSnap, blockedSnap, blockerSnap] = await Promise.all([
    db.collection(`users/${uid}/blockedUsers`).get(),
    db.collection("blocks").where("blockerId", "==", uid).get(),
    db.collection("blocks").where("blockedUserId", "==", uid).get(),
  ]);
  const blocked = new Set<string>();
  subSnap.docs.forEach((doc) => blocked.add(doc.id));
  blockedSnap.docs.forEach((doc) => {
    const other = String(doc.get("blockedUserId") ?? "");
    if (other) blocked.add(other);
  });
  blockerSnap.docs.forEach((doc) => {
    const other = String(doc.get("blockerId") ?? "");
    if (other) blocked.add(other);
  });
  return blocked;
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

export const getDiscoveryCandidates = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const callerAccount = await db.doc(`users/${uid}`).get();
  if (!isAccountEligible(callerAccount.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  const allowedRadii = new Set([5, 10, 25, 50, 100]);
  const requested = Number(request.data?.radiusKm ?? 25);
  const radiusKm = allowedRadii.has(requested) ? requested : 25;
  const limit = Math.min(Math.max(Number(request.data?.limit ?? 10), 1), 20);
  const cursor = String(request.data?.cursor ?? "");
  const [prefsSnap, viewerProfileSnap, locationSnap, blocked, likesSnap, passedSnap, boosted, activeMatches] =
    await Promise.all([
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    loadBlockedUserIds(uid),
    db.collection("likes").where("fromUserId", "==", uid).get(),
    db.collection(`users/${uid}/passedUsers`).get(),
    loadActiveBoostedUserIds(db),
    loadActiveMatchPartnerIds(db, uid),
  ]);
  const seen = new Set(likesSnap.docs.map((doc) => String(doc.get("toUserId") ?? "")));
  for (const doc of passedSnap.docs) seen.add(doc.id);
  for (const partner of activeMatches) seen.add(partner);
  seen.add(uid);
  const prefs = prefsSnap.data() ?? {};
  if (prefs.discoveryEnabled === false) {
    return {items: [], nextCursor: null};
  }
  const viewerProfile = viewerProfileSnap.data() ?? {};
  const lang = await userLanguage(uid);
  const minAge = Number(prefs.minAge ?? 18);
  const maxAge = Number(prefs.maxAge ?? 99);
  const origin = locationSnap.data();
  let query = db
    .collection("profiles")
    .where("isDiscoverable", "==", true)
    .where("profileCompleted", "==", true)
    .orderBy("updatedAt", "desc")
    .limit(40);
  if (cursor) {
    const cursorSnap = await db.doc(`profiles/${cursor}`).get();
    if (cursorSnap.exists) {
      query = query.startAfter(cursorSnap);
    }
  }
  const profiles = await query.get();
  // lastActiveAt is on private users/{uid}. Filter here so inactive
  // profiles never reach the client. Window: 90 days. Missing field = new user.
  const candidateUids = profiles.docs.map((doc) => doc.id);
  const [lastActiveByUid, accountsByUid, preferencesByUid] = await Promise.all([
    loadLastActiveAt(db, candidateUids),
    loadUserAccounts(candidateUids),
    loadPreferencesByUid(db, candidateUids),
  ]);
  const items: Array<Record<string, unknown>> = [];
  let lastUid: string | null = null;
  for (const doc of profiles.docs) {
    lastUid = doc.id;
    if (seen.has(doc.id) || blocked.has(doc.id)) continue;
    if (!passesSmokeDiscoveryIsolation(callerAccount.data(), accountsByUid.get(doc.id))) {
      continue;
    }
    if (!isActiveForDiscovery(lastActiveByUid.get(doc.id))) continue;
    if (await isBlocked(uid, doc.id)) continue;
    const data = doc.data();
    if (
      !passesDiscoveryProfileFilters({
        candidateProfile: data,
        candidateAccount: accountsByUid.get(doc.id),
        minAge,
        maxAge,
      })
    ) {
      continue;
    }
    if (
      !passesGenderPreferences({
        viewerPrefs: prefs,
        viewerProfile,
        candidatePrefs: preferencesByUid.get(doc.id) ?? {},
        candidateProfile: data,
      })
    ) {
      continue;
    }
    const age = resolveProfileAge(data);
    if (age === null) continue;
    let distanceKm: number | null = null;
    let label: string | null = null;
    if (origin?.latitude != null && origin?.longitude != null) {
      const otherLoc = await db.doc(`userLocation/${doc.id}`).get();
      const other = otherLoc.data();
      if (other?.latitude != null && other?.longitude != null) {
        distanceKm = haversineKm(
          Number(origin.latitude),
          Number(origin.longitude),
          Number(other.latitude),
          Number(other.longitude),
        );
        if (distanceKm > radiusKm) continue;
        distanceKm = Math.round(distanceKm * 10) / 10;
        label = distanceLabel(distanceKm, lang).label;
      }
    }
    const music = await musicScoreForPair(uid, doc.id);
    const relationship = await relationshipScoreForPair(uid, doc.id);
    const compat = calculateCompatibility({
      viewerProfile,
      candidateProfile: data,
      relationship: relationship
        ? {
            score: relationship.score,
            alignedCount: relationship.alignedCount,
            sharedQuestionCount: relationship.sharedQuestionCount,
            topTopics: relationship.topTopics ?? [],
          }
        : null,
      musicScore: music?.score ?? null,
    });
    items.push({
      uid: doc.id,
      profile: {
        ...publicProfileProjection({...data, uid: doc.id}),
        isVerified: accountsByUid.get(doc.id)?.isVerified === true,
      },
      distanceLabel: label,
      distanceKm,
      compatibilityScore: compat.overallScore,
      compatibilityBreakdown: {
        overallScore: compat.overallScore,
        relationshipScore: compat.relationshipScore,
        interestScore: compat.interestScore,
        lifestyleScore: compat.lifestyleScore,
        questionScore: compat.questionScore,
        musicScore: compat.musicScore,
        communicationScore: compat.communicationScore,
      },
      musicCompatibilityScore: music?.score ?? null,
      musicRankingBonus: music ? musicRankingBonus(music.score) : 0,
      sharedMusicArtists: music?.sharedArtists.slice(0, 3) ?? [],
      sharedMusicTracks: music?.sharedTracks.slice(0, 3) ?? [],
      relationshipCompatibilityScore: relationship?.score ?? null,
      relationshipSharedViewCount: relationship?.sharedQuestionCount ?? null,
      relationshipAlignedCount: relationship?.alignedCount ?? null,
      relationshipSummaryTopics: relationship?.topTopics ?? [],
      sharedInterests: compat.sharedInterests,
      compatibilityReasons: compat.reasons,
    });
  }
  const ranked = sortByBoostVisibility(items, boosted).slice(0, limit);
  const nextCursor = profiles.size === 40 ? lastUid : null;
  return {items: ranked, nextCursor};
});

export const getDiscoveryFeed = getDiscoveryCandidates;

export const recordDiscoveryDecision = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const candidateUid = String(request.data?.candidateUid ?? request.data?.targetUserId ?? "");
  const action = String(request.data?.action ?? "like");
  if (!candidateUid || candidateUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid candidate.");
  }
  const [callerAccount, callerProfileSnap, callerPrefsSnap, candidateProfile, candidatePrefsSnap, candidateAccountSnap, activeMatches] =
    await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${candidateUid}`).get(),
    db.doc(`userPreferences/${candidateUid}`).get(),
    db.doc(`users/${candidateUid}`).get(),
    loadActiveMatchPartnerIds(db, uid),
  ]);
  if (!isAccountEligible(callerAccount.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  if (activeMatches.has(candidateUid)) {
    throw new HttpsError("failed-precondition", "already-matched");
  }
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
    return {matched: false};
  }
  await db.doc(`likes/${uid}_${candidateUid}`).set({
    fromUserId: uid,
    toUserId: candidateUid,
    action: action === "superLike" ? "superLike" : "like",
    createdAt: FieldValue.serverTimestamp(),
  });
  const reverse = await db.doc(`likes/${candidateUid}_${uid}`).get();
  const reverseAction = reverse.data()?.action as string | undefined;
  const matched = reverse.exists && reverseAction !== "pass";
  if (!matched) {
    return {matched: false};
  }
  const matchId = [uid, candidateUid].sort().join("_");
  const matchRef = db.doc(`matches/${matchId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    if (snap.exists && snap.data()?.isActive === true) {
      return;
    }
    const existing = snap.data();
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
  return {matched: true, matchId};
});

export const getDistanceLabel = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const otherUid = String(request.data?.otherUid ?? "");
  if (!otherUid || otherUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid user.");
  }
  const [mine, other] = await Promise.all([
    db.doc(`userLocation/${uid}`).get(),
    db.doc(`userLocation/${otherUid}`).get(),
  ]);
  const a = mine.data();
  const b = other.data();
  if (!a || !b) {
    return {label: null};
  }
  const km = haversineKm(
    Number(a.latitude),
    Number(a.longitude),
    Number(b.latitude),
    Number(b.longitude),
  );
  const lang = await userLanguage(uid);
  const labels = distanceLabel(km, lang);
  return {label: labels.label, labelEn: labels.labelEn, kilometers: Math.round(km)};
});

export {deleteUserAccount} from "./deleteAccount.js";

export const exportMyData = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const [account, profile, prefs, settings, privacy, location, matches] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`userSettings/${uid}`).get(),
    db.doc(`userPrivacy/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.collection("matches").where("userIds", "array-contains", uid).get(),
  ]);
  return {
    exportedAt: new Date().toISOString(),
    uid,
    account: account.data() ?? null,
    profile: profile.data() ?? null,
    preferences: prefs.data() ?? null,
    settings: settings.data() ?? null,
    privacy: privacy.data() ?? null,
    location: {present: location.exists},
    matchIds: matches.docs.map((d) => d.id),
  };
});

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
    const cutoff = Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
    const staleNotifications = await db
      .collection("notifications")
      .where("createdAt", "<", cutoff)
      .limit(400)
      .get();
    const batch = db.batch();
    for (const doc of staleNotifications.docs) batch.delete(doc.ref);
    const staleCalls = await db.collection("calls").where("endedAt", "<", cutoff).limit(200).get();
    for (const doc of staleCalls.docs) batch.delete(doc.ref);
    await batch.commit();
    const retriedPhotos = await retryStaleProcessingPhotos(db, getStorage().bucket());
    logger.info("Retention cleanup complete", {
      notifications: staleNotifications.size,
      calls: staleCalls.size,
      retriedPhotos,
    });
  },
);

export const health = onCall(callableOptions, () => {
  return {status: "ok", service: "mevora"};
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

