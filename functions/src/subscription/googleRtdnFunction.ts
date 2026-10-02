/**
 * The Pub/Sub trigger that carries Google Play RTDN into Mevora.
 *
 * Kept apart from the pure handler so the decision logic can be tested without
 * a Pub/Sub event, a Firestore instance or a Play credential.
 */
import {onMessagePublished} from "firebase-functions/v2/pubsub";
import {logger} from "firebase-functions";
import {getFirestore} from "firebase-admin/firestore";
import {
  decodeNotification,
  handleDeveloperNotification,
  isTooOldToRetry,
  type OwnerLookup,
} from "./googleRtdn.js";
import {googleSubscriptionApi} from "./emulatorGoogleSubscriptionApi.js";
import {PremiumPurchaseStore} from "./premiumPurchaseStore.js";
import {ownershipRef, type OwnershipRecord} from "./purchaseOwnership.js";
import {googlePlaySecrets} from "../googlePlayConfig.js";
import {handleBoostDeveloperNotification} from "../boost/boostRtdn.js";
import {voidBoostPurchase} from "../boost/voidedPurchases.js";

/**
 * Topic Play publishes to. Configured rather than hardcoded: the topic name is
 * deployment state, and a wrong guess here would silently receive nothing.
 */
const topic = process.env.PREMIUM_RTDN_TOPIC ?? "play-subscription-rtdn";

/** Reads the ownership ledger written when a purchase was verified. */
export class FirestoreOwnerLookup implements OwnerLookup {
  constructor(private readonly db = getFirestore()) {}

  async findOwner(purchaseToken: string): Promise<string | null> {
    const snap = await ownershipRef(this.db, purchaseToken).get();
    if (!snap.exists) {
      return null;
    }
    const record = snap.data() as OwnershipRecord | undefined;
    return record?.userId ?? null;
  }
}

export const onPlaySubscriptionNotification = onMessagePublished(
  {
    topic,
    region: "europe-west1",
    // Redelivery is how a notification survives Google being briefly down:
    // the handler throws and Pub/Sub sends the message again. That only
    // happens when the trigger is declared retryable — without this a throw
    // is logged and the event is gone.
    retry: true,
    secrets: googlePlaySecrets,
  },
  async (event) => {
    const data = event.data.message.data;
    if (!data) {
      logger.warn("premium: rtdn message had no payload");
      return;
    }
    const notification = decodeNotification(data);
    if (!notification) {
      logger.warn("premium: rtdn payload was not decodable");
      return;
    }

    try {
      // The topic carries every product the app sells. One-time purchases —
      // Boost — are answered from the Boost ledger; the rest is Premium's.
      const boost = await handleBoostDeveloperNotification({
        notification,
        voidPurchase: (input) => voidBoostPurchase(getFirestore(), input),
      });
      const result =
        boost ??
        (await handleDeveloperNotification({
          notification,
          api: googleSubscriptionApi(),
          owners: new FirestoreOwnerLookup(),
          persistenceFor: (args) =>
            new PremiumPurchaseStore({
              userId: args.userId,
              purchaseToken: args.purchaseToken,
              platform: "android",
              productId: args.productId,
              linkedPurchaseToken: args.linkedPurchaseToken,
            }),
        }));

      if (result.outcome === "retry") {
        // Throwing is how this function asks Pub/Sub to redeliver. Everything
        // else — an undecodable payload, another app's package, a test ping, a
        // token nobody has claimed — returns normally: acknowledging a message
        // Mevora cannot act on stops it being redelivered forever.
        throw new Error(`premium: rtdn retryable (${result.reason ?? "unknown"})`);
      }
      if (result.outcome !== "applied") {
        logger.info("premium: rtdn not applied", {
          outcome: result.outcome,
          reason: result.reason,
        });
      }
    } catch (error) {
      // The other half of `retry: true`: a message that keeps failing is
      // given up on rather than retried without end. Checked only on failure,
      // so a message that is merely late is still processed.
      if (isTooOldToRetry(event.time, new Date())) {
        logger.error("premium: rtdn message dropped after the retry window", {
          publishedAt: event.time,
          error: String(error),
        });
        return;
      }
      throw error;
    }
  },
);
