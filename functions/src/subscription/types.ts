/**
 * Canonical Premium subscription contract (P0).
 *
 * One model for every store. Google Play (P1) and Apple (P2) map their own
 * lifecycle onto these states; nothing store-specific belongs in here.
 *
 * Canonical document path: `users/{uid}/subscription/current`
 * Written by the Admin SDK only — see `firestore.rules`.
 */

/** Same vocabulary the Boost purchase pipeline already uses. */
export type StorePlatform = "ios" | "android";

export type StoreEnvironment = "production" | "sandbox";

/**
 * Shared lifecycle vocabulary.
 *
 * - `active`         paid and renewing (or a manual grant)
 * - `grace_period`   payment failed, store granted a grace window, access kept
 * - `billing_retry`  payment failed, store is retrying; access only while a
 *                    grace window is still open (Google account hold / Apple
 *                    billing retry without grace means no access)
 * - `cancelled`      auto-renew turned off; the paid period still runs out
 * - `expired`        the paid period ended
 * - `revoked`        entitlement withdrawn by the store or by support
 * - `refunded`       money returned; entitlement withdrawn immediately
 */
export type SubscriptionStatus =
  | "active"
  | "grace_period"
  | "billing_retry"
  | "expired"
  | "cancelled"
  | "revoked"
  | "refunded";

/** What the subscription grants, independent of the time window. */
export type EntitlementGrant = "premium" | "none";

/** Where the current state came from. */
export type EntitlementSource = "store" | "manual" | "legacy_claim";

/**
 * Canonical in-memory state. Dates are plain `Date`; the Firestore layer
 * converts to/from `Timestamp` at the boundary.
 */
export interface CanonicalSubscription {
  userId: string;
  platform: StorePlatform | null;
  productId: string | null;
  status: SubscriptionStatus;
  /**
   * Grant intent, not effective access. Effective access is always
   * `evaluatePremiumAccess(state, now)` — never this field on its own.
   */
  entitlement: EntitlementGrant;
  originalTransactionId: string | null;
  latestPurchaseId: string | null;
  expiresAt: Date | null;
  graceUntil: Date | null;
  autoRenewing: boolean;
  lastVerifiedAt: Date | null;
  storeEnvironment: StoreEnvironment | null;
  source: EntitlementSource;
  /**
   * Monotonic ordering guard. Stores hand out their own ordering hints
   * (Google `purchaseToken` revision, Apple `revision` / signed date); P1/P2
   * map them here so a re-delivered or out-of-order event cannot overwrite a
   * newer state.
   */
  revision: number;
  /** Store event time, used for ordering when `revision` is unavailable. */
  eventAt: Date | null;
  /** Derived mirror of effective access; kept for legacy readers. */
  isPremium: boolean;
}

/**
 * What a caller (P1 Google, P2 Apple, RTDN, ASSN V2, reconciliation, support
 * tooling) hands to the entitlement writer. Everything optional is left
 * unchanged when an existing document already carries a value.
 */
export interface EntitlementWriteInput {
  userId: string;
  status: SubscriptionStatus;
  entitlement?: EntitlementGrant;
  platform?: StorePlatform | null;
  productId?: string | null;
  originalTransactionId?: string | null;
  latestPurchaseId?: string | null;
  expiresAt?: Date | null;
  graceUntil?: Date | null;
  autoRenewing?: boolean;
  storeEnvironment?: StoreEnvironment | null;
  source?: EntitlementSource;
  revision?: number;
  eventAt?: Date | null;
  /** Verification timestamp; defaults to `now`. */
  verifiedAt?: Date | null;
}

export type EntitlementWriteOutcome =
  | "applied"
  | "noop"
  | "stale_revision"
  | "stale_event"
  | "terminal_state";

export interface EntitlementWriteResult {
  outcome: EntitlementWriteOutcome;
  /** True only when the document actually changed. */
  applied: boolean;
  state: CanonicalSubscription;
}

/** Why `evaluatePremiumAccess` decided the way it did. Log-friendly. */
export type PremiumAccessReason =
  | "no_subscription"
  | "invalid_state"
  | "entitlement_none"
  | "revoked"
  | "refunded"
  | "expired"
  | "active"
  | "grace"
  | "paid_period_remaining"
  | "no_deadline"
  | "legacy_claim";

export interface PremiumAccess {
  isPremium: boolean;
  reason: PremiumAccessReason;
  /** When access lapses if nothing renews it. */
  accessUntil: Date | null;
}
