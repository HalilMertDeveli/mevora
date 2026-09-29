import {
  ADJUSTMENT_BOUNDS,
  LEARNING,
  PERSONALIZATION_ALGORITHM_VERSION,
  PERSONALIZATION_DIMENSIONS,
  type PersonalizationDimension,
} from "./config.js";

/**
 * The observed-preference learner. Pure and deterministic: the same profile,
 * event and clock always give the same result, and nothing here reads
 * Firestore, the wall clock or a random source.
 *
 * For each dimension the candidate was actually measured on:
 *
 *   c        = (score - 50) / 50                  in [-1, 1]  (0 when |c| is tiny)
 *   signal   = strength * c
 *   positive += max(signal, 0);  negative += max(-signal, 0);  evidence += |signal|
 *   mean     = (positive - negative) / (evidence + prior)      in (-1, 1)
 *   target   = clamp(1 + gain * mean, 0.70, 1.30)
 *   adjust   = previous + clamp(target - previous, +-maxStep)
 *
 * So a good outcome with someone high on humor is evidence humor matters; a
 * good outcome with someone LOW on humor is evidence it matters less; a bad
 * outcome with someone high on humor counts against it. A dimension the
 * candidate sits at neutral on learns nothing. The prior keeps cold-start
 * members near 1.00, and evidence decays with a half-life so tastes can move.
 */

/** A candidate's canonical 0-100 score per dimension; null when not measured for both. */
export type DimensionVector = Partial<Record<PersonalizationDimension, number | null>>;

export interface DimensionState {
  adjustment: number;
  evidence: number;
  positive: number;
  negative: number;
}

export interface PersonalizationProfile {
  algorithmVersion: number;
  dimensions: Record<PersonalizationDimension, DimensionState>;
  eventCount: number;
  /** When evidence was last decayed/updated. Null for a profile never updated. */
  updatedAtMs: number | null;
  /** Different people strong outcomes came from (see LEARNING.minDistinctPartners). */
  partnerCount: number;
  /** UTC day `dayMovement` belongs to. */
  dayKey: string | null;
  /** How far each dimension already moved on `dayKey` (see maxDailyMovePerDimension). */
  dayMovement: Partial<Record<PersonalizationDimension, number>>;
}

export interface LearningEvent {
  type: string;
  /** Signed outcome strength (see SIGNAL_STRENGTHS / WEAK_SIGNALS). */
  strength: number;
  vector: DimensionVector;
}

export interface DimensionTrace {
  dimension: PersonalizationDimension;
  candidateScore: number;
  centred: number;
  signal: number;
  before: number;
  target: number;
  after: number;
}

export interface LearningTrace {
  type: string;
  strength: number;
  decayFactor: number;
  dimensions: DimensionTrace[];
}

function neutralDimension(): DimensionState {
  return {adjustment: ADJUSTMENT_BOUNDS.neutral, evidence: 0, positive: 0, negative: 0};
}

export function neutralProfile(): PersonalizationProfile {
  const dimensions = {} as Record<PersonalizationDimension, DimensionState>;
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    dimensions[dimension] = neutralDimension();
  }
  return {
    algorithmVersion: PERSONALIZATION_ALGORITHM_VERSION,
    dimensions,
    eventCount: 0,
    updatedAtMs: null,
    partnerCount: 0,
    dayKey: null,
    dayMovement: {},
  };
}

