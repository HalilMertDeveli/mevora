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

    const access = await playAccessToken();
    if (!access) {
      logger.warn("Google Play service account missing");
      return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "unavailable"};
    }

    const pkg = BOOST_PRODUCTS.androidPackageName;
    const url =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${encodeURIComponent(pkg)}/purchases/products/${encodeURIComponent(request.productId)}/tokens/${encodeURIComponent(token)}`;

    try {
      const response = await fetch(url, {headers: {Authorization: `Bearer ${access}`}});
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
      const transactionId = body.orderId || request.transactionId;
      await consume(pkg, request.productId, token, access);
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
}

async function consume(pkg: string, productId: string, token: string, access: string): Promise<void> {
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(pkg)}/purchases/products/${encodeURIComponent(productId)}/tokens/${encodeURIComponent(token)}:consume`;
  try {
    await fetch(url, {method: "POST", headers: {Authorization: `Bearer ${access}`}});
  } catch (error) {
    logger.warn("Play consume skipped", {error: String(error)});
  }
}
