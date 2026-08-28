/** Keys / patterns that must never appear in Why You Matched client payloads. */
export const FORBIDDEN_PAYLOAD_KEYS = new Set([
  "lat",
  "lng",
  "latitude",
  "longitude",
  "geohash",
  "coordinates",
  "location",
  "accessToken",
  "refreshToken",
  "spotifySecrets",
  "password",
  "phone",
  "email",
  "fcmToken",
  "birthDate",
  "answerId",
  "rawAnswers",
  "humorVector",
]);

const FORBIDDEN_NESTED = [
  "latitude",
  "longitude",
  "geohash",
  "accesstoken",
  "refreshtoken",
];

export function containsForbiddenKey(key: string): boolean {
  const lower = key.toLowerCase();
  if (FORBIDDEN_PAYLOAD_KEYS.has(key) || FORBIDDEN_PAYLOAD_KEYS.has(lower)) {
    return true;
  }
  return FORBIDDEN_NESTED.some((p) => lower.includes(p));
}

/**
 * Deep-sanitizes a plain object for client delivery.
 * Drops forbidden keys; caps string arrays; never invents fields.
 */
export function sanitizeForClient<T>(value: T, depth = 0): T {
  if (depth > 6) {
    return value;
  }
  if (Array.isArray(value)) {
    return value
      .slice(0, 12)
      .map((item) => sanitizeForClient(item, depth + 1)) as T;
  }
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      if (k.startsWith("_")) continue;
      if (containsForbiddenKey(k)) continue;
      out[k] = sanitizeForClient(v, depth + 1);
    }
    return out as T;
  }
  if (typeof value === "string") {
    return value.slice(0, 120) as T;
  }
  return value;
}

/** Returns only allow-listed request fields. */
export function pickRequestFields(data: unknown): {
  matchId: string;
  forceRefresh: boolean;
} {
  const raw = (data ?? {}) as Record<string, unknown>;
  return {
    matchId: String(raw.matchId ?? "").trim(),
    forceRefresh: raw.forceRefresh === true,
  };
}
