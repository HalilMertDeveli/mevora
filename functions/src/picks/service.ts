import {randomBytes} from "node:crypto";
import type {DocumentData, DocumentReference, Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {coarseDistanceLabel} from "../geo/coarseDistance.js";
import {discoveryProfileProjection} from "../profileSafety.js";
import {DISCOVERY_MAX_RADIUS_KM} from "../discoveryFallback.js";
import {boostAdvantageApplies} from "../boost/ranking.js";
import {recordBoostImpressions, type BoostSession} from "../boost/measurement.js";
import {
  hasLocation,
  revalidatePoolCandidates,
  scanDiscoveryPool,
  type DiscoveryViewerContext,
} from "../discoveryPool.js";
import type {CompatibilityEvidence} from "../compatibility/compatibilityEngine.js";
import {loadUserHumorProfile} from "../humor/feed.js";
import {humorScoreForPair, isHumorCalibrationReady} from "../humor/compatibility.js";
import type {UserHumorProfileDoc} from "../humor/types.js";
import {PICK_QUALITY, PICKS_CONFIG, PICKS_SIZING, picksSizing, type PicksSizing} from "./config.js";
import {composePicks, evaluatePool} from "./selection.js";
import {loadPersonalizationContext} from "../personalization/store.js";
import {
  logicalDayKey,
  activePicks,
  appendPicks,
  applyDecision,
  applyRevalidation,
  buildStoredPicks,
  cooldownsAfterExpiry,
  excludedFromSelection,
  isBatchLive,
  markScanned,
  needsTopUp,
  newBatch,
  parseBatch,
  scrubCandidate,
  topUpSlots,
  type PickCardSnapshot,
  type PickDecision,
  type PicksBatch,
  type PickState,
  type StoredPick,
} from "./lifecycle.js";
import {bumpFunnel, introductionsOf} from "./funnel.js";
import type {PickSignals, PickType} from "./types.js";

export function picksDocPath(uid: string): string {
  return `users/${uid}/mevoraPicks/current`;
}

function numberOrNull(value: unknown): number | null {
  if (value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

// ---------------------------------------------------------------------------
// Signals: pool payload + evidence + humor → the measured PickSignals.
// ---------------------------------------------------------------------------

type ViewerHumor = {profile: UserHumorProfileDoc; ready: boolean};

async function loadViewerHumor(db: Firestore, uid: string): Promise<ViewerHumor> {
  const [profile, calibration] = await Promise.all([
    loadUserHumorProfile(db, uid),
    db.doc(`users/${uid}/humor/calibration`).get(),
  ]);
  return {profile, ready: isHumorCalibrationReady(calibration.data(), profile)};
}

/**
 * The real Humor Lab pair score, or null when either side has not finished
 * calibrating or carries no signal. Same function the match screen uses.
 */
async function humorFor(
  db: Firestore,
  viewer: ViewerHumor,
  candidateUid: string,
): Promise<{score: number; sharedTraits: string[]} | null> {
  if (!viewer.ready) return null;
  const [profile, calibration] = await Promise.all([
    loadUserHumorProfile(db, candidateUid),
    db.doc(`users/${candidateUid}/humor/calibration`).get(),
  ]);
  const result = humorScoreForPair(viewer.profile, profile, {
    readyA: viewer.ready,
    readyB: isHumorCalibrationReady(calibration.data(), profile),
  });
  if (!result.available || result.score === null) return null;
  return {score: result.score, sharedTraits: [...result.strongestShared]};
}

export function signalsFromPoolItem(input: {
  item: Record<string, unknown>;
  evidence: CompatibilityEvidence | undefined;
  exactKm: number | null;
  humor: {score: number; sharedTraits: string[]} | null;
  viewerProfile: DocumentData;
  viewerHasLocation: boolean;
  boosted: Set<string>;
}): PickSignals {
  const {item, evidence} = input;
  const breakdown = (item.compatibilityBreakdown ?? {}) as Record<string, unknown>;
  const goalMeasured = evidence?.relationshipGoal === true;
  const goalAligned = goalMeasured ? numberOrNull(breakdown.relationshipScore) === 100 : null;
  const sharedQuestions = numberOrNull(item.relationshipSharedViewCount) ?? 0;
  const questionScore = numberOrNull(item.relationshipCompatibilityScore);
  const musicScore = numberOrNull(item.musicCompatibilityScore);
  const tier = String(item.discoveryTier ?? "no_location");
  return {
    uid: String(item.uid),
    overall: numberOrNull(item.compatibilityScore) ?? 0,
    goalAligned,
    sharedGoal: goalAligned ? String(input.viewerProfile.relationshipGoal ?? "") || null : null,
    questions:
      questionScore !== null && sharedQuestions >= PICK_QUALITY.minSharedQuestions
        ? {
            score: questionScore,
            shared: sharedQuestions,
            aligned: numberOrNull(item.relationshipAlignedCount) ?? 0,
            topTopics: Array.isArray(item.relationshipSummaryTopics)
              ? (item.relationshipSummaryTopics as string[])
              : [],
          }
        : null,
    lifestyle: evidence?.lifestyle === true ? numberOrNull(breakdown.lifestyleScore) : null,
    interests:
      evidence?.interests === true
        ? {
            score: numberOrNull(breakdown.interestScore) ?? 0,
            sharedCount: Array.isArray(item.sharedInterests) ? item.sharedInterests.length : 0,
          }
        : null,
    music:
      musicScore !== null
        ? {
            score: musicScore,
            sharedArtistCount: numberOrNull(item.sharedMusicArtistCount) ?? 0,
            sharedTrackCount: numberOrNull(item.sharedMusicTrackCount) ?? 0,
            sharedGenreCount: numberOrNull(item.sharedMusicGenreCount) ?? 0,
          }
        : null,
    humor: input.humor,
    distanceKm: input.exactKm,
    disclosedDistanceKm: numberOrNull(item.distanceKm),
    // Inside the preferred radius — or no location on the viewer's side, in
    // which case discovery is location-independent for everyone.
    withinPreferredRadius: tier === "nearby" || (!input.viewerHasLocation && tier === "no_location"),
    isBoosted: boostAdvantageApplies(item, input.boosted),
  };
}

function cardSnapshot(
  item: Record<string, unknown>,
  humor: {score: number; sharedTraits: string[]} | null,
): PickCardSnapshot {
  const breakdown = (item.compatibilityBreakdown ?? {}) as Record<string, unknown>;
  const breakdownNumbers: Record<string, number | null> = {};
  for (const key of [
    "overallScore",
    "relationshipScore",
    "interestScore",
    "lifestyleScore",
    "questionScore",
    "musicScore",
    "communicationScore",
  ]) {
    breakdownNumbers[key] = numberOrNull(breakdown[key]);
  }
  return {
    compatibilityScore: numberOrNull(item.compatibilityScore) ?? 0,
    compatibilityBreakdown: breakdownNumbers,
    relationshipCompatibilityScore: numberOrNull(item.relationshipCompatibilityScore),
    relationshipSharedViewCount: numberOrNull(item.relationshipSharedViewCount),
    relationshipAlignedCount: numberOrNull(item.relationshipAlignedCount),
    relationshipSummaryTopics: Array.isArray(item.relationshipSummaryTopics)
      ? (item.relationshipSummaryTopics as string[]).slice(0, 3)
      : [],
    musicCompatibilityScore: numberOrNull(item.musicCompatibilityScore),
    sharedMusicArtistCount: numberOrNull(item.sharedMusicArtistCount) ?? 0,
    sharedMusicTrackCount: numberOrNull(item.sharedMusicTrackCount) ?? 0,
    sharedMusicGenreCount: numberOrNull(item.sharedMusicGenreCount) ?? 0,
    humorCompatibilityScore: humor?.score ?? null,
    sharedHumorTraits: humor?.sharedTraits.slice(0, 3) ?? [],
  };
}

// ---------------------------------------------------------------------------
// Selection against the live pool.
// ---------------------------------------------------------------------------

async function selectFromPool(input: {
  db: Firestore;
  viewer: DiscoveryViewerContext;
  exclude: Set<string>;
  slots: number;
  existing: StoredPick[];
  firstRank: number;
  /** The batch's generation id: keeps exploration stable within a batch. */
  batchKey: string;
  /** Scan bounds for this selection. */
  sizing: Pick<PicksSizing, "scanPageSize" | "scanMaxPages" | "scanShortlistSize">;
}): Promise<{
  composed: ReturnType<typeof composePicks>;
  cards: Map<string, PickCardSnapshot>;
  scanned: number;
}> {
  const {db} = input;
  if (input.slots <= 0) return {composed: [], cards: new Map(), scanned: 0};
  // Batch members and cooling-down people are excluded up front, so they cost
  // no per-candidate scoring reads.
  const viewer: DiscoveryViewerContext = {
    ...input.viewer,
    seen: new Set([...input.viewer.seen, ...input.exclude]),
  };
  const scan = await scanDiscoveryPool(db, viewer, {
    cursor: "",
    radiusKm: PICKS_CONFIG.preferredRadiusKm,
    gateKm: DISCOVERY_MAX_RADIUS_KM,
    pageSize: input.sizing.scanPageSize,
    maxPages: input.sizing.scanMaxPages,
    shouldStop: (pool) =>
      pool.nearby.length + pool.extended.length + pool.far.length + pool.no_location.length >=
      input.sizing.scanShortlistSize,
  });
  const items = [
    ...scan.buckets.nearby,
    ...scan.buckets.extended,
    ...scan.buckets.far,
    ...scan.buckets.no_location,
  ];
  // Humor costs two reads per candidate, so it is fetched only for people the
  // quality floor could admit at all.
  const viewerHumor = await loadViewerHumor(db, viewer.uid);
  const humorByUid = new Map<string, {score: number; sharedTraits: string[]} | null>();
  await Promise.all(
    items
      .filter((item) => (numberOrNull(item.compatibilityScore) ?? 0) >= PICK_QUALITY.minOverall)
      .map(async (item) => {
        humorByUid.set(String(item.uid), await humorFor(db, viewerHumor, String(item.uid)));
      }),
  );
  const signals = items.map((item) =>
    signalsFromPoolItem({
      item,
      evidence: scan.evidence.get(String(item.uid)),
      exactKm: scan.exactDistanceKm.get(String(item.uid)) ?? null,
      humor: humorByUid.get(String(item.uid)) ?? null,
      viewerProfile: viewer.viewerProfile,
      viewerHasLocation: scan.hasViewerLocation,
      boosted: viewer.boosted,
    }),
  );
  // The viewer's learned preferences: loaded once per selection, never per
  // candidate. Switched off, missing or unreadable all mean 1.00 everywhere.
  const personalization = await loadPersonalizationContext(db, viewer.uid);
  const composed = composePicks(evaluatePool(signals), {
    targetCount: input.slots + input.existing.length,
    existing: input.existing,
    firstRank: input.firstRank,
    personalization: {
      viewerUid: viewer.uid,
      batchKey: input.batchKey,
      adjustments: personalization.adjustments,
    },
  });
  const itemsByUid = new Map(items.map((item) => [String(item.uid), item]));
  const cards = new Map<string, PickCardSnapshot>();
  for (const pick of composed) {
    const item = itemsByUid.get(pick.candidateUid);
    if (item) cards.set(pick.candidateUid, cardSnapshot(item, humorByUid.get(pick.candidateUid) ?? null));
  }
  return {composed, cards, scanned: items.length};
}

function newGenerationId(): string {
  return randomBytes(9).toString("hex");
}

// ---------------------------------------------------------------------------
// The read path.
// ---------------------------------------------------------------------------

export type PicksStatus = "ready" | "lowSupply" | "empty";
export type PicksEmptyReason = "allDecided" | "noCandidates" | "learningRequired" | null;

function outcomeFor(
  viewer: DiscoveryViewerContext,
  uid: string,
  rejectReason: string | null,
): PickState {
  if (viewer.matchedUids.has(uid)) return "matched";
  if (viewer.likedUids.has(uid)) return "liked";
  if (viewer.passedUids.has(uid)) return "passed";
  return rejectReason ? "ineligible" : "active";
}

function sharedInterestsWith(viewerProfile: DocumentData, interests: unknown): string[] {
  const mine = new Set(
    ((viewerProfile.interests as string[]) ?? []).map((item) => String(item).trim().toLowerCase()),
  );
  return (Array.isArray(interests) ? interests : [])
    .map((item) => String(item))
    .filter((item) => mine.has(item.trim().toLowerCase()));
}

/**
 * Builds the response for one active Pick from fresh profile data and the
 * frozen card numbers. A Pick whose profile has since become unusable was
 * already dropped by revalidation.
 */
function pickPayload(input: {
  pick: StoredPick;
  generationId: string;
  profile: DocumentData;
  account: DocumentData | undefined;
  exactKm: number | null;
  viewer: DiscoveryViewerContext;
}): Record<string, unknown> {
  const {pick, profile, viewer} = input;
  const projection = discoveryProfileProjection({...profile, uid: pick.candidateUid});
  const disclosed = input.exactKm === null ? null : coarseDistanceLabel(input.exactKm, viewer.lang);
  const card = pick.card ?? ({} as PickCardSnapshot);
  return {
    uid: pick.candidateUid,
    profile: {...projection, isVerified: input.account?.isVerified === true},
    distanceLabel: disclosed?.label ?? null,
    distanceKm: disclosed?.bucketKm ?? null,
    compatibilityScore: card.compatibilityScore ?? pick.overallScore,
    compatibilityBreakdown: card.compatibilityBreakdown ?? {},
    relationshipCompatibilityScore: card.relationshipCompatibilityScore ?? null,
    relationshipSharedViewCount: card.relationshipSharedViewCount ?? null,
    relationshipAlignedCount: card.relationshipAlignedCount ?? null,
    relationshipSummaryTopics: card.relationshipSummaryTopics ?? [],
    musicCompatibilityScore: card.musicCompatibilityScore ?? null,
    sharedMusicArtistCount: card.sharedMusicArtistCount ?? 0,
    sharedMusicTrackCount: card.sharedMusicTrackCount ?? 0,
    sharedMusicGenreCount: card.sharedMusicGenreCount ?? 0,
    sharedInterests: sharedInterestsWith(viewer.viewerProfile, projection.interests),
    isBoosted: pick.isBoosted,
    pick: {
      pickId: pick.pickId,
      generationId: input.generationId,
      pickType: pick.pickType,
      labels: pick.labels,
      reasons: pick.reasons,
      rank: pick.rank,
      overallScore: pick.overallScore,
      humorCompatibilityScore: card.humorCompatibilityScore ?? null,
      sharedHumorTraits: card.sharedHumorTraits ?? [],
    },
  };
}

/**
 * Serves the viewer's current Picks, generating or topping up the batch when
 * the lifecycle says so. Safe to call on every screen open: a live batch is
 * only revalidated, never regenerated, so the order never jumps.
 */
export async function servePicks(input: {
  db: Firestore;
  viewer: DiscoveryViewerContext;
  boostSessions: Map<string, BoostSession>;
  nowMs?: number;
  /** The size of a batch generated by this call. Tests vary it; production uses PICKS_SIZING. */
  sizing?: PicksSizing;
}): Promise<Record<string, unknown>> {
  const {db, viewer} = input;
  const nowMs = input.nowMs ?? Date.now();
  const sizing = input.sizing ?? PICKS_SIZING;
  const ref = db.doc(picksDocPath(viewer.uid));
  const stored = parseBatch((await ref.get()).data());
  let batch: PicksBatch;
  let delivered: StoredPick[] = [];

  if (!isBatchLive(stored, nowMs)) {
    // Generate: the old batch's undecided Picks cool down, then the pool is
    // scanned with everyone in the old batch and every cooldown excluded.
    const cooldowns = cooldownsAfterExpiry(stored, nowMs);
    const exclude = new Set([...excludedFromSelection(stored, nowMs), ...Object.keys(cooldowns)]);
    const generationId = newGenerationId();
    const {composed, cards} = await selectFromPool({
      db,
      viewer,
      exclude,
      slots: sizing.targetCount,
      existing: [],
      firstRank: 0,
      batchKey: generationId,
      sizing,
    });
    delivered = buildStoredPicks(generationId, composed, cards, nowMs);
    const fresh = newBatch({generationId, nowMs, picks: delivered, cooldowns, sizing});
    // Two concurrent opens must not both generate: the first write wins and
    // the other request serves what it wrote.
    batch = await db.runTransaction(async (tx) => {
      const current = parseBatch((await tx.get(ref)).data());
      if (
        current &&
        isBatchLive(current, nowMs) &&
        current.generationId !== stored?.generationId
      ) {
        delivered = [];
        return current;
      }
      tx.set(ref, fresh);
      return fresh;
    });
  } else {
    batch = stored as PicksBatch;
  }

  // Revalidate everything still active against the canonical rule chain.
  const active = activePicks(batch);
  const checks = await revalidatePoolCandidates(
    db,
    viewer,
    active.map((pick) => pick.candidateUid),
    DISCOVERY_MAX_RADIUS_KM,
  );
  const outcomes = new Map<string, PickState>();
  for (const pick of active) {
    const check = checks.get(pick.candidateUid);
    outcomes.set(
      pick.candidateUid,
      // No check result at all means the profile could not be read: not servable.
      outcomeFor(viewer, pick.candidateUid, check ? check.rejectReason : "missing"),
    );
  }
  const revalidated = applyRevalidation(batch, outcomes, nowMs);
  let changed = revalidated.changed;
  batch = revalidated.batch;

  // Fill open slots (a short first batch, or a Pick that stopped being
  // eligible). Liked, passed and matched Picks keep their slot: today's set
  // stays finite however fast the member decides.
  if (delivered.length === 0 && needsTopUp(batch, nowMs)) {
    const {composed, cards} = await selectFromPool({
      db,
      viewer,
      exclude: excludedFromSelection(batch, nowMs),
      slots: topUpSlots(batch),
      existing: activePicks(batch),
      firstRank: batch.picks.reduce((max, pick) => Math.max(max, pick.rank + 1), 0),
      batchKey: batch.generationId,
      // Scan bounds follow the size the batch was generated with.
      sizing: picksSizing(batch.targetCount),
    });
    const replacements = buildStoredPicks(batch.generationId, composed, cards, nowMs);
    batch = replacements.length > 0 ? appendPicks(batch, replacements, nowMs) : markScanned(batch, nowMs);
    delivered = replacements;
    changed = true;
    if (replacements.length > 0) {
      const replacementChecks = await revalidatePoolCandidates(
        db,
        viewer,
        replacements.map((pick) => pick.candidateUid),
        DISCOVERY_MAX_RADIUS_KM,
      );
      for (const [uid, check] of replacementChecks) checks.set(uid, check);
    }
  }

  if (changed) {
    const generationId = batch.generationId;
    const next = batch;
    await db.runTransaction(async (tx) => {
      const current = parseBatch((await tx.get(ref)).data());
      // Another request moved the batch on in the meantime; keep theirs.
      if (current && current.generationId !== generationId) return;
      tx.set(ref, mergeConcurrentDecisions(next, current));
    });
  }

  if (delivered.length > 0) {
    await bumpFunnel(db, "delivered", delivered.map((pick) => pick.pickType), nowMs);
    // A boosted profile placed in a batch was served to this viewer.
    await recordBoostImpressions({
      db,
      viewerUid: viewer.uid,
      shownUids: delivered.filter((pick) => pick.isBoosted).map((pick) => pick.candidateUid),
      sessions: input.boostSessions,
    });
  }

  const visible = activePicks(batch).filter((pick) => {
    const check = checks.get(pick.candidateUid);
    return check && !check.rejectReason && check.profile;
  });
  const picks = visible.map((pick) => {
    const check = checks.get(pick.candidateUid)!;
    return pickPayload({
      pick,
      generationId: batch.generationId,
      profile: check.profile as DocumentData,
      account: check.account,
      exactKm: check.exactKm,
      viewer,
    });
  });
  const lowSupply = batch.deliveredCount < batch.targetCount;
  const status: PicksStatus = picks.length === 0 ? "empty" : lowSupply ? "lowSupply" : "ready";
  const decidedAny = batch.picks.some((pick) =>
    pick.state === "liked" || pick.state === "passed" || pick.state === "matched");
  const emptyReason: PicksEmptyReason =
    picks.length > 0 ? null : decidedAny ? "allDecided" : "noCandidates";
  logger.info("mevora_picks_served", {
    status,
    visible: picks.length,
    delivered: delivered.length,
    deliveredInBatch: batch.deliveredCount,
    targetCount: batch.targetCount,
    maxDeliveredCount: batch.maxDeliveredCount,
    viewerHasLocation: hasLocation(viewer.origin),
  });
  return {
    status,
    emptyReason,
    generationId: batch.generationId,
    generatedAtMs: batch.generatedAtMs,
    dayKey: logicalDayKey(batch.generatedAtMs),
    refreshAtMs: batch.refreshAtMs,
    targetCount: batch.targetCount,
    picks,
  };
}

/**
 * A decision recorded while this request was scanning must survive the write:
 * any Pick the stored document already moved out of `active` keeps that state.
 */
function mergeConcurrentDecisions(next: PicksBatch, current: PicksBatch | null): PicksBatch {
  if (!current) return next;
  const decided = new Map(
    current.picks.filter((pick) => pick.state !== "active").map((pick) => [pick.candidateUid, pick]),
  );
  if (decided.size === 0) return next;
  return {
    ...next,
    picks: next.picks.map((pick) =>
      pick.state === "active" && decided.has(pick.candidateUid) ? decided.get(pick.candidateUid)! : pick,
    ),
  };
}

// ---------------------------------------------------------------------------
// The write path: decisions, matches, deletion.
// ---------------------------------------------------------------------------

/**
 * Moves a Pick out of the viewer's active set when they like or pass it —
 * whichever screen the decision came from. Idempotent; a missing batch or a
 * candidate who was never a Pick is a no-op. Returns the Pick when there was one.
 */
export async function recordPickDecision(input: {
  db: Firestore;
  viewerUid: string;
  candidateUid: string;
  decision: PickDecision;
  nowMs?: number;
}): Promise<StoredPick | null> {
  const {db} = input;
  const nowMs = input.nowMs ?? Date.now();
  const ref = db.doc(picksDocPath(input.viewerUid));
  let result: {changed: boolean; pick: StoredPick | null} = {changed: false, pick: null};
  try {
    await db.runTransaction(async (tx) => {
      const batch = parseBatch((await tx.get(ref)).data());
      if (!batch) return;
      const applied = applyDecision(batch, input.candidateUid, input.decision, nowMs);
      result = {changed: applied.changed, pick: applied.pick};
      if (applied.changed) tx.set(ref, applied.batch);
    });
  } catch (error) {
    // The like or pass itself is already stored, and the next Picks request
    // revalidates against it — so a failure here must not fail that decision.
    logger.warn("pick_decision_record_failed", {
      decision: input.decision,
      message: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
  if (result.changed && result.pick && input.decision !== "matched") {
    await bumpFunnel(db, input.decision, [result.pick.pickType], nowMs);
  }
  return result.pick;
}

/**
 * On a new match, records which side met the other through Picks — on the
 * match itself, so the conversation milestones can be attributed later — and
 * moves the Pick to `matched` for each side that had one.
 */
export async function attributePickMatch(input: {
  db: Firestore;
  matchRef: DocumentReference;
  uidA: string;
  uidB: string;
  nowMs?: number;
}): Promise<void> {
  const {db} = input;
  const nowMs = input.nowMs ?? Date.now();
  try {
    const introductions: Record<string, {pickType: PickType; generationId: string}> = {};
    for (const [viewerUid, candidateUid] of [
      [input.uidA, input.uidB],
      [input.uidB, input.uidA],
    ]) {
      const batch = parseBatch((await db.doc(picksDocPath(viewerUid)).get()).data());
      const pick = batch?.picks.find((entry) => entry.candidateUid === candidateUid);
      if (!batch || !pick) continue;
      introductions[viewerUid] = {pickType: pick.pickType, generationId: batch.generationId};
      await recordPickDecision({db, viewerUid, candidateUid, decision: "matched", nowMs});
    }
    const types = Object.values(introductions).map((entry) => entry.pickType);
    if (types.length === 0) return;
    await input.matchRef.set({introducedByPick: introductions}, {merge: true});
    await bumpFunnel(db, "mutualMatch", [...new Set(types)], nowMs);
  } catch (error) {
    // Attribution is measurement. It must never fail the match it describes.
    logger.warn("pick_match_attribution_failed", {
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

/** Whether a stored match carries Pick attribution (for callers outside this module). */
export function isPickIntroducedMatch(match: DocumentData | undefined): boolean {
  return introductionsOf(match).size > 0;
}

/**
 * Account deletion: removes the deleted member from every other member's
 * Picks — active, decided and cooling down alike — so no trace of them
 * outlives the account in someone else's recommendations.
 */
export async function scrubDeletedMemberFromPicks(db: Firestore, uid: string): Promise<number> {
  let scrubbed = 0;
  // Bounded pages; a member can only ever appear in a finite set of batches.
  for (let page = 0; page < 20; page++) {
    const snap = await db
      .collectionGroup("mevoraPicks")
      .where("candidateUids", "array-contains", uid)
      .limit(200)
      .get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await db.runTransaction(async (tx) => {
        const raw = (await tx.get(doc.ref)).data() ?? {};
        const batch = parseBatch(raw);
        const next = batch ? scrubCandidate(batch, uid) : null;
        if (next) {
          tx.set(doc.ref, next);
        } else {
          // Unreadable or foreign-shaped: nothing in it can be served, so it
          // goes entirely — which also lets this query terminate.
          tx.delete(doc.ref);
        }
      });
      scrubbed += 1;
    }
    if (snap.size < 200) break;
  }
  return scrubbed;
}
