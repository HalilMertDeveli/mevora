import {evaluatePremiumAccess} from "./entitlementPolicy.js";
import type {
  CanonicalSubscription,
  EntitlementGrant,
  EntitlementWriteInput,
  EntitlementWriteResult,
  SubscriptionStatus,
} from "./types.js";

/**
 * Narrow persistence port. The Firestore implementation lives in
 * `firestoreEntitlementStore.ts`; tests inject an in-memory one.
 *
 * `transact` must read and write atomically so two concurrent store events
 * cannot interleave.
 */
export interface EntitlementPersistence {
  transact(
    userId: string,
    mutate: (
      current: CanonicalSubscription | null,
    ) => CanonicalSubscription | null,
  ): Promise<CanonicalSubscription>;
}

/** Statuses that still describe a live or recently-live paid period. */
const GRANTING_STATUSES: ReadonlySet<SubscriptionStatus> = new Set([
  "active",
  "grace_period",
  "billing_retry",
  "cancelled",
]);

/** Once here, only a strictly newer store event may move the state again. */
const TERMINAL_STATUSES: ReadonlySet<SubscriptionStatus> = new Set([
  "revoked",
  "refunded",
]);

export function defaultEntitlementFor(
  status: SubscriptionStatus,
): EntitlementGrant {
  return GRANTING_STATUSES.has(status) ? "premium" : "none";
}

function pick<T>(next: T | undefined, current: T, fallback: T): T {
  if (next !== undefined) {
    return next;
  }
  return current ?? fallback;
}

function emptyState(userId: string): CanonicalSubscription {
  return {
    userId,
    platform: null,
    productId: null,
    status: "expired",
    entitlement: "none",
    originalTransactionId: null,
    latestPurchaseId: null,
    expiresAt: null,
    graceUntil: null,
    autoRenewing: false,
    lastVerifiedAt: null,
    storeEnvironment: null,
    source: "store",
    revision: 0,
    eventAt: null,
    isPremium: false,
  };
}

/**
 * Applies `input` on top of `existing` and recomputes the derived mirror.
 * Pure — no clock reads beyond the supplied `now`.
 */
export function mergeEntitlement(
  existing: CanonicalSubscription | null,
  input: EntitlementWriteInput,
  now: Date,
): CanonicalSubscription {
  const base = existing ?? emptyState(input.userId);
  const merged: CanonicalSubscription = {
    userId: input.userId,
    platform: pick(input.platform, base.platform, null),
    productId: pick(input.productId, base.productId, null),
    status: input.status,
    entitlement: input.entitlement ?? defaultEntitlementFor(input.status),
    originalTransactionId: pick(
      input.originalTransactionId,
      base.originalTransactionId,
      null,
    ),
    latestPurchaseId: pick(
      input.latestPurchaseId,
      base.latestPurchaseId,
      null,
    ),
    expiresAt: pick(input.expiresAt, base.expiresAt, null),
    graceUntil: pick(input.graceUntil, base.graceUntil, null),
    autoRenewing: pick(input.autoRenewing, base.autoRenewing, false),
    lastVerifiedAt: input.verifiedAt === undefined ?
      now :
      input.verifiedAt,
    storeEnvironment: pick(
      input.storeEnvironment,
      base.storeEnvironment,
      null,
    ),
    source: input.source ?? base.source ?? "store",
    revision: input.revision ?? base.revision ?? 0,
    eventAt: pick(input.eventAt, base.eventAt, null),
    isPremium: false,
    purchaseTokenKey: pick(
      input.purchaseTokenKey,
      base.purchaseTokenKey ?? null,
      null,
    ),
  };
  merged.isPremium = evaluatePremiumAccess(merged, now).isPremium;
  return merged;
}

function dateKey(value: Date | null): number | null {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
    return null;
  }
  return value.getTime();
}

/** Every field that matters for equality. `lastVerifiedAt` is excluded. */
function materialFingerprint(state: CanonicalSubscription): string {
  return JSON.stringify([
    state.userId,
    state.platform,
    state.productId,
    state.status,
    state.entitlement,
    state.originalTransactionId,
    state.latestPurchaseId,
    dateKey(state.expiresAt),
    dateKey(state.graceUntil),
    state.autoRenewing,
    state.storeEnvironment,
    state.source,
    state.revision,
    dateKey(state.eventAt),
    state.isPremium,
    state.purchaseTokenKey ?? null,
  ]);
}

