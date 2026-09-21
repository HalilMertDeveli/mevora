import {Timestamp, getFirestore} from "firebase-admin/firestore";
import type {DocumentData} from "firebase-admin/firestore";
import type {EntitlementPersistence} from "./entitlementWriter.js";
import type {
  CanonicalSubscription,
  EntitlementGrant,
  EntitlementSource,
  StoreEnvironment,
  StorePlatform,
  SubscriptionStatus,
} from "./types.js";

/** Canonical document path. Admin SDK only — see `firestore.rules`. */
export function subscriptionDocPath(userId: string): string {
  return `users/${userId}/subscription/current`;
}

const STATUSES: ReadonlySet<string> = new Set<SubscriptionStatus>([
  "active",
  "grace_period",
  "billing_retry",
  "expired",
  "cancelled",
  "revoked",
  "refunded",
]);

function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date && Number.isFinite(value.getTime())) {
    return value;
  }
  return null;
}

function toTimestamp(value: Date | null): Timestamp | null {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) {
    return null;
  }
  return Timestamp.fromDate(value);
}

function toPlatform(value: unknown): StorePlatform | null {
  return value === "ios" || value === "android" ? value : null;
}

function toEnvironment(value: unknown): StoreEnvironment | null {
  return value === "production" || value === "sandbox" ? value : null;
}

function toSource(value: unknown): EntitlementSource {
  return value === "manual" || value === "legacy_claim" || value === "store" ?
    value :
    "store";
}

function toGrant(value: unknown): EntitlementGrant {
  return value === "premium" ? "premium" : "none";
}

function toText(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * Reads a stored document into canonical state.
 *
 * Backward compatibility: documents written before P0 only carry `isPremium`
 * and an optional `expiresAt`. Those are mapped onto `active` / `expired` so
 * existing paying users keep their access without a migration pass.
 * Anything unrecognisable fails safe to a non-granting state.
 */
export function fromDocument(
  userId: string,
  data: DocumentData | undefined,
): CanonicalSubscription | null {
  if (!data) {
    return null;
  }
  const expiresAt = toDate(data.expiresAt);
  const rawStatus = typeof data.status === "string" ? data.status : null;
  const legacy = rawStatus === null || !STATUSES.has(rawStatus);

  let status: SubscriptionStatus;
  let entitlement: EntitlementGrant;
  if (legacy) {
    const legacyPremium = data.isPremium === true;
    status = legacyPremium ? "active" : "expired";
    entitlement = legacyPremium ? "premium" : "none";
  } else {
    status = rawStatus as SubscriptionStatus;
    entitlement = toGrant(data.entitlement ?? (data.isPremium === true ? "premium" : "none"));
  }

  return {
    userId,
    platform: toPlatform(data.platform),
    productId: toText(data.productId),
    status,
    entitlement,
    originalTransactionId: toText(data.originalTransactionId),
    latestPurchaseId: toText(data.latestPurchaseId),
    expiresAt,
    graceUntil: toDate(data.graceUntil),
    autoRenewing: data.autoRenewing === true,
    lastVerifiedAt: toDate(data.lastVerifiedAt),
    storeEnvironment: toEnvironment(data.storeEnvironment),
    source: legacy ? "legacy_claim" : toSource(data.source),
    revision: typeof data.revision === "number" && Number.isFinite(data.revision) ?
      data.revision :
      0,
    eventAt: toDate(data.eventAt),
    isPremium: data.isPremium === true,
  };
}

/**
 * Canonical state plus the derived `isPremium` mirror legacy readers use.
 * Both are always written together, so they cannot drift apart.
 */
export function toDocument(state: CanonicalSubscription): DocumentData {
  return {
    userId: state.userId,
    platform: state.platform,
    productId: state.productId,
    status: state.status,
    entitlement: state.entitlement,
    originalTransactionId: state.originalTransactionId,
    latestPurchaseId: state.latestPurchaseId,
    expiresAt: toTimestamp(state.expiresAt),
    graceUntil: toTimestamp(state.graceUntil),
    autoRenewing: state.autoRenewing,
    lastVerifiedAt: toTimestamp(state.lastVerifiedAt),
    storeEnvironment: state.storeEnvironment,
    source: state.source,
    revision: state.revision,
    eventAt: toTimestamp(state.eventAt),
    isPremium: state.isPremium,
    updatedAt: Timestamp.now(),
  };
}

/** Transactional Firestore implementation of the writer's persistence port. */
export class FirestoreEntitlementStore implements EntitlementPersistence {
  async transact(
    userId: string,
    mutate: (
      current: CanonicalSubscription | null,
    ) => CanonicalSubscription | null,
  ): Promise<CanonicalSubscription> {
    const db = getFirestore();
    const ref = db.doc(subscriptionDocPath(userId));
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current = fromDocument(userId, snap.data());
      const next = mutate(current);
      if (next === null) {
        if (current === null) {
          throw new Error("entitlement-store: nothing to write and nothing stored");
        }
        return current;
      }
      tx.set(ref, toDocument(next), {merge: true});
      return next;
    });
  }
}

/** Reads canonical state without a transaction. */
export async function readCanonicalSubscription(
  userId: string,
): Promise<CanonicalSubscription | null> {
  const snap = await getFirestore().doc(subscriptionDocPath(userId)).get();
  if (!snap.exists) {
    return null;
  }
  return fromDocument(userId, snap.data());
}
