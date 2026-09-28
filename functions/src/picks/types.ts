/**
 * Mevora Picks — shared types.
 *
 * Identifiers here are stable API values. The client localises them; nothing
 * in this module is user-facing copy.
 */

export const PICK_TYPES = [
  "bestOverall",
  "valuesMatch",
  "humorMatch",
  "musicMatch",
  "nearbyMatch",
  "unexpectedMatch",
] as const;
export type PickType = (typeof PICK_TYPES)[number];

export const PICK_REASON_TYPES = [
  "overall",
  "relationship",
  "values",
  "communication",
  "lifestyle",
  "humor",
  "music",
  "distance",
  "interests",
] as const;
export type PickReasonType = (typeof PICK_REASON_TYPES)[number];

/** How far a reason clears its bar. The client words the two differently. */
export type PickReasonStrength = "strong" | "notable";

/**
 * One structured, evidence-backed reason. `score` is present only when a real
 * normalised 0-100 score exists for it; the client must never invent one.
 * `meta` carries counts and category keys only — never another member's raw
 * data.
 */
export interface PickReason {
  type: PickReasonType;
  score: number | null;
  strength: PickReasonStrength;
  meta: Record<string, string | number | string[]>;
}

/**
 * Everything the Picks logic knows about one viewer/candidate pair. Each
 * dimension is `null` when it was not actually measured for BOTH people —
 * a neutral default is not evidence and must not become a reason.
 */
export interface PickSignals {
  uid: string;
  /** Canonical overall compatibility (calculateCompatibility). */
  overall: number;
  /** Both chose a relationship goal: whether they chose the same one. */
  goalAligned: boolean | null;
  /** The viewer's goal key, only when aligned (it is then also the candidate's). */
  sharedGoal: string | null;
  /** Relationship-question agreement, when enough questions were shared. */
  questions: {
    score: number;
    shared: number;
    aligned: number;
    topTopics: string[];
  } | null;
  /** Canonical lifestyle score, when both described their lifestyle. */
  lifestyle: number | null;
  /** Canonical interest overlap (0-100), when both listed interests. */
  interests: {score: number; sharedCount: number} | null;
  music: {
    score: number;
    sharedArtistCount: number;
    sharedTrackCount: number;
    sharedGenreCount: number;
  } | null;
  humor: {score: number; sharedTraits: string[]} | null;
  /** Exact distance in km, server-side only; null when either has no location. */
  distanceKm: number | null;
  /** Disclosed (quantised) distance bucket — the only distance a reason may carry. */
  disclosedDistanceKm: number | null;
  /** Within the preferred radius (or location-independent). */
  withinPreferredRadius: boolean;
  isBoosted: boolean;
}

/** A candidate after qualification. */
export interface PickEvaluation {
  signals: PickSignals;
  /** Passes the quality floor (overall + positive evidence). */
  passesFloor: boolean;
  /** Every category this candidate genuinely qualifies for. */
  labels: PickType[];
  /** Per-label priority used to choose the primary reason. */
  priority: Partial<Record<PickType, number>>;
  deep: {score: number; dimensions: number} | null;
  surface: {score: number} | null;
}

/** One Pick as composed into a batch. */
export interface ComposedPick {
  candidateUid: string;
  rank: number;
  pickType: PickType;
  labels: PickType[];
  reasons: PickReason[];
  overallScore: number;
  isBoosted: boolean;
}
