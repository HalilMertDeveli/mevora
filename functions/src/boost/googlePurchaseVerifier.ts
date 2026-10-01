import {logger} from "firebase-functions";
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
      logger.warn("Google Play verification unavailable", {error: String(error)});
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
      logger.warn("Play consume skipped", {error: String(error)});
      return false;
    }
  }
}

export interface PlayApiDeps {
  accessToken?: () => Promise<string | null>;
  fetch?: typeof fetch;
}

function purchaseUrl(productId: string, token: string): string {
  return (
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(BOOST_PRODUCTS.androidPackageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}`
  );
}