function utcDay(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

export function clampAdjustment(value: number): number {
  if (!Number.isFinite(value)) return ADJUSTMENT_BOUNDS.neutral;
  return Math.min(ADJUSTMENT_BOUNDS.max, Math.max(ADJUSTMENT_BOUNDS.min, value));
}

function finiteNonNegative(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/**
 * Reads a stored profile defensively. Missing, legacy, corrupt or
 * future-version state all come back usable: unknown versions and anything
 * malformed fall back to neutral rather than steering ranking on data this
 * code does not understand.
 */
export function parseProfile(raw: unknown): PersonalizationProfile {
  const profile = neutralProfile();
  if (!raw || typeof raw !== "object") return profile;
  const data = raw as Record<string, unknown>;
  if (data.algorithmVersion !== PERSONALIZATION_ALGORITHM_VERSION) return profile;
  const dims = (data.dimensions ?? {}) as Record<string, unknown>;
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const stored = dims[dimension];
    if (!stored || typeof stored !== "object") continue;
    const s = stored as Record<string, unknown>;
    profile.dimensions[dimension] = {
      adjustment: clampAdjustment(Number(s.adjustment ?? ADJUSTMENT_BOUNDS.neutral)),
      evidence: finiteNonNegative(s.evidence),
      positive: finiteNonNegative(s.positive),
      negative: finiteNonNegative(s.negative),
    };
  }
  profile.eventCount = Math.floor(finiteNonNegative(data.eventCount));
  const updated = Number(data.updatedAtMs);
  profile.updatedAtMs = Number.isFinite(updated) && updated > 0 ? updated : null;
  profile.partnerCount = Math.floor(finiteNonNegative(data.partnerCount));
  profile.dayKey = typeof data.dayKey === "string" ? data.dayKey : null;
  const movement = (data.dayMovement ?? {}) as Record<string, unknown>;
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const moved = finiteNonNegative(movement[dimension]);
    if (moved > 0) profile.dayMovement[dimension] = moved;
  }
  return profile;
}

/** Firestore-safe plain object for a profile. */
export function serializeProfile(profile: PersonalizationProfile): Record<string, unknown> {
  const dimensions: Record<string, unknown> = {};
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const d = profile.dimensions[dimension];
    dimensions[dimension] = {
      adjustment: round(d.adjustment, 4),
      evidence: round(d.evidence, 4),
      positive: round(d.positive, 4),
      negative: round(d.negative, 4),
    };
  }
  return {
    algorithmVersion: profile.algorithmVersion,
    dimensions,
    eventCount: profile.eventCount,
    updatedAtMs: profile.updatedAtMs,
    partnerCount: profile.partnerCount,
    dayKey: profile.dayKey,
    dayMovement: Object.fromEntries(
      Object.entries(profile.dayMovement).map(([dimension, moved]) => [dimension, round(moved ?? 0, 4)]),
    ),
  };
}

function round(value: number, places: number): number {
  const f = 10 ** places;
  return Math.round(value * f) / f;
}

/** 0-100 score -> centred evidence weight in [-1, 1], zero near neutral. */
export function centredScore(score: number | null | undefined): number {
  if (score === null || score === undefined || !Number.isFinite(score)) return 0;
  const c = Math.max(-1, Math.min(1, (score - 50) / 50));
  return Math.abs(c) < LEARNING.minCentredMagnitude ? 0 : c;
}

export function decayFactor(fromMs: number | null, toMs: number): number {
  if (fromMs === null || toMs <= fromMs) return 1;
  const days = (toMs - fromMs) / 86_400_000;
  return 0.5 ** (days / LEARNING.halfLifeDays);
}

/**
 * Apply one learning event. Returns a new profile (the input is not mutated)
 * and a trace a developer can read to see exactly why each weight moved.
 */
