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
import {blockId} from "./ids.js";
import {
  isAccountEligible,
  discoveryProfileProjection,
  resolveProfileAge,
} from "./profileSafety.js";
import {
  discoveryProfileRejectReason,
  loadActiveMatchPartnerIds,
  loadPreferencesByUid,
  passesDiscoveryProfileFilters,
  passesGenderPreferences,
} from "./discoveryMatching.js";
import {loadActiveBoostedUserIds, effectiveRadiusKm, isBoostedCandidate, sortByBoostVisibility} from "./boost/ranking.js";
import {
  classifyDiscoveryDistance,
  fillFromDistanceTiers,
  type DiscoveryDistanceTier,
} from "./discoveryFallback.js";
import {userLanguage} from "./language.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {profileQualityFromDocs} from "./recommendation/profileQuality.js";
import {musicRankingBonus} from "./musicCompatibility.js";
import {ensureMatchScore, preservedMatchScoreFields} from "./matchScore.js";
import {musicScoreForPair} from "./spotifyMusic.js";
import {relationshipScoreForPair} from "./relationshipMatch.js";
import {processPendingProfilePhoto, retryStaleProcessingPhotos} from "./moderation/photoModerationService.js";
import {calculateCompatibility} from "./compatibility/compatibilityEngine.js";
import {passesSmokeDiscoveryIsolation} from "./smoke/smokeTestUsers.js";
import {
  cleanupOldCalls,
  cleanupOldNotifications,
} from "./automation/cleanup.js";
import {FcmTypes, sendUserPush} from "./notifications.js";

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

