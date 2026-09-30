import {randomBytes} from "node:crypto";
import type {DocumentData, DocumentReference, Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {HttpsError} from "firebase-functions/v2/https";
import {coarseDistanceLabel} from "../geo/coarseDistance.js";
import {discoveryProfileProjection} from "../profileSafety.js";
import {DISCOVERY_MAX_RADIUS_KM} from "../discoveryFallback.js";
import {boostAdvantageApplies} from "../boost/ranking.js";
import {recordBoostImpressions, type BoostSession} from "../boost/measurement.js";
import {
  hasLocation,
  loadPairDecisions,
  revalidatePoolCandidates,
  scanDiscoveryPool,
  withPairDecisions,
  type DiscoveryViewerContext,
  type RevalidatedCandidate,
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
  topUpScanDue,
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
  /** What the scan read about every candidate it accepted (see DiscoveryPoolScan.accepted). */
  accepted: Map<string, RevalidatedCandidate>;
}> {
  const {db} = input;
  if (input.slots <= 0) return {composed: [], cards: new Map(), scanned: 0, accepted: new Map()};
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
  return {composed, cards, scanned: items.length, accepted: scan.accepted};
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
  /**
   * The viewer. With its history loaded (loadDiscoveryViewerContext) it is
   * used for everything; with basics only (loadDiscoveryViewerBasics) it is
   * enough to reopen today's batch, and `loadFullViewer` supplies the
   * history when a pool scan has to run.
   */
  viewer: DiscoveryViewerContext;
  boostSessions?: Map<string, BoostSession>;
  loadFullViewer?: () => Promise<{viewer: DiscoveryViewerContext; boostSessions: Map<string, BoostSession>}>;
  nowMs?: number;
  /** The size of a batch generated by this call. Tests vary it; production uses PICKS_SIZING. */
  sizing?: PicksSizing;
}): Promise<Record<string, unknown>> {
  const {db} = input;
  const nowMs = input.nowMs ?? Date.now();
  const sizing = input.sizing ?? PICKS_SIZING;
  let viewer = input.viewer;
  let full: {viewer: DiscoveryViewerContext; boostSessions: Map<string, BoostSession>} | null =
    viewer.historyLoaded === false ? null : {viewer, boostSessions: input.boostSessions ?? new Map()};
  const fullViewer = async () => {
    if (!full) {
      if (!input.loadFullViewer) throw new Error("servePicks: a pool scan needs the viewer's history");
      full = await input.loadFullViewer();
    }
    viewer = full.viewer;
    return full;
  };
  const ref = db.doc(picksDocPath(viewer.uid));
  const stored = parseBatch((await ref.get()).data());
  let batch: PicksBatch;
  let delivered: StoredPick[] = [];
  // Candidates this request has already checked against the full rule chain
  // (the pool scan that just picked them): not read a second time.
  let known = new Map<string, RevalidatedCandidate>();

  if (!isBatchLive(stored, nowMs)) {
    const {viewer: scanning} = await fullViewer();
    ({batch, delivered, known} = await generateOnce({db, ref, viewer: scanning, nowMs, sizing}));
  } else {
    batch = stored as PicksBatch;
  }

  // Revalidate everything still active against the canonical rule chain.
  // Reopening today's batch does not read the member's whole history: the
  // decisions about these few people are looked up pair by pair. Blocks are
  // checked per pair inside the rule chain either way, so a block hides the
  // Pick on the very next open.
  const active = activePicks(batch);
  const toCheck = active.map((pick) => pick.candidateUid).filter((uid) => !known.has(uid));
  if (!full && toCheck.length > 0) {
    viewer = withPairDecisions(viewer, await loadPairDecisions(db, viewer.uid, toCheck));
  }
  const checks = await revalidatePoolCandidates(db, viewer, toCheck, DISCOVERY_MAX_RADIUS_KM);
  for (const [uid, check] of known) checks.set(uid, check);
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

  // Replace Picks that stopped being eligible, one for one, within the day's
  // ceiling. Liked, passed and matched Picks keep their slot, and a short
  // batch stays short: today's set is finite however fast the member decides.
  // The scan slot is claimed first, so two opens never pay for the same scan.
  if (delivered.length === 0 && needsTopUp(batch, nowMs) && (await claimTopUpScan(db, ref, batch, nowMs))) {
    const {viewer: scanning} = await fullViewer();
    const {composed, cards, accepted} = await selectFromPool({
      db,
      viewer: scanning,
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
    // The scan that chose them just checked them.
    for (const pick of replacements) {
      const check = accepted.get(pick.candidateUid);
      if (check) checks.set(pick.candidateUid, check);
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
      // Anything delivered came from a scan, which loaded the live Boosts.
      sessions: full?.boostSessions ?? new Map(),
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

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type GenerationClaim =
  | {kind: "live"; batch: PicksBatch}
  | {kind: "wait"}
  | {kind: "acquired"; previous: PicksBatch | null};

/**
 * Takes the day's generation lease on the member's batch document, unless a
 * live batch already exists (someone generated it meanwhile) or another open
 * holds an unexpired lease. The lease is a field beside the batch; writing
 * the fresh batch replaces the document and so releases it.
 */
async function claimGeneration(
  db: Firestore,
  ref: DocumentReference,
  token: string,
  nowMs: number,
): Promise<GenerationClaim> {
  return db.runTransaction(async (tx) => {
    const raw = (await tx.get(ref)).data();
    const current = parseBatch(raw);
    if (current && isBatchLive(current, nowMs)) return {kind: "live", batch: current};
    const lease = (raw?.generationLease ?? null) as {token?: unknown; untilMs?: unknown} | null;
    const leaseUntil = Number(lease?.untilMs);
    if (lease && lease.token !== token && Number.isFinite(leaseUntil) && leaseUntil > nowMs) {
      return {kind: "wait"};
    }
    tx.set(ref, {generationLease: {token, untilMs: nowMs + PICKS_CONFIG.generationLeaseMs}}, {merge: true});
    return {kind: "acquired", previous: current};
  });
}

/** Drops this open's lease after a failed generation, so the next open need not wait it out. */
async function releaseGeneration(db: Firestore, ref: DocumentReference, token: string): Promise<void> {
  try {
    await db.runTransaction(async (tx) => {
      const raw = (await tx.get(ref)).data();
      const lease = raw?.generationLease as {token?: unknown} | undefined;
      if (lease?.token !== token) return;
      const rest = {...raw};
      delete rest.generationLease;
      tx.set(ref, rest);
    });
  } catch (error) {
    // The lease expires on its own; releasing it early is only a courtesy.
    logger.warn("picks_generation_release_failed", {
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

/**
 * Generates today's batch at most once per member, however many opens race
 * for it. The winner scans the pool and writes the batch; every other open
 * waits for that batch and serves it. If the winner dies, its lease lapses
 * after `generationLeaseMs` and the next open takes over.
 */
async function generateOnce(input: {
  db: Firestore;
  ref: DocumentReference;
  viewer: DiscoveryViewerContext;
  nowMs: number;
  sizing: PicksSizing;
}): Promise<{batch: PicksBatch; delivered: StoredPick[]; known: Map<string, RevalidatedCandidate>}> {
  const {db, ref, viewer, nowMs, sizing} = input;
  const token = newGenerationId();
  const startedAt = Date.now();
  let previous: PicksBatch | null = null;
  for (;;) {
    const elapsed = Date.now() - startedAt;
    const claim = await claimGeneration(db, ref, token, nowMs + elapsed);
    if (claim.kind === "live") return {batch: claim.batch, delivered: [], known: new Map()};
    if (claim.kind === "acquired") {
      previous = claim.previous;
      break;
    }
    if (elapsed > 2 * PICKS_CONFIG.generationLeaseMs) {
      // A lease is renewed by nobody, so this only happens if the clock or
      // the store misbehaves. Fail this open rather than spin.
      throw new HttpsError("unavailable", "picks-generation-busy");
    }
    await sleep(PICKS_CONFIG.generationWaitPollMs);
  }
  try {
    // The old batch's undecided Picks cool down, then the pool is scanned
    // with everyone in the old batch and every cooldown excluded.
    const cooldowns = cooldownsAfterExpiry(previous, nowMs);
    const exclude = new Set([...excludedFromSelection(previous, nowMs), ...Object.keys(cooldowns)]);
    const generationId = newGenerationId();
    const {composed, cards, accepted} = await selectFromPool({
      db,
      viewer,
      exclude,
      slots: sizing.targetCount,
      existing: [],
      firstRank: 0,
      batchKey: generationId,
      sizing,
    });
    const picks = buildStoredPicks(generationId, composed, cards, nowMs);
    const fresh = newBatch({generationId, nowMs, picks, cooldowns, sizing});
    return await db.runTransaction(async (tx) => {
      const current = parseBatch((await tx.get(ref)).data());
      // Our lease lapsed and another open wrote today's batch first: serve theirs.
      if (current && isBatchLive(current, nowMs)) return {batch: current, delivered: [], known: new Map()};
      tx.set(ref, fresh);
      const known = new Map<string, RevalidatedCandidate>();
      for (const pick of picks) {
        const check = accepted.get(pick.candidateUid);
        if (check) known.set(pick.candidateUid, check);
      }
      return {batch: fresh, delivered: picks, known};
    });
  } catch (error) {
    await releaseGeneration(db, ref, token);
    throw error;
  }
}

/**
 * Claims the replacement scan for this open by moving the scan clock, so a
 * concurrent open of the same batch sees it as just scanned and skips its own
 * scan. False when another open claimed it first or the batch moved on.
 */
async function claimTopUpScan(
  db: Firestore,
  ref: DocumentReference,
  batch: PicksBatch,
  nowMs: number,
): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const current = parseBatch((await tx.get(ref)).data());
    if (!current || current.generationId !== batch.generationId) return false;
    if (!topUpScanDue(current, nowMs)) return false;
    tx.update(ref, {lastScanAtMs: nowMs});
    return true;
  });
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
