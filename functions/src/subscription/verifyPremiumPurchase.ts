/**
 * The one entry point where a client may present store purchase evidence.
 *
 * What the client sends is evidence, never a decision. The product, the price,
 * the expiry and whether it is premium at all are read from the store, not
 * from the request; the request only says which token to go and check. A
 * client that lies about `productId` gets whatever the store says that token
 * really is, and the catalogue decides whether that grants anything.
 *
 * Used for both first purchase and restore — restore is the same evidence
 * arriving again, so it takes the same path rather than a shortcut that could
 * skip verification.
 *
 * The answer is also what the client acts on to acknowledge the purchase, and
 * Play refunds a subscription nobody acknowledges within three days. So the
 * two kinds of "no" are kept apart:
 *
 * - **Could not be verified** (no catalogue, no store credential, the store is
 *   failing) is thrown as an `HttpsError`. Nothing was decided, the purchase
 *   stays unacknowledged, and the client presents it again later. Returning
 *   these as an ordinary result is what once let a misconfigured backend take
 *   payment for an entitlement it never wrote.
 * - **Verified and refused** is returned as `ok: false` with a reason.
 *
 * Only `ok: true` — the entitlement was written, or is already held — and
 * `owned_by_other` tell the client the purchase is accounted for.
 */
import {createHash} from "node:crypto";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {SubscriptionEntitlementWriter} from "./entitlementWriter.js";
import {
  PremiumPurchaseStore,
  PurchaseOwnershipConflict,
} from "./premiumPurchaseStore.js";
import {mapGoogleSubscription} from "./googleSubscriptionMapper.js";
import {mapAppleSubscription} from "./appleSubscriptionMapper.js";
import {
  AppStoreServerApi,
  type AppleSubscriptionApi,
} from "./appleSubscriptionVerifier.js";
import {type GoogleSubscriptionApi} from "./googleSubscriptionVerifier.js";
import {googleSubscriptionApi} from "./emulatorGoogleSubscriptionApi.js";
import {premiumCatalogue} from "./productCatalog.js";
import {evaluatePremiumAccess} from "./entitlementPolicy.js";
import {tokenIdentity} from "./purchaseOwnership.js";
import {googlePlaySecrets} from "../googlePlayConfig.js";

// Same App Check convention as every other callable: enforced in production,
// relaxed only under the Functions emulator. Premium must not be the one
// callable that quietly ships without attestation.
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const premiumCallable = {
  enforceAppCheck,
  region: "europe-west1" as const,
  secrets: googlePlaySecrets,
};

/**
 * The account id the app attaches to a Play purchase
 * (`obfuscatedExternalAccountId`). A hash, because Play forbids anything
 * personal there, and exactly 64 characters, which is Play's limit.
 *
 * Must match `StorePremiumBillingRepository.accountIdFor` in the app.
 */
export function premiumAccountId(userId: string): string {
  return createHash("sha256").update(userId).digest("hex");
}

/** Nothing could be decided; the client must keep the purchase and retry. */
function notConfigured(): HttpsError {
  // Fail closed, and loudly: with no configured products nothing can be
  // Premium, and someone may be standing at the store sheet right now.
  logger.error("premium: verification requested but nothing is configured");
  return new HttpsError("failed-precondition", "premium-not-configured");
}

function storeUnavailable(error: "transient" | "unavailable"): HttpsError {
  // `transient`: the store is failing. `unavailable`: Mevora's own store
  // credential is missing or not authorised. Either way the purchase was not
  // looked at, so a live entitlement must not be torn down and a new purchase
  // must not be acknowledged.
  if (error === "unavailable") {
    logger.error("premium: store credential missing or not authorised");
    return new HttpsError("unavailable", "store-credentials-unavailable");
  }
  return new HttpsError("unavailable", "store-unavailable");
}

export interface VerifyPremiumPurchaseResult {
  ok: boolean;
  isPremium: boolean;
  status: string | null;
  accessUntil: string | null;
  /** Why a verification did not grant anything, for the client to surface. */
  reason?: string;
}

/**
 * Runs the verification for an already-authenticated user.
 *
 * Extracted from the callable so tests can drive it with a stubbed store API
 * and a stubbed persistence, exercising the real ownership and writer path.
 */
