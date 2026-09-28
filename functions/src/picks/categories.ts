import {
  PICK_QUALITY,
  PICK_THRESHOLDS,
  PICK_TYPE_SPECIFICITY,
  PICK_WEIGHTS,
} from "./config.js";
import {
  PICK_TYPES,
  type PickEvaluation,
  type PickReason,
  type PickSignals,
  type PickType,
} from "./types.js";

/**
 * Pick category qualification and explanation.
 *
 * Pure functions over measured signals: no reads, no clock, no randomness, so
 * the same pool always yields the same categories and the same reasons.
 */

/** Engine's goal score for a pair: 100 when aligned, 35 when not. */
const GOAL_ALIGNED_SCORE = 100;
const GOAL_MISALIGNED_SCORE = 35;

/** A reason is cited only above these — below them it is not a reason. */
const REASON_FLOORS = {
  questions: 70,
  lifestyle: 70,
  humor: 70,
  music: 65,
  musicArtists: 2,
  interests: 2,
  strongOverall: PICK_THRESHOLDS.bestOverall.strongOverall,
} as const;

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

/** How far `score` clears `threshold`, as a fraction of the headroom left. */
function margin(score: number, threshold: number): number {
  if (threshold >= 100) return score >= 100 ? 1 : 0;
  return clamp01((score - threshold) / (100 - threshold));
}

function weightedAverage(parts: Array<{weight: number; score: number}>): number | null {
  const weight = parts.reduce((sum, part) => sum + part.weight, 0);
  if (weight <= 0) return null;
  return Math.round(parts.reduce((sum, part) => sum + part.score * part.weight, 0) / weight);
}

/**
 * Deep compatibility: how two people want a relationship to work.
 *
 *   deep = weighted(relationshipGoal 0.35, relationship questions 0.45,
 *                   lifestyle 0.20)
 *
 * averaged over the dimensions actually measured for both people.
 */
export function deepCompatibility(signals: PickSignals): {score: number; dimensions: number} | null {
  const w = PICK_WEIGHTS.deep;
  const parts: Array<{weight: number; score: number}> = [];
  if (signals.goalAligned !== null) {
    parts.push({
      weight: w.relationshipGoal,
      score: signals.goalAligned ? GOAL_ALIGNED_SCORE : GOAL_MISALIGNED_SCORE,
    });
  }
  if (signals.questions) {
    parts.push({weight: w.questions, score: signals.questions.score});
  }
  if (signals.lifestyle !== null) {
    parts.push({weight: w.lifestyle, score: signals.lifestyle});
  }
  const score = weightedAverage(parts);
  return score === null ? null : {score, dimensions: parts.length};
}

/**
 * Surface similarity: the things people usually notice first.
 *
 *   surface = weighted(shared interests 0.6, music taste 0.4)
 *
 * Requires measured interests — without them nobody can claim two people's
 * interests differ.
 */
export function surfaceSimilarity(signals: PickSignals): {score: number} | null {
  if (!signals.interests) return null;
  const w = PICK_WEIGHTS.surface;
  const parts: Array<{weight: number; score: number}> = [
    {weight: w.interests, score: signals.interests.score},
  ];
  if (signals.music) {
    parts.push({weight: w.music, score: signals.music.score});
  }
  const score = weightedAverage(parts);
  return score === null ? null : {score};
}

/**
 * The quality floor: strong enough overall AND at least one measured dimension
 * that is positively strong. A candidate who only avoids red flags is not a
 * Pick.
 */
export function hasPositiveEvidence(signals: PickSignals): boolean {
  return (
    signals.goalAligned === true ||
    (signals.questions !== null && signals.questions.score >= REASON_FLOORS.questions) ||
    (signals.lifestyle !== null && signals.lifestyle >= REASON_FLOORS.lifestyle) ||
    (signals.humor !== null && signals.humor.score >= REASON_FLOORS.humor) ||
    (signals.music !== null &&
      (signals.music.score >= REASON_FLOORS.music ||
        signals.music.sharedArtistCount >= REASON_FLOORS.musicArtists)) ||
    (signals.interests !== null && signals.interests.sharedCount >= REASON_FLOORS.interests)
  );
}

export function passesQualityFloor(signals: PickSignals): boolean {
  return signals.overall >= PICK_QUALITY.minOverall && hasPositiveEvidence(signals);
}

/**
 * Best Overall: one of the strongest canonical overall scores — either strong
 * in absolute terms, or near the top of this viewer's own pool.
 *
 * `poolRank` is the 0-based position of this overall score among the
 * candidates that passed the floor (ties broken by uid).
 */
export function qualifyBestOverall(signals: PickSignals, poolRank: number): boolean {
  const t = PICK_THRESHOLDS.bestOverall;
  if (signals.overall >= t.strongOverall) return true;
  return poolRank < t.poolTopN && signals.overall >= t.relativeMinOverall;
}

