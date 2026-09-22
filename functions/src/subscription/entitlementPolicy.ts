import type {
  CanonicalSubscription,
  PremiumAccess,
  SubscriptionStatus,
} from "./types.js";

const FREE: PremiumAccess = {
  isPremium: false,
  reason: "no_subscription",
  accessUntil: null,
};

const VALID_STATUSES: ReadonlySet<string> = new Set<SubscriptionStatus>([
  "active",
  "grace_period",
  "billing_retry",
  "expired",
  "cancelled",
  "paused",
  "pending",
  "revoked",
  "refunded",
]);

function isUsableDate(value: Date | null | undefined): value is Date {
  return value instanceof Date && Number.isFinite(value.getTime());
}

/** Latest of the supplied deadlines, ignoring nulls and invalid dates. */
function latest(...dates: Array<Date | null | undefined>): Date | null {
  let best: Date | null = null;
  for (const date of dates) {
    if (!isUsableDate(date)) {
      continue;
    }
    if (best === null || date.getTime() > best.getTime()) {
      best = date;
    }
  }
  return best;
}

/**
 * The single place that turns canonical subscription state into effective
 * Premium access. Backend and client must agree on this policy.
 *
 * Deliberate semantics:
 * - `cancelled` does NOT cut access off. Auto-renew is off, but the paid
 *   period the user already bought runs to `expiresAt`.
 * - `revoked` / `refunded` cut access off immediately, whatever `expiresAt`
 *   says — the money is gone or the grant was withdrawn.
 * - `grace_period` / `billing_retry` grant access only while a store-granted
 *   window is still open. Google account hold and Apple billing retry without
 *   a grace window therefore resolve to no access, which is correct.
 * - `paused` / `pending` never grant access, and unlike every other denial
 *   they are decided before any deadline is consulted. A paused plan can still
 *   carry a future `expiresAt`, and a pending one can carry a stale
 *   `isPremium: true` mirror; neither may leak access.
 * - Missing or unparseable state always fails safe to free.
 */
export function evaluatePremiumAccess(
  state: CanonicalSubscription | null | undefined,
  now: Date,
): PremiumAccess {
  if (!state) {
    return FREE;
  }
  if (!VALID_STATUSES.has(state.status)) {
    return {isPremium: false, reason: "invalid_state", accessUntil: null};
  }
  if (state.status === "revoked") {
    return {isPremium: false, reason: "revoked", accessUntil: null};
  }
  if (state.status === "refunded") {
    return {isPremium: false, reason: "refunded", accessUntil: null};
  }
  // Checked before the grant so a lapsed subscription reports why it lapsed
  // rather than the `entitlement: "none"` that lapsing already set.
  if (state.status === "expired") {
    return {isPremium: false, reason: "expired", accessUntil: null};
  }
  // Ahead of every deadline and grant check: a paused plan keeps a future
  // `expiresAt` and a pending one may carry a legacy `isPremium` mirror, so
  // anything that consults those fields would wrongly grant access here.
  if (state.status === "paused") {
    return {isPremium: false, reason: "paused", accessUntil: null};
  }
  if (state.status === "pending") {
    return {isPremium: false, reason: "pending", accessUntil: null};
  }
  if (state.entitlement !== "premium") {
    return {isPremium: false, reason: "entitlement_none", accessUntil: null};
  }

  const nowMs = now.getTime();

  if (state.status === "cancelled") {
    // Auto-renew off; honour the remaining paid period only.
    const until = isUsableDate(state.expiresAt) ? state.expiresAt : null;
    if (until === null) {
      return {isPremium: false, reason: "no_deadline", accessUntil: null};
    }
    return until.getTime() > nowMs
      ? {isPremium: true, reason: "paid_period_remaining", accessUntil: until}
      : {isPremium: false, reason: "expired", accessUntil: until};
  }

  if (state.status === "grace_period" || state.status === "billing_retry") {
    const until = latest(state.graceUntil, state.expiresAt);
    if (until === null) {
      return {isPremium: false, reason: "no_deadline", accessUntil: null};
    }
    return until.getTime() > nowMs
      ? {isPremium: true, reason: "grace", accessUntil: until}
      : {isPremium: false, reason: "expired", accessUntil: until};
  }

  // status === "active"
  const until = latest(state.expiresAt, state.graceUntil);
  if (until === null) {
    // Manual / lifetime grants carry no expiry and stay active until revoked.
    return {isPremium: true, reason: "active", accessUntil: null};
  }
  return until.getTime() > nowMs
    ? {isPremium: true, reason: "active", accessUntil: until}
    : {isPremium: false, reason: "expired", accessUntil: until};
}