export async function verifyAndroidPremiumPurchase(input: {
  userId: string;
  purchaseToken: string;
  api: GoogleSubscriptionApi;
  now?: Date;
  makeStore?: (args: {
    userId: string;
    purchaseToken: string;
    productId: string;
    linkedPurchaseToken: string | null;
  }) => ConstructorParameters<typeof SubscriptionEntitlementWriter>[0];
}): Promise<VerifyPremiumPurchaseResult> {
  const now = input.now ?? new Date();
  const catalogue = premiumCatalogue();
  const packageName = catalogue.androidPackageName;

  if (!packageName || catalogue.android.length === 0) {
    throw notConfigured();
  }

  const verified = await input.api.fetchSubscription({
    packageName,
    purchaseToken: input.purchaseToken,
  });
  if (!verified.ok) {
    if (verified.error !== "invalid") {
      throw storeUnavailable(verified.error);
    }
    return {
      ok: false,
      isPremium: false,
      status: null,
      accessUntil: null,
      reason: verified.error,
    };
  }

  const mapped = mapGoogleSubscription({
    userId: input.userId,
    packageName,
    purchase: verified.purchase,
    eventAt: now,
    catalogue,
  });
  if (!mapped.ok) {
    return {
      ok: false,
      isPremium: false,
      status: null,
      accessUntil: null,
      reason: mapped.reason,
    };
  }

  // The app stamps each purchase with the account that started it. A stamp
  // naming someone else means this caller is presenting another account's
  // purchase — the same Play account on a shared device, typically — before
  // its buyer has claimed it. Refused before anything is claimed or written.
  // No stamp is accepted: older builds did not set one, and a resubscription
  // made in the Play Store itself carries none.
  if (
    mapped.obfuscatedExternalAccountId &&
    mapped.obfuscatedExternalAccountId !== premiumAccountId(input.userId)
  ) {
    logger.warn("premium: purchase was made for a different account");
    return {
      ok: false,
      isPremium: false,
      status: null,
      accessUntil: null,
      reason: "account_mismatch",
    };
  }

  const persistence = input.makeStore
    ? input.makeStore({
        userId: input.userId,
        purchaseToken: input.purchaseToken,
        productId: String(mapped.write.productId),
        linkedPurchaseToken: mapped.linkedPurchaseToken,
      })
    : new PremiumPurchaseStore({
        userId: input.userId,
        purchaseToken: input.purchaseToken,
        platform: "android",
        productId: String(mapped.write.productId),
        linkedPurchaseToken: mapped.linkedPurchaseToken,
      });

  try {
    const writer = new SubscriptionEntitlementWriter(persistence, () => now);
    const result = await writer.apply({
      ...mapped.write,
      ...tokenIdentity(input.purchaseToken, mapped.linkedPurchaseToken),
    });
    const access = evaluatePremiumAccess(result.state, now);
    return {
      ok: true,
      isPremium: access.isPremium,
      status: result.state?.status ?? null,
      accessUntil: access.accessUntil ? access.accessUntil.toISOString() : null,
    };
  } catch (error) {
    if (error instanceof PurchaseOwnershipConflict) {
      // Deliberately does not say who owns it.
      logger.warn("premium: purchase token claimed by another account");
      return {
        ok: false,
        isPremium: false,
        status: null,
        accessUntil: null,
        reason: "owned_by_other",
      };
    }
    throw error;
  }
}

/**
 * The Apple counterpart, deliberately the same sequence as Android.
 *
 * The client presents a transaction id; everything that decides entitlement —
 * product, status, expiry, whether it was revoked — is read from Apple. The
 * subscription is then owned by its *original* transaction id, because Apple
 * issues a new one every renewal and keying ownership on the latest would let
 * each renewal look like an unclaimed purchase.
 */
export async function verifyIosPremiumPurchase(input: {
  userId: string;
  transactionId: string;
  api: AppleSubscriptionApi;
  now?: Date;
  makeStore?: (args: {
    userId: string;
    purchaseToken: string;
    productId: string;
    linkedPurchaseToken: string | null;
  }) => ConstructorParameters<typeof SubscriptionEntitlementWriter>[0];
}): Promise<VerifyPremiumPurchaseResult> {
  const now = input.now ?? new Date();
  const catalogue = premiumCatalogue();

  if (!catalogue.iosBundleId || catalogue.ios.length === 0) {
    throw notConfigured();
  }

  const verified = await input.api.fetchSubscription({
    transactionId: input.transactionId,
  });
  if (!verified.ok) {
    if (verified.error !== "invalid") {
      throw storeUnavailable(verified.error);
    }
    return {
      ok: false,
      isPremium: false,
      status: null,
      accessUntil: null,
      reason: verified.error,
    };
  }

  const mapped = mapAppleSubscription({
    userId: input.userId,
    state: verified.state,
    eventAt: now,
  });
  if (!mapped.ok) {
    return {
      ok: false,
      isPremium: false,
      status: null,
      accessUntil: null,
      reason: mapped.reason,
    };
  }

  // Stable across renewals. Falling back to the presented id keeps a first
  // purchase working if Apple has not filled the original in yet.
  const ownershipKey = mapped.originalTransactionId ?? input.transactionId;
  const persistence = input.makeStore
    ? input.makeStore({
        userId: input.userId,
        purchaseToken: ownershipKey,
        productId: String(mapped.write.productId),
        linkedPurchaseToken: null,
      })
    : new PremiumPurchaseStore({
        userId: input.userId,
        purchaseToken: ownershipKey,
        platform: "ios",
        productId: String(mapped.write.productId),
        linkedPurchaseToken: null,
      });

  try {
    const writer = new SubscriptionEntitlementWriter(persistence, () => now);
    const result = await writer.apply({
      ...mapped.write,
      ...tokenIdentity(ownershipKey),
    });
    const access = evaluatePremiumAccess(result.state, now);
    return {
      ok: true,
      isPremium: access.isPremium,
      status: result.state?.status ?? null,
      accessUntil: access.accessUntil ? access.accessUntil.toISOString() : null,
    };
  } catch (error) {
    if (error instanceof PurchaseOwnershipConflict) {
      logger.warn("premium: apple subscription claimed by another account");
      return {
        ok: false,
        isPremium: false,
        status: null,
        accessUntil: null,
        reason: "owned_by_other",
      };
    }
    throw error;
  }
}

export const verifyPremiumPurchase = onCall(
  premiumCallable,
  async (request): Promise<VerifyPremiumPurchaseResult> => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "sign-in-required");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const platform = String(data.platform ?? "");
    const purchaseToken = String(data.purchaseToken ?? "");

    if (!purchaseToken) {
      throw new HttpsError("invalid-argument", "purchase-token-required");
    }

    if (platform === "android") {
      return verifyAndroidPremiumPurchase({
        userId,
        purchaseToken,
        api: googleSubscriptionApi(),
      });
    }
    if (platform === "ios") {
      return verifyIosPremiumPurchase({
        userId,
        transactionId: purchaseToken,
        api: new AppStoreServerApi(),
      });
    }
    // Anything else grants nothing rather than falling through to a verifier
    // that was not written for it.
    throw new HttpsError("invalid-argument", "unsupported-platform");
  },
);