async function loadUserLocations(
  uids: string[],
): Promise<Map<string, {latitude: number; longitude: number}>> {
  const out = new Map<string, {latitude: number; longitude: number}>();
  const unique = [...new Set(uids)].filter((id) => id.length > 0);
  for (let i = 0; i < unique.length; i += 30) {
    const chunk = unique.slice(i, i + 30);
    const snaps = await Promise.all(chunk.map((id) => db.doc(`userLocation/${id}`).get()));
    snaps.forEach((snap, index) => {
      const data = snap.data();
      if (data?.latitude == null || data?.longitude == null) {
        return;
      }
      out.set(chunk[index], {
        latitude: Number(data.latitude),
        longitude: Number(data.longitude),
      });
    });
  }
  return out;
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
  // Client may ask for soft distance expansion when a preferred radius is empty.
  const expandDistance = request.data?.expandDistance === true;
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
    return {items: [], nextCursor: null, fallbackLevel: "empty"};
  }
  const viewerProfile = viewerProfileSnap.data() ?? {};
  const lang = await userLanguage(uid);
  const minAge = Number(prefs.minAge ?? 18);
  const maxAge = Number(prefs.maxAge ?? 99);
  const origin = locationSnap.data();
  const hasViewerLocation = origin?.latitude != null && origin?.longitude != null;

  // Scan multiple profile pages when nearby is sparse so far/no-location
  // candidates can still fill the deck without a full collection download.
  const pageSize = 40;
  const maxPages = expandDistance ? 4 : 3;
  let pageCursor = cursor;
  let lastUid: string | null = null;
  let scannedFullPage = false;
  const buckets: Record<DiscoveryDistanceTier, Array<Record<string, unknown>>> = {
    nearby: [],
    extended: [],
    far: [],
    no_location: [],
  };
  const rejectionReasons: Record<string, number> = {};
  const bumpReject = (reason: string) => {
    rejectionReasons[reason] = (rejectionReasons[reason] ?? 0) + 1;
  };
  const includeDebug = request.data?.includeDebug === true;

  for (let page = 0; page < maxPages; page++) {
    let query = db
      .collection("profiles")
      .where("isDiscoverable", "==", true)
      .where("profileCompleted", "==", true)
      .orderBy("updatedAt", "desc")
      .limit(pageSize);
    if (pageCursor) {
      const cursorSnap = await db.doc(`profiles/${pageCursor}`).get();
      if (cursorSnap.exists) {
        query = query.startAfter(cursorSnap);
      }
    }
    const profiles = await query.get();
    scannedFullPage = profiles.size === pageSize;
    if (profiles.empty) {
      break;
    }
    const candidateUids = profiles.docs.map((doc) => doc.id);
    const [lastActiveByUid, accountsByUid, preferencesByUid, locationsByUid] = await Promise.all([
      loadLastActiveAt(db, candidateUids),
      loadUserAccounts(candidateUids),
      loadPreferencesByUid(db, candidateUids),
      hasViewerLocation ? loadUserLocations(candidateUids) : Promise.resolve(new Map()),
    ]);

    for (const doc of profiles.docs) {
      lastUid = doc.id;
      if (seen.has(doc.id) || blocked.has(doc.id)) {
        bumpReject(seen.has(doc.id) ? "already_seen_or_matched" : "blocked");
        continue;
      }
      if (!passesSmokeDiscoveryIsolation(callerAccount.data(), accountsByUid.get(doc.id))) {
        bumpReject("smoke_isolation");
        continue;
      }
      if (!isActiveForDiscovery(lastActiveByUid.get(doc.id))) {
        bumpReject("inactive");
        continue;
      }
      if (await isBlocked(uid, doc.id)) {
        bumpReject("blocked");
        continue;
      }
      const data = doc.data();
      const profileReject = discoveryProfileRejectReason({
        candidateProfile: data,
        candidateAccount: accountsByUid.get(doc.id),
        minAge,
        maxAge,
      });
      if (profileReject) {
        bumpReject(profileReject);
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
        bumpReject("gender_preference");
        continue;
      }
      const age = resolveProfileAge(data);
      if (age === null) {
        bumpReject("age_unresolved");
        continue;
      }
      const candidateBoosted = isBoostedCandidate(doc.id, boosted);
      let distanceKm: number | null = null;
      let label: string | null = null;
      let tier: DiscoveryDistanceTier = "no_location";
      if (hasViewerLocation) {
        const other = locationsByUid.get(doc.id);
        if (other) {
          distanceKm = haversineKm(
            Number(origin.latitude),
            Number(origin.longitude),
            other.latitude,
            other.longitude,
          );
          const maxNearbyKm = effectiveRadiusKm(radiusKm, candidateBoosted);
          tier = classifyDiscoveryDistance(
            distanceKm,
            radiusKm,
            candidateBoosted,
            maxNearbyKm,
          );
          distanceKm = Math.round(distanceKm * 10) / 10;
          label = distanceLabel(distanceKm, lang).label;
        } else {
          tier = "no_location";
        }
      } else {
        // Viewer has no location → location-independent discovery.
        tier = "no_location";
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
      const quality = profileQualityFromDocs({
        profile: data,
        user: {
          ...(accountsByUid.get(doc.id) ?? {}),
          lastActiveAt: lastActiveByUid.get(doc.id) ?? null,
        },
        personalityAnswerCount: Number(
          (data as {relationshipAnswerCount?: unknown}).relationshipAnswerCount ?? 0,
        ),
        nowMs: Date.now(),
      });
      buckets[tier].push({
        uid: doc.id,
        profile: {
          ...discoveryProfileProjection({...data, uid: doc.id}),
          isVerified: accountsByUid.get(doc.id)?.isVerified === true,
        },
        distanceLabel: label,
        distanceKm,
        profileQualityScore: quality.score,
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
        sharedMusicArtists: music?.sharedArtistNames?.slice(0, 5)
          ?? music?.sharedArtists.slice(0, 5)
          ?? [],
        sharedMusicTracks: music?.sharedTrackNames?.slice(0, 5)
          ?? music?.sharedTracks.slice(0, 5)
          ?? [],
        sharedMusicGenres: music?.sharedGenres.slice(0, 3) ?? [],
        sharedMusicArtistCount: music?.sharedArtists.length ?? 0,
        sharedMusicTrackCount: music?.sharedTracks.length ?? 0,
        sharedMusicGenreCount: music?.sharedGenres.length ?? 0,
        sharedMusicPlaylistTrackCount: music?.sharedPlaylistTracks.length ?? 0,
        sharedMusicRecentTrackCount: music?.sharedRecentTracks.length ?? 0,
        musicInsights: music?.insights ?? [],
        musicBreakdown: music?.breakdown ?? null,
        relationshipCompatibilityScore: relationship?.score ?? null,
        relationshipSharedViewCount: relationship?.sharedQuestionCount ?? null,
        relationshipAlignedCount: relationship?.alignedCount ?? null,
        relationshipSummaryTopics: relationship?.topTopics ?? [],
        sharedInterests: compat.sharedInterests,
        compatibilityReasons: compat.reasons,
        isBoosted: candidateBoosted,
        discoveryTier: tier,
      });
    }

    const nearbyCount = buckets.nearby.length;
    const totalEligible =
      nearbyCount +
      buckets.extended.length +
      buckets.far.length +
      buckets.no_location.length;
    // Enough nearby — stop scanning. Otherwise keep scanning for fallback tiers.
    if (nearbyCount >= limit || totalEligible >= limit * 2) {
      pageCursor = lastUid ?? "";
      break;
    }
    if (!scannedFullPage) {
      break;
    }
    pageCursor = lastUid ?? "";
  }

  // Rank each tier with the existing boost/compat ranking (no engine rewrite).
  for (const key of Object.keys(buckets) as DiscoveryDistanceTier[]) {
    buckets[key] = sortByBoostVisibility(buckets[key], boosted, radiusKm);
  }

  const filled = fillFromDistanceTiers(buckets, limit);
  logger.info("discovery_fallback", {
    viewerHasLocation: hasViewerLocation,
    radiusKm,
    expandDistance,
    nearby: buckets.nearby.length,
    extended: buckets.extended.length,
    far: buckets.far.length,
    noLocation: buckets.no_location.length,
    returned: filled.items.length,
    fallbackLevel: filled.fallbackLevel,
    rejectionReasons,
  });

  const nextCursor = scannedFullPage ? lastUid : null;
  return {
    items: filled.items,
    nextCursor,
    fallbackLevel: filled.fallbackLevel,
    ...(includeDebug
      ? {
          debug: {
            rejectionReasons,
            viewerHasLocation: hasViewerLocation,
            radiusKm,
            nearby: buckets.nearby.length,
            extended: buckets.extended.length,
            far: buckets.far.length,
            noLocation: buckets.no_location.length,
          },
        }
      : {}),
  };
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
    db.doc(`users/${uid}/verification/sumsub`).get(),
    db.collection(`users/${uid}/questionAnswers`).limit(100).get(),
  ]);

  // Never include exact GPS, Spotify secrets, private keys, or message ciphertext bodies.
  const loc = location.data();
  const verificationData = verification.data();
  const musicData = music.data();

  return {
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
        reviewedAt: verificationData.reviewedAt ?? null,
        // No Sumsub applicant secrets.
      }
      : null,
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
  };
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

