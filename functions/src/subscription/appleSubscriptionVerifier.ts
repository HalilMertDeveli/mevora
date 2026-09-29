/**
 * Apple subscription verification.
 *
 * Talks to the App Store Server API's subscription status endpoint, not the
 * single-transaction endpoint the Boost consumable verifier uses. A
 * subscription has a lifecycle — renew, grace, billing retry, revoke — that a
 * one-off transaction lookup cannot express, and reusing it would collapse all
 * of those into "purchased".
 *
 * Trust comes from the authenticated call to Apple, exactly as in the Boost
 * verifier: the JWS payloads in the response are decoded rather than
 * signature-checked, because they arrived over a channel Apple authenticated.
 * A JWS that reached us any other way would need its chain verified first, and
 * there is no path here that accepts one.
 *
 * https://developer.apple.com/documentation/appstoreserverapi/get_all_subscription_statuses
 */
import {createPrivateKey, sign} from "node:crypto";
import {logger} from "firebase-functions";
import {premiumCatalogue} from "./productCatalog.js";
import type {
  AppleRenewalInfo,
  AppleSubscriptionState,
  AppleTransactionInfo,
} from "./appleSubscriptionMapper.js";

export type AppleVerifyFailure =
  /** No App Store credentials configured — cannot verify, so cannot grant. */
  | "unavailable"
  /** Apple rejected the identifier, or it is not a subscription we know. */
  | "invalid"
  /** Apple itself is failing; the caller should retry rather than revoke. */
  | "transient";

export type AppleVerifyResult =
  | {ok: true; state: AppleSubscriptionState}
  | {ok: false; error: AppleVerifyFailure};

export interface AppleSubscriptionApi {
  fetchSubscription(input: {
    transactionId: string;
  }): Promise<AppleVerifyResult>;
}

/** Signs the ES256 token the App Store Server API expects. */
function appStoreJwt(bundleId: string): string | null {
  const issuerId = process.env.APPLE_IAP_ISSUER_ID ?? "";
  const keyId = process.env.APPLE_IAP_KEY_ID ?? "";
  const privateKey = process.env.APPLE_IAP_PRIVATE_KEY ?? "";
  if (!issuerId || !keyId || !privateKey || !bundleId) {
    return null;
  }
  const header = Buffer.from(
    JSON.stringify({alg: "ES256", kid: keyId, typ: "JWT"}),
  ).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(
    JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + 20 * 60,
      aud: "appstoreconnect-v1",
      bid: bundleId,
    }),
  ).toString("base64url");
  const unsigned = `${header}.${payload}`;
  const key = createPrivateKey(
    privateKey.includes("BEGIN") ? privateKey : privateKey.replace(/\\n/g, "\n"),
  );
  const signature = sign("sha256", Buffer.from(unsigned), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${signature.toString("base64url")}`;
}

/** Reads a JWS payload that arrived inside an authenticated Apple response. */
export function decodeJwsPayload<T>(jws: string): T | null {
  const parts = jws.split(".");
  if (parts.length < 2) {
    return null;
  }
  try {
    return JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8"),
    ) as T;
  } catch {
    return null;
  }
}

/** The subset of the status response this needs. */
interface StatusResponse {
  data?: Array<{
    lastTransactions?: Array<{
      status?: number;
      signedTransactionInfo?: string;
      signedRenewalInfo?: string;
    }>;
  }>;
}

/**
 * Picks the transaction that decides entitlement.
 *
 * Apple returns one entry per subscription group, each with its recent
 * transactions. Anything still granting outranks anything that is not, so a
 * lapsed old transaction cannot mask a live one in the same group.
 */
export function selectSubscriptionState(
  body: StatusResponse,
): AppleSubscriptionState | null {
  const GRANTING = new Set([1, 3, 4]);
  let fallback: AppleSubscriptionState | null = null;

  for (const group of body.data ?? []) {
    for (const entry of group.lastTransactions ?? []) {
      const transaction = decodeJwsPayload<AppleTransactionInfo & {
        expiresDate?: number | string | null;
      }>(entry.signedTransactionInfo ?? "");
      if (!transaction) {
        continue;
      }
      const renewal =
        decodeJwsPayload<AppleRenewalInfo>(entry.signedRenewalInfo ?? "") ?? {};
      const state: AppleSubscriptionState = {
        status: entry.status ?? null,
        expiresDate: transaction.expiresDate ?? null,
        transaction,
        renewal,
      };
      if (typeof entry.status === "number" && GRANTING.has(entry.status)) {
        return state;
      }
      fallback ??= state;
    }
  }
  return fallback;
}

export class AppStoreServerApi implements AppleSubscriptionApi {
  async fetchSubscription(input: {
    transactionId: string;
  }): Promise<AppleVerifyResult> {
    if (!input.transactionId) {
      return {ok: false, error: "invalid"};
    }
    const bundleId = premiumCatalogue().iosBundleId;
    const jwt = appStoreJwt(bundleId);
    if (!jwt) {
      // Fail closed, and deliberately with no emulator shortcut that
      // fabricates a subscription: this grants a recurring entitlement, so an
      // emulator run goes through the same contract with a stubbed API rather
      // than around it.
      logger.warn("premium: App Store credentials not configured");
      return {ok: false, error: "unavailable"};
    }

    // Production first, sandbox on a miss — the same order the Boost verifier
    // uses, so a sandbox tester is not silently treated as production.
    for (const host of [
      "api.storekit.itunes.apple.com",
      "api.storekit-sandbox.itunes.apple.com",
    ]) {
      const url =
        `https://${host}/inApps/v1/subscriptions/` +
        encodeURIComponent(input.transactionId);

      let response: Response;
      try {
        response = await fetch(url, {headers: {Authorization: `Bearer ${jwt}`}});
      } catch (error) {
        logger.warn("premium: App Store request failed", {error});
        return {ok: false, error: "transient"};
      }

      if (response.status === 404) {
        continue;
      }
      if (!response.ok) {
        // 5xx and 429 are Apple's problem and must not revoke a live
        // entitlement; other 4xx means the identifier is not valid for us.
        const transient = response.status >= 500 || response.status === 429;
        logger.warn("premium: App Store rejected a subscription lookup", {
          status: response.status,
        });
        return {ok: false, error: transient ? "transient" : "invalid"};
      }

      let body: StatusResponse;
      try {
        body = (await response.json()) as StatusResponse;
      } catch (error) {
        logger.warn("premium: App Store returned unreadable JSON", {error});
        return {ok: false, error: "transient"};
      }

      const state = selectSubscriptionState(body);
      if (!state) {
        return {ok: false, error: "invalid"};
      }
      return {ok: true, state};
    }

    return {ok: false, error: "invalid"};
  }
}
