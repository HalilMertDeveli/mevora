/**
 * Turns App Store subscription state into a canonical entitlement write.
 *
 * Deliberately the same shape as the Google mapper: both produce an
 * `EntitlementWriteInput` for the one writer, so Apple gets no separate notion
 * of what Premium means. Every rejection path returns nothing to write, which
 * is what keeps an unrecognised or unconfigured purchase from granting access.
 */
import type {EntitlementWriteInput, SubscriptionStatus} from "./types.js";
import {premiumCatalogue, resolveIosProduct} from "./productCatalog.js";
import type {PremiumCatalogue} from "./productCatalog.js";

/**
 * `status` from `GET /inApps/v1/subscriptions/{transactionId}`.
 *
 * Apple numbers these; the names are ours. Anything outside this map — a value
 * Apple adds later — is unknown, and unknown fails closed.
 */
const STATUS_MAP: Readonly<Record<number, SubscriptionStatus>> = {
  1: "active",
  2: "expired",
  3: "billing_retry",
  4: "grace_period",
  5: "revoked",
};

/** Decoded `signedTransactionInfo`. */
export interface AppleTransactionInfo {
  bundleId?: string | null;
  productId?: string | null;
  originalTransactionId?: string | null;
  transactionId?: string | null;
  /** Milliseconds. Apple sets this only on a refund or revocation. */
  revocationDate?: number | string | null;
  revocationReason?: number | null;
  environment?: string | null;
}

/** Decoded `signedRenewalInfo`. */
export interface AppleRenewalInfo {
  autoRenewStatus?: number | null;
  autoRenewProductId?: string | null;
  /** Milliseconds. Present while Apple is still retrying payment. */
  gracePeriodExpiresDate?: number | string | null;
  expirationIntent?: number | null;
  environment?: string | null;
}

export interface AppleSubscriptionState {
  /** Apple's numeric subscription status. */
  status?: number | null;
  /** Milliseconds. When the paid period ends. */
  expiresDate?: number | string | null;
  transaction: AppleTransactionInfo;
  renewal: AppleRenewalInfo;
}

export type AppleMapRejection =
  | "unknown_state"
  | "no_product"
  | "not_configured"
  | "wrong_bundle"
  | "unknown_product";

export type AppleMapResult =
  | {ok: false; reason: AppleMapRejection}
  | {
      ok: true;
      write: EntitlementWriteInput;
      originalTransactionId: string | null;
    };

function millis(value: number | string | null | undefined): Date | null {
  if (value === null || value === undefined) {
    return null;
  }
  const parsed = typeof value === "string" ? Number(value) : value;
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return null;
  }
  return new Date(parsed);
}

export function mapAppleSubscription(input: {
  userId: string;
  state: AppleSubscriptionState;
  /** When the verification or notification happened, for write ordering. */
  eventAt: Date;
  catalogue?: PremiumCatalogue;
}): AppleMapResult {
  const {userId, state, eventAt} = input;
  const catalogue = input.catalogue ?? premiumCatalogue();

  if (!catalogue.iosBundleId || catalogue.ios.length === 0) {
    return {ok: false, reason: "not_configured"};
  }

  const bundleId = state.transaction.bundleId ?? null;
  if (bundleId && bundleId !== catalogue.iosBundleId) {
    // A transaction from another app must never reach this app's entitlement.
    return {ok: false, reason: "wrong_bundle"};
  }

  const productId = state.transaction.productId ?? null;
  if (!productId) {
    return {ok: false, reason: "no_product"};
  }
  const product = resolveIosProduct(
    {bundleId: catalogue.iosBundleId, productId},
    catalogue,
  );
  if (!product.ok) {
    // A Boost SKU, or anything else Apple sold that Premium does not include.
    return {ok: false, reason: "unknown_product"};
  }

  const rawStatus = state.status;
  const mapped =
    typeof rawStatus === "number" ? STATUS_MAP[rawStatus] : undefined;
  if (!mapped) {
    return {ok: false, reason: "unknown_state"};
  }

  const expiresAt = millis(state.expiresDate);
  const revokedAt = millis(state.transaction.revocationDate);
  const autoRenewing = state.renewal.autoRenewStatus === 1;

  // A revocation date is Apple saying this purchase was taken back, whatever
  // the status field happens to read. Refund and revoke both land here; the
  // reason distinguishes them, and both end access immediately.
  let status: SubscriptionStatus = mapped;
  if (revokedAt) {
    status = state.transaction.revocationReason === 1 ? "refunded" : "revoked";
  } else if (status === "active" && !autoRenewing) {
    // Still paid up, but it will not renew. `cancelled` is what the policy
    // reads to keep access until the period actually runs out.
    status = "cancelled";
  }

  const grantingStatuses = new Set<SubscriptionStatus>([
    "active",
    "cancelled",
    "grace_period",
    "billing_retry",
  ]);

  const graceUntil =
    status === "grace_period"
      ? millis(state.renewal.gracePeriodExpiresDate) ?? expiresAt
      : null;

  const environment =
    (state.transaction.environment ?? state.renewal.environment ?? "")
      .toString()
      .toLowerCase() === "sandbox"
      ? "sandbox"
      : "production";

  return {
    ok: true,
    originalTransactionId: state.transaction.originalTransactionId ?? null,
    write: {
      userId,
      status,
      entitlement: grantingStatuses.has(status) ? "premium" : "none",
      platform: "ios",
      productId,
      // Apple issues a new transaction id per renewal, so the subscription is
      // identified by its original transaction, not by the latest one.
      latestPurchaseId: state.transaction.transactionId ?? null,
      expiresAt,
      graceUntil,
      autoRenewing,
      storeEnvironment: environment,
      source: "store",
      eventAt,
      verifiedAt: eventAt,
    },
  };
}
