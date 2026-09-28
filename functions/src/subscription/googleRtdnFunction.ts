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
  type OwnerLookup,
} from "./googleRtdn.js";
import {PlayDeveloperApi} from "./googleSubscriptionVerifier.js";
import {PremiumPurchaseStore} from "./premiumPurchaseStore.js";
import {ownershipRef, type OwnershipRecord} from "./purchaseOwnership.js";

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
  {topic, region: "europe-west1", retry: false},
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

    const result = await handleDeveloperNotification({
      notification,
      api: new PlayDeveloperApi(),
      owners: new FirestoreOwnerLookup(),
      persistenceFor: (args) =>
        new PremiumPurchaseStore({
          userId: args.userId,
          purchaseToken: args.purchaseToken,
          platform: "android",
          productId: args.productId,
          linkedPurchaseToken: args.linkedPurchaseToken,
        }),
    });

    if (result.outcome === "retry") {
      // Throwing is how this function asks Pub/Sub to redeliver. Everything
      // else is deliberately swallowed: acknowledging a message Mevora cannot
      // act on stops Play retrying it forever.
      throw new Error(`premium: rtdn retryable (${result.reason ?? "unknown"})`);
    }
    if (result.outcome !== "applied") {
      logger.info("premium: rtdn not applied", {
        outcome: result.outcome,
        reason: result.reason,
      });
    }
  },
);
