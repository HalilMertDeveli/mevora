/**
 * Google's side of a test purchase, for the Functions emulator only.
 *
 * An emulator has no Play account and no Premium product, so the real
 * `subscriptionsv2.get` has nothing to say about any token it could produce.
 * This answers in its place — for tokens the app's emulator test store minted,
 * and for nothing else — with an ordinary active subscription.
 *
 * It stands in for Google and for nothing after Google. The answer goes through
 * the same mapper, catalogue check, token-ownership claim and entitlement
 * writer as a real one, so a test purchase exercises everything Mevora owns:
 * a second account presenting the same token is still refused, and the paywall
 * still only unlocks once the written entitlement is observed.
 *
 * Selected by `googleSubscriptionApi()` only when `FUNCTIONS_EMULATOR` is set
 * and no Play service account is configured. Deployed functions never run with
 * that variable, so there is no production path to this class.
 */
import type {
  GoogleSubscriptionApi,
  GoogleVerifyResult,
} from "./googleSubscriptionVerifier.js";
import {PlayDeveloperApi} from "./googleSubscriptionVerifier.js";

/** Must match `EmulatorPremiumBillingRepository.tokenPrefix` in the app. */
export const EMULATOR_TOKEN_PREFIX = "emulator-test:";

const DAY_MS = 24 * 60 * 60 * 1000;

export class EmulatorGoogleSubscriptionApi implements GoogleSubscriptionApi {
  constructor(private readonly clock: () => Date = () => new Date()) {}

  async fetchSubscription(input: {
    packageName: string;
    purchaseToken: string;
  }): Promise<GoogleVerifyResult> {
    const token = input.purchaseToken ?? "";
    if (!token.startsWith(EMULATOR_TOKEN_PREFIX)) {
      // Anything the test store did not mint is not a purchase here either.
      return {ok: false, error: "invalid"};
    }
    // `emulator-test:<productId>:<basePlanId>:<nonce>`
    const [productId, basePlanId] = token
      .slice(EMULATOR_TOKEN_PREFIX.length)
      .split(":");
    if (!productId) {
      return {ok: false, error: "invalid"};
    }

    const now = this.clock();
    const days = basePlanId === "yearly" ? 365 : 30;
    const expiry = new Date(now.getTime() + days * DAY_MS);

    return {
      ok: true,
      purchase: {
        subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
        acknowledgementState: "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        // Marks the write as sandbox, so a test grant is never recorded as a
        // production purchase even inside the emulator.
        testPurchase: {},
        latestOrderId: `GPA.EMULATOR-${now.getTime()}`,
        startTime: now.toISOString(),
        lineItems: [
          {
            productId,
            expiryTime: expiry.toISOString(),
            autoRenewingPlan: {autoRenewEnabled: true},
            offerDetails: {basePlanId: basePlanId || null},
          },
        ],
      },
    };
  }
}

/**
 * The Google API every Premium entry point uses.
 *
 * The emulator stand-in needs both conditions: running under the Functions
 * emulator, and no real Play credential configured. With a credential present
 * the emulator talks to real Google, so a sandbox purchase can still be tested
 * locally against the real API.
 */
export function googleSubscriptionApi(
  env: NodeJS.ProcessEnv = process.env,
): GoogleSubscriptionApi {
  if (env.FUNCTIONS_EMULATOR === "true" && !env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) {
    return new EmulatorGoogleSubscriptionApi();
  }
  return new PlayDeveloperApi();
}
