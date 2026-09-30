import {FieldPath, type DocumentData, type DocumentSnapshot, type Firestore} from "firebase-admin/firestore";
import {blockId, canonicalMatchId, likeId} from "./ids.js";
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
import {isActiveForDiscovery} from "./discoveryActivity.js";
import {musicRankingBonus} from "./musicCompatibility.js";
import {hasMusicTaste, musicScoreFromSummaries, musicSummaryPath} from "./spotifyMusic.js";
import {
  hasRelationshipAnswers,
  relationshipScoreFromSummaries,
  relationshipSummaryPath,
} from "./relationshipMatch.js";
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

/**
 * Existing documents at `pathOf(uid)` for each uid, fetched in bulk (one
 * batched get per 100). Missing documents are simply absent from the map.
 */
async function loadDocsByUid(
  db: Firestore,
  uids: readonly string[],
  pathOf: (uid: string) => string,
): Promise<Map<string, DocumentData>> {
  const out = new Map<string, DocumentData>();
  const unique = [...new Set(uids.filter(Boolean))];
  for (let i = 0; i < unique.length; i += 100) {
    const chunk = unique.slice(i, i + 100);
    const snaps = await db.getAll(...chunk.map((uid) => db.doc(pathOf(uid))));
    snaps.forEach((snap, index) => {
      const data = snap.data();
      if (data != null) out.set(chunk[index], data);
    });
  }
  return out;
}

/**
 * The `users/{uid}` documents, read once each. They carry both the account
 * state (suspension, deletion, verification) and `lastActiveAt`, so nothing
 * here reads the same document a second time for activity.
 */