/** Values Match: relationship views measured, and deep compatibility strong. */
export function qualifyValuesMatch(signals: PickSignals): boolean {
  if (!signals.questions) return false;
  const deep = deepCompatibility(signals);
  return deep !== null && deep.score >= PICK_THRESHOLDS.values.minScore;
}

/** Humor Match: the real Humor Lab pair score, both calibrated. */
export function qualifyHumorMatch(signals: PickSignals): boolean {
  return signals.humor !== null && signals.humor.score >= PICK_THRESHOLDS.humor.minScore;
}

/** Music Match: the real music compatibility score, or genuinely shared artists. */
export function qualifyMusicMatch(signals: PickSignals): boolean {
  const music = signals.music;
  if (!music) return false;
  const t = PICK_THRESHOLDS.music;
  return music.score >= t.minScore || music.sharedArtistCount >= t.minSharedArtists;
}

/** Nearby Match: close by AND a strong match. Proximity alone never qualifies. */
export function qualifyNearbyMatch(signals: PickSignals): boolean {
  const t = PICK_THRESHOLDS.nearby;
  return (
    signals.distanceKm !== null &&
    signals.distanceKm <= t.maxKm &&
    signals.overall >= t.minOverall
  );
}

/**
 * Unexpected Match — someone the viewer might scroll past on surface
 * similarity, whose deeper compatibility is strong.
 *
 *   overall  >= 70                      still a strong match
 *   deep     >= 80 over >= 2 dimensions how they want a relationship to work
 *   surface  <= 40                      shared interests / music are not the draw
 *   deep - surface >= 35                and the contrast is wide
 *
 * Deep and surface are defined above; both use only measured dimensions.
 */
export function qualifyUnexpectedMatch(signals: PickSignals): boolean {
  const t = PICK_THRESHOLDS.unexpected;
  if (signals.overall < t.minOverall) return false;
  const deep = deepCompatibility(signals);
  const surface = surfaceSimilarity(signals);
  if (!deep || !surface) return false;
  return (
    deep.dimensions >= t.minDeepDimensions &&
    deep.score >= t.minDeep &&
    surface.score <= t.maxSurface &&
    deep.score - surface.score >= t.minGap
  );
}

/**
 * How strongly a candidate holds each label: the normalised margin above that
 * label's own bar, plus the label's specificity. Drives the primary reason.
 */
function labelPriority(
  type: PickType,
  signals: PickSignals,
  deep: {score: number} | null,
  surface: {score: number} | null,
): number {
  const t = PICK_THRESHOLDS;
  let strength = 0;
  switch (type) {
    case "bestOverall":
      strength = margin(signals.overall, t.bestOverall.relativeMinOverall);
      break;
    case "valuesMatch":
      strength = deep ? margin(deep.score, t.values.minScore) : 0;
      break;
    case "humorMatch":
      strength = signals.humor ? margin(signals.humor.score, t.humor.minScore) : 0;
      break;
    case "musicMatch":
      strength = signals.music
        ? Math.max(
          margin(signals.music.score, t.music.minScore),
          clamp01((signals.music.sharedArtistCount - t.music.minSharedArtists) / 7),
        )
        : 0;
      break;
    case "nearbyMatch":
      strength = signals.distanceKm === null
        ? 0
        : 0.5 * margin(signals.overall, t.nearby.minOverall) +
          0.5 * clamp01(1 - signals.distanceKm / t.nearby.maxKm);
      break;
    case "unexpectedMatch":
      strength = deep && surface
        ? 0.5 * margin(deep.score, t.unexpected.minDeep) +
          0.5 * clamp01((deep.score - surface.score - t.unexpected.minGap) / (100 - t.unexpected.minGap))
        : 0;
      break;
  }
  return Math.round((strength + PICK_TYPE_SPECIFICITY[type]) * 1000) / 1000;
}

/** Qualify one candidate for every category. */
export function evaluateCandidate(signals: PickSignals, poolRank: number): PickEvaluation {
  const deep = deepCompatibility(signals);
  const surface = surfaceSimilarity(signals);
  const passesFloor = passesQualityFloor(signals);
  const labels: PickType[] = [];
  if (passesFloor) {
    if (qualifyBestOverall(signals, poolRank)) labels.push("bestOverall");
    if (qualifyValuesMatch(signals)) labels.push("valuesMatch");
    if (qualifyHumorMatch(signals)) labels.push("humorMatch");
    if (qualifyMusicMatch(signals)) labels.push("musicMatch");
    if (qualifyNearbyMatch(signals)) labels.push("nearbyMatch");
    if (qualifyUnexpectedMatch(signals)) labels.push("unexpectedMatch");
  }
  const priority: Partial<Record<PickType, number>> = {};
  for (const label of labels) {
    priority[label] = labelPriority(label, signals, deep, surface);
  }
  return {signals, passesFloor, labels, priority, deep, surface};
}

