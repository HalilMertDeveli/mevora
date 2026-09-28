import type {DocumentData, Firestore} from "firebase-admin/firestore";
import {blockId} from "./ids.js";
import {coarseDistanceLabel} from "./geo/coarseDistance.js";
import {discoveryProfileProjection, resolveProfileAge} from "./profileSafety.js";
import {
  discoveryProfileRejectReason,
  loadActiveMatchPartnerIds,
  loadPreferencesByUid,
  passesGenderPreferences,
} from "./discoveryMatching.js";
import {effectiveRadiusKm, isBoostedCandidate, loadActiveBoostSessions} from "./boost/ranking.js";
import type {BoostSession} from "./boost/measurement.js";
import {userLanguage} from "./language.js";
import {
  classifyDiscoveryDistance,
  isWithinDiscoveryRadius,
  type DiscoveryDistanceTier,
} from "./discoveryFallback.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {musicRankingBonus} from "./musicCompatibility.js";
import {musicScoreForPair} from "./spotifyMusic.js";
import {relationshipScoreForPair} from "./relationshipMatch.js";
import {
  calculateCompatibility,
  compatibilityEvidence,
  type CompatibilityEvidence,
} from "./compatibility/compatibilityEngine.js";
import {passesSmokeDiscoveryIsolation} from "./smoke/smokeTestUsers.js";

/**
 * The Discover candidate pool: who may be shown to a viewer at all, and the
 * canonical compatibility payload for each of them.
 *
 * Both entry points that put people in front of a viewer — the Discover deck
 * (`getDiscoveryCandidates`) and Mevora Picks (`getMevoraPicks`) — walk the
 * pool through this one function, so a safety or eligibility rule added here
 * binds both. Nothing downstream may re-admit a candidate this scan rejected.
 */

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const sLat = Math.sin(dLat / 2);
  const sLng = Math.sin(dLng / 2);
  const h =
    sLat * sLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sLng * sLng;
  return 2 * 6371 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

export async function isBlocked(db: Firestore, a: string, b: string): Promise<boolean> {
  const [subA, subB, topA, topB] = await Promise.all([
    db.doc(`users/${a}/blockedUsers/${b}`).get(),
    db.doc(`users/${b}/blockedUsers/${a}`).get(),
    db.doc(`blocks/${blockId(a, b)}`).get(),
    db.doc(`blocks/${blockId(b, a)}`).get(),
  ]);
  return subA.exists || subB.exists || topA.exists || topB.exists;
}

export async function loadUserAccounts(
  db: Firestore,
  uids: string[],
): Promise<Map<string, DocumentData>> {
  const unique = [...new Set(uids.filter(Boolean))];
  const entries = await Promise.all(
    unique.map(async (uid) => {
      const snap = await db.doc(`users/${uid}`).get();
      return [uid, snap.data()] as const;
    }),
  );
  return new Map(entries.filter(([, data]) => data != null) as Array<[string, DocumentData]>);
}