export async function loadUserAccounts(
  db: Firestore,
  uids: string[],
): Promise<Map<string, DocumentData>> {
  return loadDocsByUid(db, uids, (uid) => `users/${uid}`);
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
  const docs = await loadDocsByUid(db, uids, (uid) => `userLocation/${uid}`);
  for (const [uid, data] of docs) {
    if (data.latitude == null || data.longitude == null) continue;
    out.set(uid, {latitude: Number(data.latitude), longitude: Number(data.longitude)});
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
  /**
   * False for a viewer loaded without their decision history (see
   * loadDiscoveryViewerBasics): `seen`, `likedUids`, `passedUids`,
   * `matchedUids`, `blocked` and `boosted` are then empty, and a caller that
   * needs them for specific people must look those pairs up.
   */
  historyLoaded?: boolean;
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
  /**
   * What the scan read about every candidate it accepted, in the shape
   * revalidation returns — so a caller serving them in this same request need
   * not read them again.
   */
  accepted: Map<string, RevalidatedCandidate>;
}

export function hasLocation(origin: DocumentData | undefined): boolean {
  return origin?.latitude != null && origin?.longitude != null;
}

/**
 * The viewer-side reads whose cost does not grow with how long someone has
 * used Mevora: who the viewer is, what they want, where they are, which
 * language. Enough to revalidate and render a stored Picks batch; the
 * exclusion history is left empty (`historyLoaded: false`).
 */
export async function loadDiscoveryViewerBasics(
  db: Firestore,
  uid: string,
  callerAccount: DocumentData | undefined,
): Promise<DiscoveryViewerContext> {
  const [prefsSnap, viewerProfileSnap, locationSnap, lang] = await Promise.all([
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    userLanguage(uid),
  ]);
  return {
    uid,
    callerAccount,
    prefs: prefsSnap.data() ?? {},
    viewerProfile: viewerProfileSnap.data() ?? {},
    origin: locationSnap.data(),
    lang,
    seen: new Set([uid]),
    likedUids: new Set(),
    passedUids: new Set(),
    matchedUids: new Set(),
    blocked: new Set(),
    boosted: new Set(),
    historyLoaded: false,
  };
}

/**
 * The viewer's decisions about specific people, looked up pair by pair
 * instead of by reading the whole history: one document-id query per 30
 * candidates against each of likes, passedUsers and matches. Billed per
 * document that exists (at least one read per query), so the cost follows
 * the candidates asked about, not how many people the viewer ever decided on.
 */
export async function loadPairDecisions(
  db: Firestore,
  viewerUid: string,
  candidateUids: readonly string[],
): Promise<{liked: Set<string>; passed: Set<string>; matched: Set<string>}> {
  const liked = new Set<string>();
  const passed = new Set<string>();
  const matched = new Set<string>();
  const unique = [...new Set(candidateUids.filter((id) => id && id !== viewerUid))];
  for (let i = 0; i < unique.length; i += 30) {
    const chunk = unique.slice(i, i + 30);
    const [likes, passes, matches] = await Promise.all([
      db.collection("likes")
        .where(FieldPath.documentId(), "in", chunk.map((uid) => likeId(viewerUid, uid)))
        .get(),
      db.collection(`users/${viewerUid}/passedUsers`)
        .where(FieldPath.documentId(), "in", chunk)
        .get(),
      db.collection("matches")
        .where(FieldPath.documentId(), "in", chunk.map((uid) => canonicalMatchId(viewerUid, uid)))
        .get(),
    ]);
    for (const doc of likes.docs) {
      const target = String(doc.get("toUserId") ?? "");
      if (!target) continue;
      // A like document with action "pass" is a pass, whatever its collection.
      if (doc.get("action") === "pass") passed.add(target);
      else liked.add(target);
    }
    for (const doc of passes.docs) passed.add(doc.id);
    for (const doc of matches.docs) {
      if (doc.get("isActive") !== true) continue;
      for (const other of (doc.get("userIds") as string[]) ?? []) {
        if (other && other !== viewerUid) matched.add(other);
      }
    }
  }
  return {liked, passed, matched};
}

/**
 * Which of these people are blocked from the viewer, or have blocked them, in
 * any of the four records a block can leave: `blocks/{a}_{b}` either way
 * (server-written) and `users/{a}/blockedUsers/{b}` either way (the owner may
 * write their own). Pair-targeted: one document-id query per 15 candidates for
 * the top-level records, one per 30 for the viewer's own subcollection, and
 * one document read per candidate for theirs.
 */
export async function loadPairBlocks(
  db: Firestore,
  viewerUid: string,
  candidateUids: readonly string[],
): Promise<Set<string>> {
  const blocked = new Set<string>();
  const unique = [...new Set(candidateUids.filter((id) => id && id !== viewerUid))];
  if (unique.length === 0) return blocked;
  const byBlockId = new Map<string, string>();
  for (const uid of unique) {
    byBlockId.set(blockId(viewerUid, uid), uid);
    byBlockId.set(blockId(uid, viewerUid), uid);
  }
  const blockIds = [...byBlockId.keys()];
  const queries: Array<Promise<void>> = [];
  for (let i = 0; i < blockIds.length; i += 30) {
    const chunk = blockIds.slice(i, i + 30);
    queries.push(db.collection("blocks").where(FieldPath.documentId(), "in", chunk).get().then((snap) => {
      // The document id is what counts (see isBlockedPair in the rules).
      for (const doc of snap.docs) {
        const uid = byBlockId.get(doc.id);
        if (uid) blocked.add(uid);
      }
    }));
  }
  for (let i = 0; i < unique.length; i += 30) {
    const chunk = unique.slice(i, i + 30);
    queries.push(db.collection(`users/${viewerUid}/blockedUsers`)
      .where(FieldPath.documentId(), "in", chunk).get().then((snap) => {
        for (const doc of snap.docs) blocked.add(doc.id);
      }));
  }
  queries.push(db.getAll(...unique.map((uid) => db.doc(`users/${uid}/blockedUsers/${viewerUid}`)))
    .then((snaps) => {
      snaps.forEach((snap, index) => {
        if (snap.exists) blocked.add(unique[index]);
      });
    }));
  await Promise.all(queries);
  return blocked;
}

/**
 * The viewer with everything the rule chain needs to know about these
 * specific people: blocks either way (always looked up per pair — the one
 * record a preloaded set cannot cover is the other member's own
 * subcollection) and, for a viewer loaded without history, their decisions.
 * People already excluded (seen, blocked, batch members, cooldowns) cost no
 * lookup.
 */
export async function resolvePairExclusions(
  db: Firestore,
  viewer: DiscoveryViewerContext,
  candidateUids: readonly string[],
): Promise<DiscoveryViewerContext> {
  const unknown = [...new Set(candidateUids)].filter(
    (uid) => uid && uid !== viewer.uid && !viewer.seen.has(uid) && !viewer.blocked.has(uid),
  );
  if (unknown.length === 0) return viewer;
  const [blocks, decisions] = await Promise.all([
    loadPairBlocks(db, viewer.uid, unknown),
    viewer.historyLoaded === false
      ? loadPairDecisions(db, viewer.uid, unknown)
      : Promise.resolve({liked: new Set<string>(), passed: new Set<string>(), matched: new Set<string>()}),
  ]);
  const resolved = withPairDecisions(viewer, decisions);
  return {...resolved, blocked: new Set([...viewer.blocked, ...blocks])};
}

/** The viewer's decision about one person, as the Picks lifecycle names it. */
export function decisionOf(
  viewer: DiscoveryViewerContext,
  uid: string,
): "matched" | "liked" | "passed" | null {
  if (viewer.matchedUids.has(uid)) return "matched";
  if (viewer.likedUids.has(uid)) return "liked";
  if (viewer.passedUids.has(uid)) return "passed";
  return null;
}

/** A basics-only viewer, with the decisions about these specific people filled in. */
export function withPairDecisions(
  viewer: DiscoveryViewerContext,
  decisions: {liked: Set<string>; passed: Set<string>; matched: Set<string>},
): DiscoveryViewerContext {
  const union = (a: Set<string>, b: Set<string>) => new Set([...a, ...b]);
  return {
    ...viewer,
    seen: union(viewer.seen, union(decisions.liked, union(decisions.passed, decisions.matched))),
    likedUids: union(viewer.likedUids, decisions.liked),
    passedUids: union(viewer.passedUids, decisions.passed),
    matchedUids: union(viewer.matchedUids, decisions.matched),
  };
}

/**
 * The viewer-side reads a pool scan needs, in one round trip: who the viewer
 * is, what they want, where they are, and everyone already excluded for them
 * (liked, passed, matched, blocked either way). Pass `basics` when they were
 * already loaded for this request, so they are not read twice.
 */
export async function loadDiscoveryViewerContext(
  db: Firestore,
  uid: string,
  callerAccount: DocumentData | undefined,
  basics?: DiscoveryViewerContext,
): Promise<{viewer: DiscoveryViewerContext; boostSessions: Map<string, BoostSession>}> {
  const [base, blocked, likesSnap, passedSnap, boostSessions, activeMatches] =
    await Promise.all([
      basics ? Promise.resolve(basics) : loadDiscoveryViewerBasics(db, uid, callerAccount),
      loadBlockedUserIds(db, uid),
      db.collection("likes").where("fromUserId", "==", uid).get(),
      db.collection(`users/${uid}/passedUsers`).get(),
      loadActiveBoostSessions(db),
      loadActiveMatchPartnerIds(db, uid),
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
      ...base,
      seen,
      likedUids,
      passedUids,
      matchedUids: activeMatches,
      blocked,
      // Ranking needs only the uids; measurement needs the sessions behind them.
      boosted: new Set(boostSessions.keys()),
      historyLoaded: true,
    },
    boostSessions,
  };
}

/**
 * Why this candidate may not be shown to this viewer, or null when they may.
 *
 * The single rule chain for "may these two people be put in front of each
 * other": already decided or matched, blocked in either direction, smoke-test
 * isolation, inactivity, profile/account/moderation/photo/age gates, and
 * mutual gender preference.
 *
 * It reads nothing. `viewer.seen` and `viewer.blocked` must already cover
 * this candidate — callers resolve the pair first (resolvePairExclusions),
 * for a whole page at once, after the checks that need no pair state
 * (candidateOwnRejectReason) have thinned it out.
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
  return candidateOwnRejectReason(viewer, candidate);
}

/**
 * The part of the rule chain that needs no pair state: smoke-test isolation,
 * inactivity, profile/account/moderation/photo/age gates and mutual gender
 * preference. Run first, so pair lookups are paid only for people who could
 * otherwise be shown.
 */
export function candidateOwnRejectReason(
  viewer: DiscoveryViewerContext,
  candidate: {
    uid: string;
    profile: DocumentData | undefined;
    account: DocumentData | undefined;
    candidatePrefs: DocumentData | undefined;
    lastActiveAt: unknown;
  },
): string | null {
  if (candidate.uid === viewer.uid) {
    return "already_seen_or_matched";
  }
  if (!passesSmokeDiscoveryIsolation(viewer.callerAccount, candidate.account)) {
    return "smoke_isolation";
  }
  if (!isActiveForDiscovery(candidate.lastActiveAt)) {
    return "inactive";
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

  // The viewer's side of every pair score, read once per scan rather than
  // once per candidate. When the viewer has no usable music or relationship
  // data, every pair score on that dimension is null, so no candidate's
  // summary is read for it at all.
  const [viewerMusicSnap, viewerRelationshipSnap] = await Promise.all([
    db.doc(musicSummaryPath(uid)).get(),
    db.doc(relationshipSummaryPath(uid)).get(),
  ]);
  const viewerMusic = viewerMusicSnap.data();
  const viewerRelationship = viewerRelationshipSnap.data();
  const scoresMusic = hasMusicTaste(viewerMusic);
  const scoresRelationship = hasRelationshipAnswers(viewerRelationship);
  const accepted = new Map<string, RevalidatedCandidate>();

  let pageCursor = options.cursor;
  // The previous page's last document positions the next page directly.
  let cursorSnap: DocumentSnapshot | null = null;
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
    if (!cursorSnap && pageCursor) {
      // Only a cursor handed in from outside needs reading.
      const snap = await db.doc(`profiles/${pageCursor}`).get();
      if (snap.exists) cursorSnap = snap;
    }
    if (cursorSnap) {
      query = query.startAfter(cursorSnap);
    }
    const profiles = await query.get();
    scannedFullPage = profiles.size === pageSize;
    if (profiles.empty) {
      break;
    }
    cursorSnap = profiles.docs[profiles.docs.length - 1];
    const candidateUids = profiles.docs.map((doc) => doc.id);
    const [accountsByUid, preferencesByUid, locationsByUid] = await Promise.all([
      loadUserAccounts(db, candidateUids),
      loadPreferencesByUid(db, candidateUids),
      hasViewerLocation ? loadUserLocations(db, candidateUids) : Promise.resolve(new Map()),
    ]);

    // First pass: the rule chain and the hard distance gate. Nothing here
    // reads per candidate beyond the page's bulk loads above.
    const survivors: Array<{
      uid: string;
      data: DocumentData;
      tier: DiscoveryDistanceTier;
      distanceKm: number | null;
      label: string | null;
      candidateBoosted: boolean;
    }> = [];
    // Pair state (decisions, blocks either way) only for the people the rest
    // of the rule chain would still admit, looked up for the page at once.
    const ownFields = (doc: (typeof profiles.docs)[number]) => {
      const account = accountsByUid.get(doc.id);
      return {
        uid: doc.id,
        profile: doc.data(),
        account,
        candidatePrefs: preferencesByUid.get(doc.id),
        lastActiveAt: account?.lastActiveAt,
      };
    };
    const pageViewer = await resolvePairExclusions(
      db,
      viewer,
      profiles.docs.filter((doc) => candidateOwnRejectReason(viewer, ownFields(doc)) === null).map((doc) => doc.id),
    );
    for (const doc of profiles.docs) {
      lastUid = doc.id;
      const data = doc.data();
      const account = accountsByUid.get(doc.id);
      const reject = await candidateRejectReason(db, pageViewer, {
        uid: doc.id,
        profile: data,
        account,
        candidatePrefs: preferencesByUid.get(doc.id),
        lastActiveAt: account?.lastActiveAt,
      });
      if (reject) {
        bumpReject(reject);
        continue;
      }
      const candidateBoosted = isBoostedCandidate(doc.id, boosted);
      let distanceKm: number | null = null;
      let label: string | null = null;
      let tier: DiscoveryDistanceTier = "no_location";
      let exactKmOf: number | null = null;
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
          exactKmOf = exactKm;
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
      survivors.push({uid: doc.id, data, tier, distanceKm, label, candidateBoosted});
      accepted.set(doc.id, {uid: doc.id, rejectReason: null, profile: data, account, exactKm: exactKmOf});
    }

    // Second pass: pair scores for the survivors only, their summaries read
    // in bulk — and not at all on a dimension the viewer has no data for.
    const survivorUids = survivors.map((survivor) => survivor.uid);
    const [musicByUid, relationshipByUid] = await Promise.all([
      scoresMusic ? loadDocsByUid(db, survivorUids, musicSummaryPath) : Promise.resolve(new Map()),
      scoresRelationship
        ? loadDocsByUid(db, survivorUids, relationshipSummaryPath)
        : Promise.resolve(new Map()),
    ]);
    for (const {uid: candidateUid, data, tier, distanceKm, label, candidateBoosted} of survivors) {
      const music = scoresMusic ? musicScoreFromSummaries(viewerMusic, musicByUid.get(candidateUid)) : null;
      const relationship = scoresRelationship
        ? relationshipScoreFromSummaries(uid, candidateUid, viewerRelationship, relationshipByUid.get(candidateUid))
        : null;
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
      evidence.set(candidateUid, compatibilityEvidence(viewerProfile, data));
      buckets[tier].push({
        uid: candidateUid,
        profile: {
          ...discoveryProfileProjection({...data, uid: candidateUid}),
          isVerified: accountsByUid.get(candidateUid)?.isVerified === true,
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
    accepted,
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
  /** The viewer's decision about them, when they made one. */
  decision?: "matched" | "liked" | "passed" | null;
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
  const [profileSnaps, accountsByUid, preferencesByUid, locationsByUid] =
    await Promise.all([
      db.getAll(...unique.map((id) => db.doc(`profiles/${id}`))),
      loadUserAccounts(db, unique),
      loadPreferencesByUid(db, unique),
      hasViewerLocation ? loadUserLocations(db, unique) : Promise.resolve(new Map()),
    ]);
  const profilesByUid = new Map(profileSnaps.map((snap) => [snap.id, snap.data()] as const));
  const fieldsOf = (uid: string) => {
    const account = accountsByUid.get(uid);
    return {
      uid,
      profile: profilesByUid.get(uid),
      account,
      candidatePrefs: preferencesByUid.get(uid),
      lastActiveAt: account?.lastActiveAt,
    };
  };
  // Decisions for everyone asked about (a liked Pick whose account has since
  // gone is still "liked", not a slot to refill); blocks only for people the
  // rest of the chain would still admit. Both in parallel.
  const [decisions, blocks] = await Promise.all([
    viewer.historyLoaded === false
      ? loadPairDecisions(db, viewer.uid, unique)
      : Promise.resolve({liked: new Set<string>(), passed: new Set<string>(), matched: new Set<string>()}),
    loadPairBlocks(
      db,
      viewer.uid,
      unique.filter((uid) => !viewer.blocked.has(uid) && candidateOwnRejectReason(viewer, fieldsOf(uid)) === null),
    ),
  ]);
  const decided = {
    ...withPairDecisions(viewer, decisions),
    blocked: new Set([...viewer.blocked, ...blocks]),
  };
  for (const uid of unique) {
    const {profile, account} = fieldsOf(uid);
    let rejectReason = await candidateRejectReason(db, decided, fieldsOf(uid));
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
    out.set(uid, {uid, rejectReason, profile, account, exactKm, decision: decisionOf(decided, uid)});
  }
  return out;
}