/** Stable order used to break priority ties. */
const TYPE_ORDER: Record<PickType, number> = {
  unexpectedMatch: 0,
  humorMatch: 1,
  valuesMatch: 2,
  musicMatch: 3,
  nearbyMatch: 4,
  bestOverall: 5,
};

/** Labels ordered most meaningful first. Deterministic. */
export function rankLabels(evaluation: PickEvaluation): PickType[] {
  return [...evaluation.labels].sort((a, b) => {
    const delta = (evaluation.priority[b] ?? 0) - (evaluation.priority[a] ?? 0);
    return delta !== 0 ? delta : TYPE_ORDER[a] - TYPE_ORDER[b];
  });
}

/** The candidate's own primary reason, before any batch-level diversity. */
export function primaryPickType(evaluation: PickEvaluation): PickType | null {
  return rankLabels(evaluation)[0] ?? null;
}

function strengthOf(score: number, strongAt: number): "strong" | "notable" {
  return score >= strongAt ? "strong" : "notable";
}

/**
 * The structured reasons behind a Pick, primary-relevant first. Only measured,
 * positive signals are cited; a reason's `score` is set only when a real
 * normalised score exists.
 */
export function buildPickReasons(evaluation: PickEvaluation, pickType: PickType): PickReason[] {
  const s = evaluation.signals;
  const reasons: PickReason[] = [];
  if (s.goalAligned === true) {
    reasons.push({
      type: "relationship",
      score: null,
      strength: "strong",
      meta: s.sharedGoal ? {goal: s.sharedGoal} : {},
    });
  }
  if (s.questions && s.questions.score >= REASON_FLOORS.questions) {
    reasons.push({
      type: "values",
      score: s.questions.score,
      strength: strengthOf(s.questions.score, 85),
      meta: {
        aligned: s.questions.aligned,
        shared: s.questions.shared,
        topics: s.questions.topTopics.slice(0, 3),
      },
    });
    if (s.questions.topTopics.includes("communication")) {
      reasons.push({type: "communication", score: null, strength: "notable", meta: {}});
    }
  }
  if (s.humor && s.humor.score >= REASON_FLOORS.humor) {
    reasons.push({
      type: "humor",
      score: s.humor.score,
      strength: strengthOf(s.humor.score, 85),
      meta: {traits: s.humor.sharedTraits.slice(0, 3)},
    });
  }
  if (
    s.music &&
    (s.music.score >= REASON_FLOORS.music || s.music.sharedArtistCount >= REASON_FLOORS.musicArtists)
  ) {
    reasons.push({
      type: "music",
      score: s.music.score,
      strength: strengthOf(s.music.score, 80),
      meta: {
        artists: s.music.sharedArtistCount,
        tracks: s.music.sharedTrackCount,
        genres: s.music.sharedGenreCount,
      },
    });
  }
  if (s.lifestyle !== null && s.lifestyle >= REASON_FLOORS.lifestyle) {
    reasons.push({
      type: "lifestyle",
      score: s.lifestyle,
      strength: strengthOf(s.lifestyle, 85),
      meta: {},
    });
  }
  if (s.interests && s.interests.sharedCount >= REASON_FLOORS.interests && pickType !== "unexpectedMatch") {
    reasons.push({
      type: "interests",
      score: null,
      strength: s.interests.sharedCount >= 4 ? "strong" : "notable",
      meta: {count: s.interests.sharedCount},
    });
  }
  if (
    s.disclosedDistanceKm !== null &&
    s.distanceKm !== null &&
    s.distanceKm <= PICK_THRESHOLDS.nearby.maxKm
  ) {
    reasons.push({
      type: "distance",
      score: null,
      strength: "notable",
      meta: {km: s.disclosedDistanceKm},
    });
  }
  reasons.push({
    type: "overall",
    score: s.overall,
    strength: strengthOf(s.overall, REASON_FLOORS.strongOverall),
    meta: {},
  });
  return orderReasonsFor(pickType, reasons);
}

/** Which reason types speak most directly to each Pick type. */
const LEAD_REASONS: Record<PickType, PickReason["type"][]> = {
  bestOverall: ["overall", "relationship", "values", "lifestyle"],
  valuesMatch: ["values", "relationship", "communication", "lifestyle"],
  humorMatch: ["humor"],
  musicMatch: ["music"],
  nearbyMatch: ["distance", "overall"],
  unexpectedMatch: ["relationship", "values", "communication", "lifestyle"],
};

function orderReasonsFor(pickType: PickType, reasons: PickReason[]): PickReason[] {
  const lead = LEAD_REASONS[pickType];
  const rank = (reason: PickReason) => {
    const index = lead.indexOf(reason.type);
    return index < 0 ? lead.length : index;
  };
  // Array.prototype.sort is stable, so equal ranks keep insertion order.
  return [...reasons].sort((a, b) => rank(a) - rank(b));
}

export function isPickType(value: unknown): value is PickType {
  return typeof value === "string" && (PICK_TYPES as readonly string[]).includes(value);
}
