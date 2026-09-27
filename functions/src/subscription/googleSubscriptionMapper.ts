/**
 * Maps a Google Play `SubscriptionPurchaseV2` onto the canonical subscription
 * contract.
 *
 * Kept free of network and Firestore so the whole mapping — including every
 * lifecycle state and the fail-closed paths — is testable directly.
 *
 * Contract reference: purchases.subscriptionsv2.get
 * https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2
 */
import type {
  EntitlementWriteInput,
  StoreEnvironment,
  SubscriptionStatus,
} from "./types.js";
import {resolveAndroidProduct, type PremiumCatalogue} from "./productCatalog.js";

/** The subset of SubscriptionPurchaseV2 this mapper reads. */
export interface GoogleSubscriptionPurchase {
  subscriptionState?: string;
  linkedPurchaseToken?: string | null;
  latestOrderId?: string | null;
  acknowledgementState?: string | null;
  testPurchase?: unknown;
  regionCode?: string | null;
  startTime?: string | null;
  externalAccountIdentifiers?: {
    obfuscatedExternalAccountId?: string | null;
    externalAccountId?: string | null;
  } | null;
  lineItems?: Array<{
    productId?: string | null;
    expiryTime?: string | null;
    latestSuccessfulOrderId?: string | null;
    autoRenewingPlan?: {autoRenewEnabled?: boolean | null} | null;
    prepaidPlan?: unknown;
    offerDetails?: {basePlanId?: string | null; offerId?: string | null} | null;
  }> | null;
}

/**
 * Google's lifecycle mapped onto ours.
 *
 * `ON_HOLD` becomes `billing_retry` rather than `expired`: Google is still
 * retrying payment and the plan can recover. The entitlement policy already
 * refuses access for a retry with no open grace window, which is the correct
 * Google account-hold behaviour, so no access leaks by calling it retry.
 *
 * `PENDING_PURCHASE_CANCELED` becomes `expired`, not `cancelled`: nothing was
 * ever paid for, so there is no paid period left to honour.
 */
const STATE_MAP: Readonly<Record<string, SubscriptionStatus>> = {
  SUBSCRIPTION_STATE_ACTIVE: "active",
  SUBSCRIPTION_STATE_CANCELED: "cancelled",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD: "grace_period",
  SUBSCRIPTION_STATE_ON_HOLD: "billing_retry",
  SUBSCRIPTION_STATE_PAUSED: "paused",
  SUBSCRIPTION_STATE_PENDING: "pending",
  SUBSCRIPTION_STATE_EXPIRED: "expired",
  SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED: "expired",
};

export type GoogleMapRejection =
  | "unknown_state"
  | "no_line_item"
  | "not_configured"
  | "package_mismatch"
  | "unknown_product"
  | "unknown_base_plan";

export type GoogleMapResult =
  | {
      ok: true;
      write: EntitlementWriteInput;
      /** Carried out so the caller can chain-guard superseded tokens. */
      linkedPurchaseToken: string | null;
      acknowledged: boolean;
      obfuscatedExternalAccountId: string | null;
    }
  | {ok: false; reason: GoogleMapRejection};

function parseDate(value: string | null | undefined): Date | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

/** Latest expiry across line items; a multi-item plan lapses with its last. */
function latestExpiry(purchase: GoogleSubscriptionPurchase): Date | null {
  let best: Date | null = null;
  for (const item of purchase.lineItems ?? []) {
    const expiry = parseDate(item?.expiryTime);
    if (expiry && (best === null || expiry.getTime() > best.getTime())) {
      best = expiry;
    }
  }
  return best;
}

/**
 * Turns verified Google state into a canonical write.
 *
 * Every rejection path leaves the caller with nothing to write, which is what
 * keeps an unrecognised or unconfigured purchase from granting Premium.
 */
export function mapGoogleSubscription(input: {
  userId: string;
  packageName: string;
  purchase: GoogleSubscriptionPurchase;
  /** When the notification/verification happened, for write ordering. */
  eventAt: Date;
  catalogue?: PremiumCatalogue;
}): GoogleMapResult {
  const {userId, packageName, purchase, eventAt} = input;

  const rawState = String(purchase.subscriptionState ?? "");
  const status = STATE_MAP[rawState];
  if (!status) {
    // Includes SUBSCRIPTION_STATE_UNSPECIFIED and anything Google adds later.
    return {ok: false, reason: "unknown_state"};
  }

  // The line item carries the product identity; without one there is nothing
  // to check against the catalogue, so nothing may be granted.
  const lineItem = (purchase.lineItems ?? []).find(
    (item) => typeof item?.productId === "string" && item.productId.length > 0,
  );
  if (!lineItem) {
    return {ok: false, reason: "no_line_item"};
  }

  const productId = String(lineItem.productId);
  const basePlanId = lineItem.offerDetails?.basePlanId ?? null;
  const lookup = resolveAndroidProduct(
    {packageName, productId, basePlanId},
    input.catalogue,
  );
  if (!lookup.ok) {
    return {ok: false, reason: lookup.reason};
  }

  const expiresAt = latestExpiry(purchase);
  const autoRenewing = lineItem.autoRenewingPlan?.autoRenewEnabled === true;
  const environment: StoreEnvironment =
    purchase.testPurchase != null ? "sandbox" : "production";

  // The policy decides access from status plus deadlines; the grant only says
  // what the product would give while the window is open.
  const grantingStatuses: ReadonlySet<SubscriptionStatus> = new Set([
    "active",
    "cancelled",
    "grace_period",
    "billing_retry",
  ]);

  return {
    ok: true,
    linkedPurchaseToken: purchase.linkedPurchaseToken ?? null,
    acknowledged:
      String(purchase.acknowledgementState ?? "") ===
      "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
    obfuscatedExternalAccountId:
      purchase.externalAccountIdentifiers?.obfuscatedExternalAccountId ?? null,
    write: {
      userId,
      status,
      entitlement: grantingStatuses.has(status) ? "premium" : "none",
      platform: "android",
      productId,
      // Google rotates order ids per renewal, so the original purchase is
      // identified by its token, not by an order id.
      latestPurchaseId:
        lineItem.latestSuccessfulOrderId ?? purchase.latestOrderId ?? null,
      expiresAt,
      // Google exposes no separate grace deadline; the grace window ends at
      // the line item expiry it already extended.
      graceUntil: status === "grace_period" ? expiresAt : null,
      autoRenewing,
      storeEnvironment: environment,
      source: "store",
      eventAt,
      verifiedAt: eventAt,
    },
  };
}