export function applyLearningEvent(
  current: PersonalizationProfile,
  event: LearningEvent,
  nowMs: number,
): {profile: PersonalizationProfile; trace: LearningTrace} {
  const factor = decayFactor(current.updatedAtMs, nowMs);
  const today = utcDay(nowMs);
  const movedToday: Partial<Record<PersonalizationDimension, number>> =
    current.dayKey === today ? {...current.dayMovement} : {};
  const next: PersonalizationProfile = {
    algorithmVersion: PERSONALIZATION_ALGORITHM_VERSION,
    dimensions: {} as Record<PersonalizationDimension, DimensionState>,
    eventCount: current.eventCount + 1,
    updatedAtMs: Math.max(nowMs, current.updatedAtMs ?? 0),
    partnerCount: current.partnerCount ?? 0,
    dayKey: today,
    dayMovement: movedToday,
  };
  const strength = Number.isFinite(event.strength) ? event.strength : 0;
  const traces: DimensionTrace[] = [];

  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const prev = current.dimensions[dimension] ?? neutralDimension();
    const state: DimensionState = {
      adjustment: clampAdjustment(prev.adjustment),
      evidence: prev.evidence * factor,
      positive: prev.positive * factor,
      negative: prev.negative * factor,
    };
    const score = event.vector[dimension];
    const centred = typeof score === "number" ? centredScore(score) : 0;
    const signal = strength * centred;

    if (signal !== 0) {
      state.positive += Math.max(signal, 0);
      state.negative += Math.max(-signal, 0);
      state.evidence += Math.abs(signal);
      const mean = (state.positive - state.negative) / (state.evidence + LEARNING.priorEvidence);
      const target = clampAdjustment(ADJUSTMENT_BOUNDS.neutral + LEARNING.gain * mean);
      // Per event and per day: however many events land at once, a dimension
      // drifts, it never jumps.
      const dayBudget = Math.max(0, LEARNING.maxDailyMovePerDimension - (movedToday[dimension] ?? 0));
      const step = Math.min(LEARNING.maxStepPerEvent, dayBudget);
      const delta = Math.max(-step, Math.min(step, target - state.adjustment));
      const before = state.adjustment;
      state.adjustment = clampAdjustment(before + delta);
      const moved = Math.abs(state.adjustment - before);
      if (moved > 0) movedToday[dimension] = (movedToday[dimension] ?? 0) + moved;
      traces.push({
        dimension,
        candidateScore: score as number,
        centred,
        signal,
        before,
        target,
        after: state.adjustment,
      });
    }
    next.dimensions[dimension] = state;
  }
  return {
    profile: next,
    trace: {type: event.type, strength, decayFactor: factor, dimensions: traces},
  };
}

export type Adjustments = Record<PersonalizationDimension, number>;

export function neutralAdjustments(): Adjustments {
  const out = {} as Adjustments;
  for (const dimension of PERSONALIZATION_DIMENSIONS) out[dimension] = ADJUSTMENT_BOUNDS.neutral;
  return out;
}

/** Whether enough different people stand behind what was learned. */
export function isObservedConfident(profile: PersonalizationProfile | null): boolean {
  return !!profile && (profile.partnerCount ?? 0) >= LEARNING.minDistinctPartners;
}

/**
 * The OBSERVED adjustments ranking should use. Personalization OFF behaves
 * exactly as if nothing had ever been learned: every dimension is 1.00. So
 * does a profile that has not yet cleared the confidence gate.
 */
export function effectiveAdjustments(
  profile: PersonalizationProfile | null,
  enabled: boolean,
): Adjustments {
  const out = neutralAdjustments();
  if (!enabled || !profile || !isObservedConfident(profile)) return out;
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    out[dimension] = clampAdjustment(profile.dimensions[dimension]?.adjustment ?? 1);
  }
  return out;
}

/**
 * Declared x observed, per dimension, clamped to the same band. What the
 * member said matters sets the starting point; what their connections show
 * nudges it. Neither can push a dimension outside 0.70-1.30, and ranking only
 * ever uses the RELATIVE differences (ranking.ts), so the result stays
 * normalized however the two combine.
 */
export function combineAdjustments(declared: Adjustments, observed: Adjustments): Adjustments {
  const out = neutralAdjustments();
  for (const dimension of PERSONALIZATION_DIMENSIONS) {
    const d = Number.isFinite(declared[dimension]) ? declared[dimension] : ADJUSTMENT_BOUNDS.neutral;
    const o = Number.isFinite(observed[dimension]) ? observed[dimension] : ADJUSTMENT_BOUNDS.neutral;
    out[dimension] = clampAdjustment(d * o);
  }
  return out;
}
