/**
 * Every tunable number behind Mevora Picks, in one place.
 *
 * All scores are on the canonical 0-100 compatibility scale produced by
 * compatibility/compatibilityEngine.ts, humor/compatibility.ts and
 * musicCompatibility.ts. Nothing here is a new scoring system: these are the
 * thresholds at which an existing, measured score counts as a reason to
 * introduce two people.
 */

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

export const PICKS_CONFIG = {
  /** How many Picks a fresh batch aims for. Fewer is shown when supply is weak. */
  targetCount: 6,
  /**
   * Most Picks one batch may ever deliver, replacements included. Liked,
   * passed and matched Picks are never replaced — only ones that stopped
   * being eligible (block, deletion, hidden) — so deciding quickly does not
   * buy more people. Keeps the curated set finite: once reached, the next
   * people arrive with the next day's batch rather than as an endless refill.
   */
  maxDeliveredPerBatch: 10,
  /**
   * Picks are a DAILY set: a batch lives until the next logical-day boundary
   * (midnight at this UTC offset — Europe/Istanbul, which has no DST), so
   * reopening the app never reshuffles today and tomorrow brings new people.
   * Batches stored before daily Picks keep the refresh time they were given.
   */
  logicalDayUtcOffsetMinutes: 180,
  /**
   * Open slots (a short first batch, or a Pick that stopped being eligible)
   * are looked for at most this often. A top-up needs a pool scan, so a
   * low-supply viewer reopening the app must not pay for one on every visit.
   */
  topUpMinIntervalMs: 30 * 60 * 1000,
  /**
   * A Pick that expires undecided rests for this long before it may be picked
   * again, so the same faces do not recycle day after day. The person stays
   * reachable in Discover More throughout. Liked, passed and matched people
   * never return to Picks: those exclusions come from the canonical Discover
   * state (likes, passedUsers, matches) and are permanent there.
   */
  expiredCooldownMs: 3 * DAY_MS,
  /**
   * Picks come from inside the viewer's preferred radius first, and reach
   * beyond it (never past the Discover hard ceiling) only when the preferred
   * radius cannot fill the batch with candidates who clear the quality floor.
   */
  preferredRadiusKm: 50,
  /** Pool scan bounds, per generation. Same page size as Discover. */
  scanPageSize: 40,
  scanMaxPages: 4,
  /** Stop scanning once this many eligible candidates are scored. */
  scanShortlistSize: 60,
} as const;

/**
 * The quality floor. A candidate becomes a Pick only with a strong enough
 * canonical overall score AND at least one dimension of positive evidence
 * (see `hasPositiveEvidence` in categories.ts). Below the floor nobody is
 * picked, however short the batch runs.
 */
export const PICK_QUALITY = {
  minOverall: 62,
  /** A relationship-question signal needs this many questions both answered. */
  minSharedQuestions: 3,
} as const;

/** Category thresholds. Each is a floor on a real, measured score. */
export const PICK_THRESHOLDS = {
  bestOverall: {
    /** Absolute: this strong overall always qualifies. */
    strongOverall: 78,
    /** Relative: among the top N overall scores of the scored pool... */
    poolTopN: 2,
    /** ...provided the score is at least this. */
    relativeMinOverall: 70,
  },
  values: {
    /**
     * Weighted blend of relationship goal, relationship-question agreement
     * and lifestyle. Needs question evidence: a shared goal alone is not
     * enough to claim shared values.
     */
    minScore: 80,
  },
  humor: {minScore: 75},
  music: {
    minScore: 70,
    /** Or this many shared artists, whatever the blended score. */
    minSharedArtists: 3,
  },
  nearby: {
    /** "Meaningfully nearby", on the exact server-side distance. */
    maxKm: 10,
    /** Nearby alone never qualifies: the pair must also be a strong match. */
    minOverall: 70,
  },
  unexpected: {
    /** Still a strong match overall — never a filler or a random pick. */
    minOverall: 70,
    /** Deep compatibility (values, relationship views, lifestyle) is high... */
    minDeep: 80,
    /** ...across at least this many measured deep dimensions... */
    minDeepDimensions: 2,
    /** ...while surface similarity (shared interests, music) is at most medium... */
    maxSurface: 40,
    /** ...by a wide margin. Keeps the category rare enough to mean something. */
    minGap: 35,
  },
} as const;

/** Weights inside the two blended scores. Only measured parts are averaged. */
export const PICK_WEIGHTS = {
  deep: {relationshipGoal: 0.35, questions: 0.45, lifestyle: 0.2},
  surface: {interests: 0.6, music: 0.4},
} as const;

/**
 * Set composition. Ranking starts from the canonical overall score; these are
 * small, bounded adjustments on top of it.
 */
export const PICK_COMPOSITION = {
  /**
   * Taken off a candidate's rank for each Pick already in the batch whose
   * primary reason it would repeat. Bounded, so a candidate this many points
   * (or more) better still wins over a diverse but weaker one.
   */
  repeatPenalty: 5,
  maxRepeatPenalty: 12,
  /**
   * Boost inside Picks. Much smaller than Discover's priorityBonus: Picks are
   * curated, so Boost may only break near-ties between candidates who already
   * cleared the quality floor on their own.
   */
  boostBonus: 4,
  /** At most this many boosted profiles per batch. */
  maxBoostedPerBatch: 1,
  /** Unexpected Match is a signature category; one per batch at most. */
  maxUnexpectedPerBatch: 1,
} as const;

/**
 * How distinctive each category is when a candidate qualifies for several.
 * Added to the normalised margin above the category's own threshold when the
 * primary reason is chosen, so a specific reason ("your humor lines up") wins
 * over the generic one ("strong overall") unless the generic one is much
 * stronger. Order doubles as the deterministic tie-break.
 */
export const PICK_TYPE_SPECIFICITY = {
  unexpectedMatch: 0.3,
  humorMatch: 0.15,
  valuesMatch: 0.15,
  musicMatch: 0.12,
  nearbyMatch: 0.05,
  bestOverall: 0,
} as const;

export const PICKS_SCHEMA_VERSION = 1;
