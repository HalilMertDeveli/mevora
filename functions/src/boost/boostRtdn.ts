/**
 * Google Play notifications about one-time purchases — Boost.
 *
 * Boost shares the RTDN topic with Premium. This picks out the messages that
 * are about a one-time purchase and answers them; everything else comes back
 * as `null` for the subscription handler.
 *
 * It does not depend on the Premium catalogue: Boost can ship while no
 * subscription is configured, and a refund has to be honoured then too.
 */
import {BOOST_PRODUCTS} from "./config.js";
import type {BoostVoidInput, BoostVoidResult} from "./voidedPurchases.js";
import type {DeveloperNotification, RtdnResult} from "../subscription/googleRtdn.js";

/** `voidedPurchaseNotification.productType` */
const PRODUCT_TYPE_SUBSCRIPTION = 1;
const PRODUCT_TYPE_ONE_TIME = 2;
/** `voidedPurchaseNotification.refundType`: only part of a multi-quantity purchase was refunded. */
const REFUND_TYPE_QUANTITY_BASED_PARTIAL = 2;
/** `oneTimeProductNotification.notificationType`: a purchase that was still pending was cancelled. */
const ONE_TIME_PRODUCT_CANCELED = 2;

export async function handleBoostDeveloperNotification(input: {
  notification: DeveloperNotification;
  voidPurchase: (input: BoostVoidInput) => Promise<BoostVoidResult>;
}): Promise<RtdnResult | null> {
  const {notification} = input;
  const oneTime = notification.oneTimeProductNotification;
  const voided = notification.voidedPurchaseNotification;
  if (!oneTime && !voided) {
    return null;
  }
  if (!oneTime && voided?.productType === PRODUCT_TYPE_SUBSCRIPTION) {
    return null;
  }
  // A message for another app must never reach this app's ledger.
  if (notification.packageName !== BOOST_PRODUCTS.androidPackageName) {
    return {outcome: "rejected", reason: "wrong_package"};
  }

  if (oneTime) {
    if (oneTime.notificationType !== ONE_TIME_PRODUCT_CANCELED) {
      // A completed purchase is granted when the app submits its token: Play
      // knows the token, not which Mevora account bought it.
      return {outcome: "ignored", reason: "one_time_purchased"};
    }
    if (!oneTime.purchaseToken) {
      return {outcome: "ignored", reason: "no_token"};
    }
    // A pending purchase is never granted, so normally there is nothing here
    // to take back. If there is a grant, the purchase behind it is gone.
    const result = await input.voidPurchase({
      purchaseToken: oneTime.purchaseToken,
      source: "rtdn_one_time_canceled",
      voidedAt: eventTimeOf(notification),
    });
    return result.outcome === "notFound" ? {outcome: "unattributed", reason: "no_boost_purchase"} : applied(result);
  }

  if (!voided?.purchaseToken) {
    return {outcome: "ignored", reason: "no_token"};
  }
  if (voided.refundType === REFUND_TYPE_QUANTITY_BASED_PARTIAL) {
    // Boost is sold one at a time; a partial refund has nothing to map onto.
    return {outcome: "ignored", reason: "partial_refund"};
  }
  const result = await input.voidPurchase({
    purchaseToken: voided.purchaseToken,
    source: "rtdn_voided",
    orderId: voided.orderId ?? null,
    voidedAt: eventTimeOf(notification),
  });
  if (result.outcome !== "notFound") {
    return applied(result);
  }
  // Not a Boost grant. If Play did not say what kind of purchase it was, it
  // may be a subscription's.
  return voided.productType === PRODUCT_TYPE_ONE_TIME ? {outcome: "unattributed", reason: "no_boost_purchase"} : null;
}

function applied(result: BoostVoidResult): RtdnResult {
  return {outcome: "applied", reason: result.outcome === "voided" ? "voided" : "already_voided"};
}

function eventTimeOf(notification: DeveloperNotification): Date | null {
  const millis = Number(notification.eventTimeMillis);
  return Number.isFinite(millis) && millis > 0 ? new Date(millis) : null;
}
