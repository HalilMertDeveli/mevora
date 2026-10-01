/**
 * The fallback for refunds nobody was told about.
 *
 * A voided Boost purchase normally arrives as a Play notification. That
 * depends on notifications being configured, on the topic, and on the function
 * being up when the message is delivered. This asks Play for the list instead
 * — every one-time purchase it voided recently — and puts each through the
 * same idempotent void, so a refund that was missed is caught within a day.
 */
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {GooglePurchaseVerifier} from "./googlePurchaseVerifier.js";
import {voidBoostPurchase} from "./voidedPurchases.js";
import {googlePlaySecrets} from "../googlePlayConfig.js";

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * How far back each run looks. Play keeps voided purchases for 30 days and
 * refuses an older start time, so this is the whole list with a day to spare:
 * a purchase is seen on every run for a month, and missing runs loses nothing.
 */
export const VOIDED_SWEEP_LOOKBACK_MS = 29 * DAY_MS;
/** Anything beyond this many pages waits for the next run. */
export const VOIDED_SWEEP_MAX_PAGES = 20;

export interface VoidedSweepResult {
  seen: number;
  voided: number;
  alreadyVoided: number;
  /** Voided purchases that never bought a Boost here. */
  unknown: number;
  pages: number;
  /** False when Play could not be asked, or the list was longer than one run reads. */
  complete: boolean;
}

export async function sweepVoidedBoostPurchases(
  db: Firestore,
  options: {play: GooglePurchaseVerifier; now?: Date; maxPages?: number},
): Promise<VoidedSweepResult> {
  const startTime = new Date((options.now ?? new Date()).getTime() - VOIDED_SWEEP_LOOKBACK_MS);
  const maxPages = options.maxPages ?? VOIDED_SWEEP_MAX_PAGES;
  const result: VoidedSweepResult = {seen: 0, voided: 0, alreadyVoided: 0, unknown: 0, pages: 0, complete: false};

  let pageToken: string | null = null;
  while (result.pages < maxPages) {
    const page = await options.play.listVoidedPurchases({startTime, pageToken});
    if (!page.ok) {
      logger.warn("boost_voided_sweep_incomplete", {...result, reason: "play_unavailable"});
      return result;
    }
    result.pages += 1;
    for (const purchase of page.purchases) {
      result.seen += 1;
      const {outcome} = await voidBoostPurchase(db, {
        purchaseToken: purchase.purchaseToken,
        source: "voided_purchases_api",
        orderId: purchase.orderId,
        voidedAt: purchase.voidedAt,
        voidedReason: purchase.voidedReason,
        voidedSource: purchase.voidedSource,
      });
      if (outcome === "voided") {
        result.voided += 1;
      } else if (outcome === "alreadyVoided") {
        result.alreadyVoided += 1;
      } else {
        result.unknown += 1;
      }
    }
    if (!page.nextPageToken) {
      result.complete = true;
      break;
    }
    pageToken = page.nextPageToken;
  }

  if (result.complete) {
    logger.info("boost_voided_sweep", {...result});
  } else {
    logger.warn("boost_voided_sweep_incomplete", {...result, reason: "page_limit"});
  }
  return result;
}

export const reconcileVoidedBoostPurchases = onSchedule(
  {schedule: "every 24 hours", region: "europe-west1", secrets: googlePlaySecrets},
  async () => {
    await sweepVoidedBoostPurchases(getFirestore(), {play: new GooglePurchaseVerifier()});
  },
);
