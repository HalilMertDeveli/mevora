/**
 * Google Play Real-time Developer Notifications.
 *
 * A notification is a nudge, not a fact. Play delivers at least once, out of
 * order, and sometimes for a token that has already been superseded, so the
 * notification *type* is never written as state. Every message resolves to the
 * same question — what does `subscriptionsv2.get` say about this token right
 * now — and that answer goes through the one entitlement writer, which already
 * knows how to reject a stale or out-of-order write.
 *
 * This is what keeps a renewal, a cancellation, an expiry or a refund that
 * happens entirely inside the store from being invisible to Mevora.
 */
import {logger} from "firebase-functions";
import {mapGoogleSubscription} from "./googleSubscriptionMapper.js";
import {
  type GoogleSubscriptionApi,
} from "./googleSubscriptionVerifier.js";
import {premiumCatalogue} from "./productCatalog.js";
import {SubscriptionEntitlementWriter} from "./entitlementWriter.js";
import type {EntitlementPersistence} from "./entitlementWriter.js";
import {PurchaseOwnershipConflict} from "./premiumPurchaseStore.js";
import {tokenIdentity} from "./purchaseOwnership.js";

/** Shape Play puts in the Pub/Sub message payload. */
export interface DeveloperNotification {
  version?: string;
  packageName?: string;
  eventTimeMillis?: string | number;
  subscriptionNotification?: {
    version?: string;
    notificationType?: number;
    purchaseToken?: string;
    subscriptionId?: string;
  };
  /** A one-time product — Boost. Handled by `boost/boostRtdn.ts`, never here. */
  oneTimeProductNotification?: {
    version?: string;
    notificationType?: number;
    purchaseToken?: string;
    sku?: string;
  };
  voidedPurchaseNotification?: {
    purchaseToken?: string;
    orderId?: string;
    productType?: number;
    refundType?: number;
  };
  testNotification?: {version?: string};
}

export type RtdnOutcome =
  /** Entitlement was recomputed from the store and handed to the writer. */
  | "applied"
  /** A valid message with nothing to do — a test ping, or an unknown shape. */
  | "ignored"
  /** Not ours, or not parseable. Acknowledged so Play stops retrying. */
  | "rejected"
  /** Nobody has claimed this token yet, so there is no user to write to. */
  | "unattributed"
  /**
   * The store could not be asked — it is failing, or Mevora's credential for
   * it is missing or not authorised. The message should be retried.
   */
  | "retry";

export interface RtdnResult {
  outcome: RtdnOutcome;
  reason?: string;
}

/** Decodes the base64 payload Pub/Sub carries, tolerating anything. */
export function decodeNotification(data: string): DeveloperNotification | null {
  try {
    const json = Buffer.from(data, "base64").toString("utf8");
    const parsed: unknown = JSON.parse(json);
    if (!parsed || typeof parsed !== "object") {
      return null;
    }
    return parsed as DeveloperNotification;
  } catch {
    return null;
  }
}

/**
 * Picks the token this message is about.
 *
 * A voided purchase carries its own token and no subscription block; treating
 * both the same way means a refund follows exactly the path a renewal does,
 * and the store's own state decides what that means.
 */
export function tokenOf(notification: DeveloperNotification): string | null {
  const subscription = notification.subscriptionNotification?.purchaseToken;
  if (typeof subscription === "string" && subscription.length > 0) {
    return subscription;
  }
  const voided = notification.voidedPurchaseNotification?.purchaseToken;
  if (typeof voided === "string" && voided.length > 0) {
    return voided;
  }
  return null;
}

function eventTimeOf(notification: DeveloperNotification, fallback: Date): Date {
  const raw = notification.eventTimeMillis;
  const millis = typeof raw === "string" ? Number(raw) : raw;
  if (typeof millis !== "number" || !Number.isFinite(millis) || millis <= 0) {
    return fallback;
  }
  return new Date(millis);
}

/**
 * How long a message keeps being retried. Redelivery is requested by
 * throwing, so without an end a message that can never succeed would be
 * retried for as long as Pub/Sub keeps it.
 */
export const RTDN_MAX_RETRY_AGE_MS = 24 * 60 * 60 * 1000;

