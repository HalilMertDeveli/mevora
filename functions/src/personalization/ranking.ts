import {createHash} from "node:crypto";
import {
  ADJUSTMENT_BOUNDS,
  EXPLORATION,
  PERSONALIZATION_ALGORITHM_VERSION,
  PERSONALIZATION_DIMENSIONS,
  RANKING,
  type PersonalizationDimension,
} from "./config.js";
import {centredScore, type Adjustments, type DimensionVector} from "./learner.js";

/**
 * Ranking side of adaptive personalization. Pure and deterministic.
 *
 * The canonical engine stays the only source of compatibility. Personalization
 * re-weights how far each measured dimension sits from neutral:
 *
 *   term_d = pointsPerUnit × (adjustment_d − 1) × (score_d − 50) / 50
 *
 * This is dimension-level re-weighting centred on neutral: with every
 * adjustment at 1.00 every term is 0 and ranking is exactly the canonical
 * order. A dimension that was not measured for both people contributes
 * nothing. Each term and the total are capped, so no single dimension can
 * outweigh the rest of the profile, and the result is a RANKING term only:
 * the public compatibility percentage and the quality floor never see it.
 */

export type SelectionStrategy = "exploit" | "explore";

export interface DimensionContribution {
  dimension: PersonalizationDimension;
  base: number | null;
  adjustment: number;
  points: number;
}

export interface PersonalRankingExplanation {
  baseOverall: number;
  contributions: DimensionContribution[];
  personalPoints: number;
  rankingScore: number;
}

export function personalRankingPoints(
  vector: DimensionVector,
  adjustments: Adjustments,
): {points: number; contributions: DimensionContribution[]} {
  const contributions: DimensionContribution[] = [];
  let total = 0;
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const score = vector[dimension];
    const base = typeof score === "number" && Number.isFinite(score) ? score : null;
    const adjustment = adjustments[dimension] ?? ADJUSTMENT_BOUNDS.neutral;
    const raw = base === null
      ? 0
      : RANKING.pointsPerUnit * (adjustment - ADJUSTMENT_BOUNDS.neutral) * centredScore(base);
    const points = Math.max(-RANKING.maxDimensionPoints, Math.min(RANKING.maxDimensionPoints, raw));
    total += points;
    contributions.push({dimension, base, adjustment, points: round2(points)});
  }
  const capped = Math.max(-RANKING.maxTotalPoints, Math.min(RANKING.maxTotalPoints, total));
  return {points: round2(capped), contributions};
}

export function explainPersonalRanking(
  baseOverall: number,
  vector: DimensionVector,
  adjustments: Adjustments,
): PersonalRankingExplanation {
  const {points, contributions} = personalRankingPoints(vector, adjustments);
  return {
    baseOverall,
    contributions,
    personalPoints: points,
    rankingScore: round2(baseOverall + points),
  };
}

/** True once at least one dimension has moved meaningfully away from neutral. */
export function isPersonalizationActive(adjustments: Adjustments): boolean {
  return PERSONALIZATION_DIMENSIONS.some(
    (dimension) =>
      Math.abs((adjustments[dimension] ?? 1) - ADJUSTMENT_BOUNDS.neutral) >= RANKING.activeThreshold,
  );
}

/** How many of `slots` go to exploration. Zero until personalization is active. */
export function explorationSlotCount(slots: number, active: boolean): number {
  if (!active || slots < 2) return 0;
  return Math.min(slots - 1, Math.max(EXPLORATION.minSlots, Math.round(slots * EXPLORATION.ratio)));
}

/**
 * Where exploration slots sit in a batch: spread through the middle, never
 * first (the lead Pick is the strongest personal fit) and not dumped last.
 */
export function explorationSlotPositions(slots: number, count: number): Set<number> {
  const out = new Set<number>();
  if (count <= 0) return out;
  for (let i = 1; i <= count; i++) {
    const position = Math.min(slots - 1, Math.max(1, Math.floor((slots * i) / (count + 1))));
    out.add(position);
  }
  return out;
}

/**
 * Stable per-batch jitter in [0, jitterPoints). The same viewer, candidate and
 * batch always hash the same, so reopening the app never reshuffles; a new
 * batch rotates which strong-but-unfamiliar candidate gets the slot.
 */
export function explorationJitter(viewerUid: string, candidateUid: string, batchKey: string): number {
  const digest = createHash("sha256")
    .update(`${PERSONALIZATION_ALGORITHM_VERSION}|${viewerUid}|${candidateUid}|${batchKey}`)
    .digest();
  return (digest.readUInt32BE(0) / 0x1_0000_0000) * EXPLORATION.jitterPoints;
}

/**
 * An exploration candidate is strong on its own and NOT favoured by what has
 * been learned so far (personal points ≤ 0) — "slightly outside the pattern",
 * never a weak or ineligible one.
 */
export function isExplorationCandidate(baseOverall: number, personalPoints: number): boolean {
  return baseOverall >= EXPLORATION.minOverall && personalPoints <= 0;
}

export function explorationScore(
  baseOverall: number,
  viewerUid: string,
  candidateUid: string,
  batchKey: string,
): number {
  return baseOverall + explorationJitter(viewerUid, candidateUid, batchKey);
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * The personalization vector from the Picks per-candidate signals. Structural,
 * so this module does not depend on the Picks types. Every field is null when
 * the dimension was not measured for both people.
 */
export interface MeasuredSignalsLike {
  goalAligned: boolean | null;
  questions: {score: number} | null;
  lifestyle: number | null;
  interests: {score: number} | null;
  music: {score: number} | null;
  humor: {score: number} | null;
}

/** Engine scores for a set / different relationship goal (relationshipGoalScore). */
const GOAL_ALIGNED_SCORE = 100;
const GOAL_DIFFERENT_SCORE = 35;

export function vectorFromSignals(signals: MeasuredSignalsLike): DimensionVector {
  return {
    relationship:
      signals.goalAligned === null
        ? null
        : signals.goalAligned
          ? GOAL_ALIGNED_SCORE
          : GOAL_DIFFERENT_SCORE,
    values: signals.questions?.score ?? null,
    lifestyle: signals.lifestyle ?? null,
    interests: signals.interests?.score ?? null,
    music: signals.music?.score ?? null,
    humor: signals.humor?.score ?? null,
  };
}