/**
 * True when `input` is provably older than what is already stored.
 *
 * `revision` wins when both sides carry one; otherwise `eventAt` decides.
 * Equal revisions fall through so a legitimate correction carrying the same
 * revision is still evaluated by the idempotency check.
 */
function isStrictlyNewer(
  existing: CanonicalSubscription,
  input: EntitlementWriteInput,
): boolean {
  if (typeof input.revision === "number" && existing.revision > 0) {
    if (input.revision !== existing.revision) {
      return input.revision > existing.revision;
    }
  }
  const incomingAt = dateKey(input.eventAt ?? null);
  const existingAt = dateKey(existing.eventAt);
  if (incomingAt !== null && existingAt !== null) {
    return incomingAt > existingAt;
  }
  return false;
}

/**
 * True when `input` comes from a purchase token other than the one the stored
 * entitlement rests on, and would take away access that token still grants.
 *
 * The document is per user, so a user's older token reports into the same
 * place as their current one. After an upgrade Google expires the replaced
 * token; without this, that expiry — a newer event, so ordering lets it
 * through — would overwrite the live subscription with `expired`.
 *
 * Deliberately narrow. A foreign token that *grants* is applied (a new
 * purchase takes the entitlement over), the successor in an upgrade chain is
 * never foreign, and once the stored state has stopped granting on its own
 * there is nothing left to protect.
 */
function isLapseFromSupersededToken(
  existing: CanonicalSubscription,
  input: EntitlementWriteInput,
  next: CanonicalSubscription,
  now: Date,
): boolean {
  const restsOn = existing.purchaseTokenKey ?? null;
  const incoming = input.purchaseTokenKey ?? null;
  if (!restsOn || !incoming || restsOn === incoming) {
    return false;
  }
  if (input.supersedesTokenKey === restsOn) {
    return false;
  }
  return !next.isPremium && evaluatePremiumAccess(existing, now).isPremium;
}

/**
 * Pure decision: what the store should end up holding, and why.
 * The writer runs this inside the transaction.
 */
export function decideWrite(
  existing: CanonicalSubscription | null,
  input: EntitlementWriteInput,
  now: Date,
): EntitlementWriteResult {
  const next = mergeEntitlement(existing, input, now);
  if (!existing) {
    return {outcome: "applied", applied: true, state: next};
  }

  if (
    typeof input.revision === "number" &&
    existing.revision > 0 &&
    input.revision < existing.revision
  ) {
    return {outcome: "stale_revision", applied: false, state: existing};
  }

  const incomingAt = dateKey(input.eventAt ?? null);
  const existingAt = dateKey(existing.eventAt);
  if (incomingAt !== null && existingAt !== null && incomingAt < existingAt) {
    return {outcome: "stale_event", applied: false, state: existing};
  }

  // A refund or revocation only steps aside for a provably newer event.
  if (
    TERMINAL_STATUSES.has(existing.status) &&
    !TERMINAL_STATUSES.has(input.status) &&
    !isStrictlyNewer(existing, input)
  ) {
    return {outcome: "terminal_state", applied: false, state: existing};
  }

  if (isLapseFromSupersededToken(existing, input, next, now)) {
    return {outcome: "superseded_token", applied: false, state: existing};
  }

  if (materialFingerprint(existing) === materialFingerprint(next)) {
    return {outcome: "noop", applied: false, state: existing};
  }

  return {outcome: "applied", applied: true, state: next};
}

/**
 * The one server-side entitlement writer.
 *
 * Every future entitlement source goes through here: Google Play verification
 * and RTDN (P1), Apple verification and ASSN V2 (P2), restore flows (P3) and
 * reconciliation jobs. Idempotent, ordering-aware and server-only — clients
 * cannot reach it, and `firestore.rules` blocks the document outright.
 */
export class SubscriptionEntitlementWriter {
  constructor(
    private readonly persistence: EntitlementPersistence,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async apply(input: EntitlementWriteInput): Promise<EntitlementWriteResult> {
    if (!input.userId) {
      throw new Error("entitlement-writer: userId is required");
    }
    const now = this.clock();
    const holder: {decision?: EntitlementWriteResult} = {};
    const stored = await this.persistence.transact(input.userId, (current) => {
      const decision = decideWrite(current, input, now);
      holder.decision = decision;
      return decision.applied ? decision.state : null;
    });
    const decision = holder.decision;
    if (!decision) {
      throw new Error("entitlement-writer: transaction did not run");
    }
    return {...decision, state: stored};
  }
}
