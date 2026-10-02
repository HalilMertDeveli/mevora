import {logger} from "firebase-functions";
import {safeErrorMeta} from "../security/logHygiene.js";
import {BOOST_PRODUCTS} from "./config.js";
import {sha256} from "./hash.js";
import type {StoreVerificationResult, VerifyBoostRequest} from "./types.js";

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

/**
 * Verifies an Android Boost purchase with the Google Play Developer API.
 * Does not trust a client "payment succeeded" flag.
 */
export class GooglePurchaseVerifier {
  /** The Play credentials and HTTP client can be swapped, so tests never reach Google. */
  constructor(private readonly deps: PlayApiDeps = {}) {}

  async verify(request: VerifyBoostRequest): Promise<StoreVerificationResult> {
    const token = request.purchaseToken;
    if (!token) {
      return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
    }

    if (process.env.FUNCTIONS_EMULATOR === "true" && !process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) {
      return {
        ok: true,
        productId: request.productId,
        transactionId: request.transactionId,
        purchaseTokenHashOrReference: sha256(token),
        purchasedAt: new Date(),
      };
    }

    const access = await (this.deps.accessToken ?? playAccessToken)();
    if (!access) {
      logger.warn("Google Play service account missing");
      return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "unavailable"};
    }

    try {
      const response = await (this.deps.fetch ?? fetch)(purchaseUrl(request.productId, token), {
        headers: {Authorization: `Bearer ${access}`},
      });
      if (!response.ok) {
        return {
          ok: false,
          productId: request.productId,
          transactionId: request.transactionId,
          error: response.status >= 500 ? "unavailable" : "invalid",
        };
      }
      const body = (await response.json()) as {
        purchaseState?: number;
        orderId?: string;
        purchaseTimeMillis?: string;
        consumptionState?: number;
      };
      if (body.purchaseState !== 0) {
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      // A consumed purchase has been spent. verify() only runs for a token the
      // ledger has never seen, so this one was consumed without a grant on
      // record: a replay, or a ledger entry that no longer exists.
      if (body.consumptionState === 1) {
        logger.warn("boost_purchase_token_already_consumed", {productId: request.productId});
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      const transactionId = body.orderId || request.transactionId;
      return {
        ok: true,
        productId: request.productId,
        transactionId,
        purchaseTokenHashOrReference: sha256(token),
        purchasedAt: body.purchaseTimeMillis ? new Date(Number(body.purchaseTimeMillis)) : new Date(),
      };
    } catch (error) {
      // Never the raw error text: the request URL carries the purchase token.
      logger.warn("Google Play verification unavailable", {error: safeErrorMeta(error, [token])});
      return {
        ok: false,
        productId: request.productId,
        transactionId: request.transactionId,
        error: "unavailable",
      };
    }
  }

  /**
   * Consumes a purchase on Google Play. Call it only once the grant is on the
   * ledger: a consumed token can never be verified again, so consuming first
   * would lose the purchase if the grant then failed.
   *
   * Resolves to whether Play confirmed it. Never throws — the grant is already
   * committed, and the caller retries on the next verification of this token.
   */
  async consume(request: VerifyBoostRequest): Promise<boolean> {
    const token = request.purchaseToken;
    if (!token) {
      return false;
    }
    try {
      const access = await (this.deps.accessToken ?? playAccessToken)();
      if (!access) {
        return false;
      }
      const response = await (this.deps.fetch ?? fetch)(`${purchaseUrl(request.productId, token)}:consume`, {
        method: "POST",
        headers: {Authorization: `Bearer ${access}`},
      });
      if (!response.ok) {
        logger.warn("Play consume failed", {status: response.status});
      }
      return response.ok;
    } catch (error) {
      logger.warn("Play consume skipped", {error: safeErrorMeta(error, [token])});
      return false;
    }
  }

  /**
   * One page of the one-time purchases Play has voided since `startTime`
   * (Voided Purchases API). Never throws: a run that cannot ask Play reports
   * it and the next run asks again.
   */
  async listVoidedPurchases(params: {startTime: Date; pageToken?: string | null}): Promise<VoidedPurchasesPage> {
    if (process.env.FUNCTIONS_EMULATOR === "true" && !process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) {
      // The emulator has no Play account behind it, so nothing was ever voided.
      return {ok: true, purchases: [], nextPageToken: null};
    }
    try {
      const access = await (this.deps.accessToken ?? playAccessToken)();
      if (!access) {
        logger.warn("Google Play service account missing");
        return {ok: false, error: "unavailable"};
      }
      // type=0: one-time purchases only. Subscriptions have their own path.
      const query = new URLSearchParams({startTime: String(params.startTime.getTime()), type: "0"});
      if (params.pageToken) {
        query.set("token", params.pageToken);
      }
      const response = await (this.deps.fetch ?? fetch)(`${voidedPurchasesUrl()}?${query.toString()}`, {
        headers: {Authorization: `Bearer ${access}`},
      });
      if (!response.ok) {
        logger.warn("Play voided purchases list failed", {status: response.status});
        return {ok: false, error: "unavailable"};
      }
      const body = (await response.json()) as {
        voidedPurchases?: Array<{
          purchaseToken?: string;
          orderId?: string;
          voidedTimeMillis?: string;
          voidedReason?: number;
          voidedSource?: number;
        }>;
        tokenPagination?: {nextPageToken?: string};
      };
      const purchases: VoidedPlayPurchase[] = [];
      for (const item of body.voidedPurchases ?? []) {
        if (!item.purchaseToken) {
          continue;
        }
        const voidedAt = Number(item.voidedTimeMillis);
        purchases.push({
          purchaseToken: item.purchaseToken,
          orderId: item.orderId ?? null,
          voidedAt: Number.isFinite(voidedAt) && voidedAt > 0 ? new Date(voidedAt) : null,
          voidedReason: typeof item.voidedReason === "number" ? item.voidedReason : null,
          voidedSource: typeof item.voidedSource === "number" ? item.voidedSource : null,
        });
      }
      return {ok: true, purchases, nextPageToken: body.tokenPagination?.nextPageToken || null};
    } catch (error) {
      logger.warn("Play voided purchases list unavailable", {error: safeErrorMeta(error)});
      return {ok: false, error: "unavailable"};
    }
  }
}

export interface PlayApiDeps {
  accessToken?: () => Promise<string | null>;
  fetch?: typeof fetch;
}

/** A purchase Play reports as voided: refunded, charged back or revoked. */
export interface VoidedPlayPurchase {
  purchaseToken: string;
  orderId: string | null;
  voidedAt: Date | null;
  voidedReason: number | null;
  voidedSource: number | null;
}

export type VoidedPurchasesPage =
  | {ok: true; purchases: VoidedPlayPurchase[]; nextPageToken: string | null}
  | {ok: false; error: "unavailable"};

function voidedPurchasesUrl(): string {
  return (
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(BOOST_PRODUCTS.androidPackageName)}/purchases/voidedpurchases`
  );
}

function purchaseUrl(productId: string, token: string): string {
  return (
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(BOOST_PRODUCTS.androidPackageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`
  );
}
