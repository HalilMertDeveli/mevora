/** Canonical humor vector dimensions. Order is stable for scoring. */
export const HUMOR_CATEGORIES = [
  "sarcasm",
  "absurd",
  "silly",
  "romantic",
  "dark",
  "meme",
  "dry",
  "wordplay",
  "situational",
  "cringe",
  "teasing",
] as const;

export type HumorCategory = (typeof HUMOR_CATEGORIES)[number];
export type HumorVector = Record<HumorCategory, number>;

export function emptyHumorVector(fill = 0): HumorVector {
  const vector = {} as HumorVector;
  for (const dim of HUMOR_CATEGORIES) {
    vector[dim] = fill;
  }
  return vector;
}

export function clamp01(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.min(1, Math.max(0, value));
}

export function clamp100(value: number): number {
  if (!Number.isFinite(value)) {
    return 50;
  }
  return Math.min(100, Math.max(0, Math.round(value)));
}

/** Normalize / sanitize a partial vector to all dims in 0..1. */
export function normalizeHumorVector(
  input: Partial<HumorVector> | Record<string, number> | null | undefined,
  fill = 0,
): HumorVector {
  const out = emptyHumorVector(fill);
  if (!input) {
    return out;
  }
  for (const dim of HUMOR_CATEGORIES) {
    const raw = (input as Record<string, number>)[dim];
    if (typeof raw === "number") {
      out[dim] = clamp01(raw);
    }
  }
  return out;
}

/**
 * Clamp a profile dimension to 0..100 *without* rounding.
 *
 * The stored lifetime profile keeps full precision: rounding every update
 * swallows the small late-learning steps and biases the vector toward whole
 * numbers. `clamp100` (which rounds) stays for views and the callers that want
 * integer output.
 */
export function clampProfileValue(value: number): number {
  if (!Number.isFinite(value)) {
    return 50;
  }
  return Math.min(100, Math.max(0, value));
}

/** Like {@link normalizeProfileVector}, but keeps full precision. */
export function exactProfileVector(
  input: Partial<HumorVector> | Record<string, number> | null | undefined,
  fill = 50,
): HumorVector {
  const out = emptyHumorVector(fill);
  if (!input) {
    return out;
  }
  for (const dim of HUMOR_CATEGORIES) {
    const raw = (input as Record<string, number>)[dim];
    if (typeof raw === "number") {
      out[dim] = clampProfileValue(raw);
    }
  }
  return out;
}

/** Profile vectors live in 0..100. Rounded — for views and scoring inputs. */
export function normalizeProfileVector(
  input: Partial<HumorVector> | Record<string, number> | null | undefined,
  fill = 50,
): HumorVector {
  const out = emptyHumorVector(fill);
  if (!input) {
    return out;
  }
  for (const dim of HUMOR_CATEGORIES) {
    const raw = (input as Record<string, number>)[dim];
    if (typeof raw === "number") {
      out[dim] = clamp100(raw);
    }
  }
  return out;
}

export function isHumorCategory(value: string): value is HumorCategory {
  return (HUMOR_CATEGORIES as readonly string[]).includes(value);
}
