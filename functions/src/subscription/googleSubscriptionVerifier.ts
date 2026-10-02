/**
 * Google Play subscription verification.
 *
 * Talks to purchases.subscriptionsv2.get, which is the subscription contract —
 * deliberately not the purchases.products endpoint the Boost consumable
 * verifier uses. A subscription has a lifecycle (renew, grace, hold, pause,
 * cancel) that the one-time product endpoint cannot express, and reusing it
 * would collapse every one of those states into "purchased".
 *
 * https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2/get
 */
import {logger} from "firebase-functions";
import {safeErrorMeta} from "../security/logHygiene.js";
import type {GoogleSubscriptionPurchase} from "./googleSubscriptionMapper.js";

export type GoogleVerifyFailure =
  /**
   * No service account configured, or Google does not accept the one that
   * is — cannot verify, so cannot grant. Says nothing about the purchase.
   */
  | "unavailable"
  /** Google rejected the token, or it is not a subscription we know. */
  | "invalid"
  /** Google itself is failing; the caller should retry rather than revoke. */
  | "transient";

export type GoogleVerifyResult =
  | {ok: true; purchase: GoogleSubscriptionPurchase}
  | {ok: false; error: GoogleVerifyFailure};

async function playAccessToken(): Promise<string | null> {
  const raw = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON ?? "";
  if (!raw) {
    return null;
  }
  const {GoogleAuth} = await import("google-auth-library");
  const auth = new GoogleAuth({
    credentials: JSON.parse(raw) as Record<string, unknown>,
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  return token.token ?? null;
}

export interface GoogleSubscriptionApi {
  fetchSubscription(input: {
    packageName: string;
    purchaseToken: string;
  }): Promise<GoogleVerifyResult>;
}

export class PlayDeveloperApi implements GoogleSubscriptionApi {
  /** Both seams exist for tests; a deployment uses the defaults. */
  constructor(
    private readonly deps: {
      accessToken?: () => Promise<string | null>;
      fetchImpl?: typeof fetch;
    } = {},
  ) {}

  async fetchSubscription(input: {
    packageName: string;
    purchaseToken: string;
  }): Promise<GoogleVerifyResult> {
    if (!input.packageName || !input.purchaseToken) {
      return {ok: false, error: "invalid"};
    }

    const access = await (this.deps.accessToken ?? playAccessToken)();
    if (!access) {
      // Fail closed. There is deliberately no emulator shortcut that fabricates
      // a purchase here: the Boost verifier has one, but Boost is a consumable
      // and this grants a recurring entitlement. An emulator Premium purchase
      // goes through the same verification contract with a stubbed API, so it
      // still exercises the real ownership and writer path.
      logger.warn("premium: Google Play service account not configured");
      return {ok: false, error: "unavailable"};
    }

    const url =
      "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
      `${encodeURIComponent(input.packageName)}/purchases/subscriptionsv2/tokens/` +
      encodeURIComponent(input.purchaseToken);

    let response: Response;
    try {
      response = await (this.deps.fetchImpl ?? fetch)(url, {
        headers: {Authorization: `Bearer ${access}`},
      });
    } catch (error) {
      // Never the raw error: the request URL carries the purchase token.
      logger.warn("premium: Google Play request failed", {
        error: safeErrorMeta(error, [input.purchaseToken]),
      });
      return {ok: false, error: "transient"};
    }

    if (!response.ok) {
      logger.warn("premium: Google Play rejected a subscription lookup", {
        status: response.status,
      });
      // 401 and 403 are about Mevora's credential — a service account that is
      // not linked in Play Console, or lacks the permission — not about the
      // token. Calling that `invalid` would declare a genuine purchase bad.
      if (response.status === 401 || response.status === 403) {
        return {ok: false, error: "unavailable"};
      }
      // 5xx and 429 are Google's problem and must not revoke a live
      // entitlement; any other 4xx means the token really is not valid for us.
      const transient = response.status >= 500 || response.status === 429;
      return {ok: false, error: transient ? "transient" : "invalid"};
    }

    try {
      const purchase = (await response.json()) as GoogleSubscriptionPurchase;
      return {ok: true, purchase};
    } catch (error) {
      logger.warn("premium: Google Play returned unreadable JSON", {
        error: safeErrorMeta(error, [input.purchaseToken]),
      });
      return {ok: false, error: "transient"};
    }
  }
}
