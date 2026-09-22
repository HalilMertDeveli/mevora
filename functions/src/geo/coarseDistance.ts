/**
 * Distance disclosure policy.
 *
 * A user controls their own userLocation document, so any endpoint returning a
 * precise distance to a chosen target is a trilateration oracle: move, re-query,
 * intersect three circles, recover the target's coordinates. Resolution of the
 * returned number is what bounds that attack, so every distance leaving the
 * backend is quantised here before it is emitted.
 *
 * Filtering, ranking and radius logic keep using the exact haversine value
 * server-side. Only the disclosed value is coarsened.
 */

/** Width of a disclosed distance band, in km. */
export const DISTANCE_BUCKET_KM = 5;

/** Distances at or above this are disclosed as a single open-ended bucket. */
export const DISTANCE_MAX_DISCLOSED_KM = 100;

/**
 * Quantises an exact distance onto the disclosure ladder:
 *   < 1 km        -> 0   (rendered as "less than 1 km")
 *   1..100 km     -> floor to a 5 km band (5, 10, 15, ...)
 *   >= 100 km     -> 100 (rendered as "100+ km")
 *
 * Returns null for a missing/invalid input so callers can omit the field.
 */
export function coarseDistanceKm(km: unknown): number | null {
  // Number(null) and Number("") are 0, which would disclose "less than 1 km"
  // for a candidate whose distance is simply unknown.
  if (km === null || km === undefined || km === "") {
    return null;
  }
  const value = Number(km);
  if (!Number.isFinite(value) || value < 0) {
    return null;
  }
  if (value < 1) {
    return 0;
  }
  if (value >= DISTANCE_MAX_DISCLOSED_KM) {
    return DISTANCE_MAX_DISCLOSED_KM;
  }
  const bucket = Math.floor(value / DISTANCE_BUCKET_KM) * DISTANCE_BUCKET_KM;
  return bucket < DISTANCE_BUCKET_KM ? DISTANCE_BUCKET_KM : bucket;
}

/**
 * Localised label for an already-quantised distance. Keeps the existing copy
 * shape ("N km away") so no new localisation strings are needed; only the
 * numbers it can contain are coarser.
 */
export function coarseDistanceLabel(
  km: unknown,
  lang: "tr" | "en",
): {label: string; labelEn: string; bucketKm: number | null} {
  const bucketKm = coarseDistanceKm(km);
  if (bucketKm === null) {
    return {label: "", labelEn: "", bucketKm: null};
  }
  const labelEn =
    bucketKm === 0
      ? "Less than 1 km away"
      : bucketKm >= DISTANCE_MAX_DISCLOSED_KM
        ? "100+ km away"
        : `${bucketKm} km away`;
  const labelTr =
    bucketKm === 0
      ? "1 km'den yakın"
      : bucketKm >= DISTANCE_MAX_DISCLOSED_KM
        ? "100+ km uzakta"
        : `${bucketKm} km uzakta`;
  return {label: lang === "tr" ? labelTr : labelEn, labelEn, bucketKm};
}

/**
 * Authorization for distance disclosure.
 *
 * A caller may learn a distance only to somebody they are actually connected
 * to: an active match, not blocked in either direction. Kept here, free of
 * Firebase Admin side effects, so it is unit-testable without booting an app.
 */
export function distanceDisclosureDecision(options: {
  uid: string;
  otherUid: string;
  matchData: Record<string, unknown> | undefined;
  matchExists: boolean;
  blocked: boolean;
}): "allow" | "invalid-target" | "not-matched" | "blocked" {
  const {uid, otherUid, matchData, matchExists, blocked} = options;
  if (!otherUid || otherUid === uid) {
    return "invalid-target";
  }
  const userIds = (matchData?.userIds as string[] | undefined) ?? [];
  if (
    !matchExists ||
    matchData?.isActive !== true ||
    !userIds.includes(uid) ||
    !userIds.includes(otherUid)
  ) {
    return "not-matched";
  }
  if (blocked) {
    return "blocked";
  }
  return "allow";
}

export const DISTANCE_WINDOW_MS = 60 * 60 * 1000;
export const DISTANCE_MAX_PER_WINDOW = 60;

/**
 * Per-caller throttle for distance disclosure. Quantisation bounds what one
 * reading reveals; this bounds how many readings an attacker can stack up.
 * State lives under users/{uid}/rateLimits, which the Firestore rules deny to
 * every client (read, write: if false).
 */
export interface QuotaTransaction {
  // Method syntax (not arrow properties) so a real Firestore Transaction,
  // whose get/set are far more heavily overloaded, stays assignable.
  get(ref: never): Promise<{data(): Record<string, unknown> | undefined}>;
  set(ref: never, data: Record<string, unknown>): unknown;
}

export interface QuotaStore {
  doc(path: string): unknown;
  runTransaction<T>(fn: (tx: QuotaTransaction) => Promise<T>): Promise<T>;
}

export async function consumeDistanceQuota(
  database: QuotaStore,
  uid: string,
  now: number,
  serverTimestamp: unknown,
): Promise<"ok" | "rate-limited"> {
  const ref = database.doc(`users/${uid}/rateLimits/distanceLabel`) as never;
  return database.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() ?? {};
    const started = typeof data.windowStart === "number" ? data.windowStart : now;
    const count = typeof data.count === "number" ? data.count : 0;
    if (now - started > DISTANCE_WINDOW_MS) {
      tx.set(ref, {windowStart: now, count: 1, updatedAt: serverTimestamp});
      return "ok" as const;
    }
    if (count >= DISTANCE_MAX_PER_WINDOW) {
      return "rate-limited" as const;
    }
    tx.set(ref, {windowStart: started, count: count + 1, updatedAt: serverTimestamp});
    return "ok" as const;
  });
}