export async function loadBlockedUserIds(db: Firestore, uid: string): Promise<Set<string>> {
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

export async function loadUserLocations(
  db: Firestore,
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

/** Everything the scan needs to know about the viewer. Loaded once per request. */
export interface DiscoveryViewerContext {
  uid: string;
  callerAccount: DocumentData | undefined;
  prefs: DocumentData;
  viewerProfile: DocumentData;
  origin: DocumentData | undefined;
  lang: Awaited<ReturnType<typeof userLanguage>>;
  /** People the viewer already liked, passed or is matched with — and self. */
  seen: Set<string>;
  /** The parts of `seen`, kept apart for callers that need to tell them apart. */
  likedUids: Set<string>;
  passedUids: Set<string>;
  matchedUids: Set<string>;
  blocked: Set<string>;
  boosted: Set<string>;
}

export type DiscoveryPoolBuckets = Record<DiscoveryDistanceTier, Array<Record<string, unknown>>>;

export interface DiscoveryPoolScan {
  buckets: DiscoveryPoolBuckets;
  rejectionReasons: Record<string, number>;
  /** Last profile id examined, for the next page cursor. */
  lastUid: string | null;
  /** Whether the final page read was full, i.e. more profiles may follow. */
  scannedFullPage: boolean;
  /**
   * Exact viewer→candidate distance, server-side only. Never copied into a
   * payload: what leaves the backend is the quantised `distanceKm` bucket.
   */
  exactDistanceKm: Map<string, number>;
  /** Which profile dimensions both sides actually filled in. Server-side only. */
  evidence: Map<string, CompatibilityEvidence>;
  hasViewerLocation: boolean;
}

export function hasLocation(origin: DocumentData | undefined): boolean {
  return origin?.latitude != null && origin?.longitude != null;
}

/**
 * The viewer-side reads every pool request makes, in one round trip: who the
 * viewer is, what they want, where they are, and everyone already excluded
 * for them (liked, passed, matched, blocked either way).
 */
export async function loadDiscoveryViewerContext(
  db: Firestore,
  uid: string,
  callerAccount: DocumentData | undefined,
): Promise<{viewer: DiscoveryViewerContext; boostSessions: Map<string, BoostSession>}> {
  const [prefsSnap, viewerProfileSnap, locationSnap, blocked, likesSnap, passedSnap, boostSessions, activeMatches, lang] =
    await Promise.all([
      db.doc(`userPreferences/${uid}`).get(),
      db.doc(`profiles/${uid}`).get(),
      db.doc(`userLocation/${uid}`).get(),
      loadBlockedUserIds(db, uid),
      db.collection("likes").where("fromUserId", "==", uid).get(),
      db.collection(`users/${uid}/passedUsers`).get(),
      loadActiveBoostSessions(db),
      loadActiveMatchPartnerIds(db, uid),
      userLanguage(uid),
    ]);
  const seen = new Set(likesSnap.docs.map((doc) => String(doc.get("toUserId") ?? "")));
  for (const doc of passedSnap.docs) seen.add(doc.id);
  for (const partner of activeMatches) seen.add(partner);
  seen.add(uid);
  // A like document with action "pass" is a pass, whatever its collection.
  const likedUids = new Set<string>();
  const passedUids = new Set<string>(passedSnap.docs.map((doc) => doc.id));
  for (const doc of likesSnap.docs) {
    const target = String(doc.get("toUserId") ?? "");
    if (!target) continue;
    if (doc.get("action") === "pass") passedUids.add(target);
    else likedUids.add(target);
  }
  return {
    viewer: {
      uid,
      callerAccount,
      prefs: prefsSnap.data() ?? {},
      viewerProfile: viewerProfileSnap.data() ?? {},
      origin: locationSnap.data(),
      lang,
      seen,
      likedUids,
      passedUids,
      matchedUids: activeMatches,
      blocked,
      // Ranking needs only the uids; measurement needs the sessions behind them.
      boosted: new Set(boostSessions.keys()),
    },
    boostSessions,
  };
}

/**
 * Why this candidate may not be shown to this viewer, or null when they may.
 *
 * The single rule chain for "may these two people be put in front of each
 * other": already decided or matched, blocked in either direction (by the
 * preloaded set and by a direct pair check), smoke-test isolation, inactivity,
 * profile/account/moderation/photo/age gates, and mutual gender preference.
 * Order matters only for cost — cheap in-memory checks run before reads.
 */
export async function candidateRejectReason(
  db: Firestore,
  viewer: DiscoveryViewerContext,
  candidate: {
    uid: string;
    profile: DocumentData | undefined;
    account: DocumentData | undefined;
    candidatePrefs: DocumentData | undefined;
    lastActiveAt: unknown;
  },
): Promise<string | null> {
  const {uid} = candidate;
  if (uid === viewer.uid || viewer.seen.has(uid)) {
    return "already_seen_or_matched";
  }
  if (viewer.blocked.has(uid)) {
    return "blocked";
  }
  if (!passesSmokeDiscoveryIsolation(viewer.callerAccount, candidate.account)) {
    return "smoke_isolation";
  }
  if (!isActiveForDiscovery(candidate.lastActiveAt)) {
    return "inactive";
  }
  if (await isBlocked(db, viewer.uid, uid)) {
    return "blocked";
  }
  const profileReject = discoveryProfileRejectReason({
    candidateProfile: candidate.profile,
    candidateAccount: candidate.account,
    minAge: Number(viewer.prefs.minAge ?? 18),
    maxAge: Number(viewer.prefs.maxAge ?? 99),
  });
  if (profileReject) {
    return profileReject;
  }
  if (
    !passesGenderPreferences({
      viewerPrefs: viewer.prefs,
      viewerProfile: viewer.viewerProfile,
      candidatePrefs: candidate.candidatePrefs ?? {},
      candidateProfile: candidate.profile ?? {},
    })
  ) {
    return "gender_preference";
  }
  if (resolveProfileAge(candidate.profile) === null) {
    return "age_unresolved";
  }
  return null;
}

/**
 * Walks `profiles` newest-updated first and returns every eligible candidate
 * with its canonical compatibility payload, bucketed by distance tier.
 *
 * `shouldStop` is asked after each page; the scan also stops at `maxPages`
 * or the first short page.
 */
export async function scanDiscoveryPool(
  db: Firestore,
  viewer: DiscoveryViewerContext,
  options: {
    cursor: string;
    radiusKm: number;
    gateKm: number;
    pageSize: number;
    maxPages: number;
    shouldStop: (buckets: DiscoveryPoolBuckets) => boolean;
  },
): Promise<DiscoveryPoolScan> {
  const {uid, viewerProfile, origin, lang, boosted} = viewer;
  const {radiusKm, gateKm, pageSize, maxPages} = options;
  const hasViewerLocation = hasLocation(origin);

  let pageCursor = options.cursor;
  let lastUid: string | null = null;
  let scannedFullPage = false;
  const buckets: DiscoveryPoolBuckets = {
    nearby: [],
    extended: [],
    far: [],
    no_location: [],
  };
  const exactDistanceKm = new Map<string, number>();
  const evidence = new Map<string, CompatibilityEvidence>();
  const rejectionReasons: Record<string, number> = {};
  const bumpReject = (reason: string) => {
    rejectionReasons[reason] = (rejectionReasons[reason] ?? 0) + 1;
  };

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
      loadUserAccounts(db, candidateUids),
      loadPreferencesByUid(db, candidateUids),
      hasViewerLocation ? loadUserLocations(db, candidateUids) : Promise.resolve(new Map()),
    ]);

    for (const doc of profiles.docs) {
      lastUid = doc.id;
      const data = doc.data();
      const reject = await candidateRejectReason(db, viewer, {
        uid: doc.id,
        profile: data,
        account: accountsByUid.get(doc.id),
        candidatePrefs: preferencesByUid.get(doc.id),
        lastActiveAt: lastActiveByUid.get(doc.id),
      });
      if (reject) {
        bumpReject(reject);
        continue;
      }
      const candidateBoosted = isBoostedCandidate(doc.id, boosted);
      let distanceKm: number | null = null;
      let label: string | null = null;
      let tier: DiscoveryDistanceTier = "no_location";
      if (hasViewerLocation) {
        const other = locationsByUid.get(doc.id);
        if (other) {
          const exactKm = haversineKm(
            Number(origin?.latitude),
            Number(origin?.longitude),
            other.latitude,
            other.longitude,
          );
          // HARD GATE. Beyond the resolved radius the candidate is dropped,
          // not demoted to a lower tier: the tiers below only order the
          // people who got through here.
          //
          // Deliberately the exact haversine, and deliberately ahead of the
          // disclosure step further down — that step floors the value into
          // 5 km bands and flattens everything at or beyond 100 km to
          // exactly 100, so gating on the disclosed figure would wave
          // through a candidate on the far side of the planet.
          //
          // Ahead of the music/relationship scoring below as well, so a
          // rejected candidate costs no extra reads.
          if (!isWithinDiscoveryRadius(exactKm, gateKm)) {
            bumpReject("distance_over_radius");
            continue;
          }
          const maxNearbyKm = effectiveRadiusKm(radiusKm, candidateBoosted);
          tier = classifyDiscoveryDistance(
            exactKm,
            radiusKm,
            candidateBoosted,
            maxNearbyKm,
          );
          exactDistanceKm.set(doc.id, exactKm);
          // Tier classification above used the exact value. What leaves the
          // backend is quantised: a 0.1 km figure for a candidate the caller
          // can pick out of the deck is a sharper trilateration oracle than
          // getDistanceLabel ever was.
          const disclosed = coarseDistanceLabel(exactKm, lang);
          distanceKm = disclosed.bucketKm;
          label = disclosed.label;
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
      evidence.set(doc.id, compatibilityEvidence(viewerProfile, data));
      buckets[tier].push({
        uid: doc.id,
        profile: {
          ...discoveryProfileProjection({...data, uid: doc.id}),
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

    if (options.shouldStop(buckets)) {
      pageCursor = lastUid ?? "";
      break;
    }
    if (!scannedFullPage) {
      break;
    }
    pageCursor = lastUid ?? "";
  }

  return {
    buckets,
    rejectionReasons,
    lastUid,
    scannedFullPage,
    exactDistanceKm,
    evidence,
    hasViewerLocation,
  };
}

export interface RevalidatedCandidate {
  uid: string;
  /** Null when the candidate may still be shown. */
  rejectReason: string | null;
  profile: DocumentData | undefined;
  account: DocumentData | undefined;
  /** Exact viewer→candidate distance; server-side only. */
  exactKm: number | null;
}

/**
 * Re-checks named candidates against the same rule chain and hard distance
 * gate the scan applies — for callers that hold on to people between requests
 * (Mevora Picks keeps a batch for a day). Anyone blocked, matched, deleted,
 * suspended, hidden or moved out of range since is reported, not returned.
 */
export async function revalidatePoolCandidates(
  db: Firestore,
  viewer: DiscoveryViewerContext,
  uids: string[],
  gateKm: number,
): Promise<Map<string, RevalidatedCandidate>> {
  const unique = [...new Set(uids.filter(Boolean))];
  const out = new Map<string, RevalidatedCandidate>();
  if (unique.length === 0) {
    return out;
  }
  const hasViewerLocation = hasLocation(viewer.origin);
  const [profileSnaps, accountsByUid, preferencesByUid, lastActiveByUid, locationsByUid] =
    await Promise.all([
      db.getAll(...unique.map((id) => db.doc(`profiles/${id}`))),
      loadUserAccounts(db, unique),
      loadPreferencesByUid(db, unique),
      loadLastActiveAt(db, unique),
      hasViewerLocation ? loadUserLocations(db, unique) : Promise.resolve(new Map()),
    ]);
  const profilesByUid = new Map(profileSnaps.map((snap) => [snap.id, snap.data()] as const));
  for (const uid of unique) {
    const profile = profilesByUid.get(uid);
    const account = accountsByUid.get(uid);
    let rejectReason = await candidateRejectReason(db, viewer, {
      uid,
      profile,
      account,
      candidatePrefs: preferencesByUid.get(uid),
      lastActiveAt: lastActiveByUid.get(uid),
    });
    let exactKm: number | null = null;
    const other = locationsByUid.get(uid);
    if (!rejectReason && hasViewerLocation && other) {
      exactKm = haversineKm(
        Number(viewer.origin?.latitude),
        Number(viewer.origin?.longitude),
        other.latitude,
        other.longitude,
      );
      if (!isWithinDiscoveryRadius(exactKm, gateKm)) {
        rejectReason = "distance_over_radius";
      }
    }
    out.set(uid, {uid, rejectReason, profile, account, exactKm});
  }
  return out;
}