/**
 * True once a message is older than the retry window. An unreadable time is
 * treated as fresh: the first delivery must never be dropped for it, and
 * Pub/Sub's own retention still bounds the retries.
 */
export function isTooOldToRetry(
  publishedAt: string | undefined,
  now: Date,
): boolean {
  const published = Date.parse(publishedAt ?? "");
  if (!Number.isFinite(published)) {
    return false;
  }
  return now.getTime() - published > RTDN_MAX_RETRY_AGE_MS;
}

/**
 * Resolves which Mevora account a purchase token belongs to.
 *
 * RTDN arrives with no user on it — Play knows a token, not a Mevora uid. The
 * ownership ledger written during verification is the only link, which is also
 * why an unclaimed token is dropped rather than guessed at.
 */
export interface OwnerLookup {
  findOwner(purchaseToken: string): Promise<string | null>;
}

export async function handleDeveloperNotification(input: {
  notification: DeveloperNotification;
  api: GoogleSubscriptionApi;
  owners: OwnerLookup;
  persistenceFor: (args: {
    userId: string;
    purchaseToken: string;
    productId: string;
    linkedPurchaseToken: string | null;
  }) => EntitlementPersistence;
  now?: Date;
}): Promise<RtdnResult> {
  const now = input.now ?? new Date();
  const notification = input.notification;
  const catalogue = premiumCatalogue();

  if (!catalogue.androidPackageName || catalogue.android.length === 0) {
    // Nothing is configured, so nothing this message says can grant anything.
    return {outcome: "rejected", reason: "not_configured"};
  }

  // A message for another app must never reach this app's entitlement.
  if (notification.packageName !== catalogue.androidPackageName) {
    return {outcome: "rejected", reason: "wrong_package"};
  }

  if (notification.testNotification) {
    return {outcome: "ignored", reason: "test_notification"};
  }

  const purchaseToken = tokenOf(notification);
  if (!purchaseToken) {
    return {outcome: "ignored", reason: "no_token"};
  }

  const userId = await input.owners.findOwner(purchaseToken);
  if (!userId) {
    // Bought outside Mevora, or verification has not run yet. The client's
    // next verifyPremiumPurchase claims the token and writes the state, so
    // dropping this is not a lost entitlement.
    return {outcome: "unattributed", reason: "no_owner"};
  }

  const verified = await input.api.fetchSubscription({
    packageName: catalogue.androidPackageName,
    purchaseToken,
  });
  if (!verified.ok) {
    if (verified.error === "transient") {
      // Ask Pub/Sub to redeliver rather than tearing down a live entitlement
      // because Google was briefly unavailable.
      return {outcome: "retry", reason: "store_unavailable"};
    }
    if (verified.error === "unavailable") {
      // Mevora's credential, not the purchase. Acknowledging here would lose
      // a renewal or a refund for good while the credential is being fixed.
      return {outcome: "retry", reason: "store_credentials_unavailable"};
    }
    return {outcome: "rejected", reason: verified.error};
  }

  const mapped = mapGoogleSubscription({
    userId,
    packageName: catalogue.androidPackageName,
    purchase: verified.purchase,
    // Ordering key. The writer uses it to discard a message that overtook a
    // newer one in delivery.
    eventAt: eventTimeOf(notification, now),
  });
  if (!mapped.ok) {
    return {outcome: "rejected", reason: mapped.reason};
  }

  const persistence = input.persistenceFor({
    userId,
    purchaseToken,
    productId: mapped.write.productId ?? "",
    linkedPurchaseToken: mapped.linkedPurchaseToken,
  });
  const writer = new SubscriptionEntitlementWriter(persistence, () => now);
  let result;
  try {
    result = await writer.apply({
      ...mapped.write,
      ...tokenIdentity(purchaseToken, mapped.linkedPurchaseToken),
    });
  } catch (error) {
    if (error instanceof PurchaseOwnershipConflict) {
      // Permanent: redelivery cannot change who owns a token.
      return {outcome: "rejected", reason: "owned_by_other"};
    }
    throw error;
  }

  logger.info("premium: rtdn applied", {
    outcome: result.outcome,
    status: mapped.write.status,
  });
  return {outcome: "applied", reason: result.outcome};
}
