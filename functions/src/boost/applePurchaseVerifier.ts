import {createPrivateKey, sign} from "node:crypto";
import {logger} from "firebase-functions";
import {BOOST_PRODUCTS} from "./config.js";
import {sha256} from "./hash.js";
import type {StoreVerificationResult, VerifyBoostRequest} from "./types.js";

function appStoreJwt(): string | null {
  const issuerId = process.env.APPLE_IAP_ISSUER_ID ?? "";
  const keyId = process.env.APPLE_IAP_KEY_ID ?? "";
  const privateKey = process.env.APPLE_IAP_PRIVATE_KEY ?? "";
  if (!issuerId || !keyId || !privateKey) {
    return null;
  }
  const header = Buffer.from(JSON.stringify({alg: "ES256", kid: keyId, typ: "JWT"})).toString(
    "base64url",
  );
  const now = Math.floor(Date.now() / 1000);
  const payload = Buffer.from(
    JSON.stringify({
      iss: issuerId,
      iat: now,
      exp: now + 20 * 60,
      aud: "appstoreconnect-v1",
      bid: BOOST_PRODUCTS.bundleId,
    }),
  ).toString("base64url");
  const unsigned = `${header}.${payload}`;
  const key = createPrivateKey(privateKey.includes("BEGIN") ? privateKey : privateKey.replace(/\\n/g, "\n"));
  const signature = sign("sha256", Buffer.from(unsigned), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${signature.toString("base64url")}`;
}

async function fetchTransaction(transactionId: string, sandbox: boolean, jwt: string) {
  const host = sandbox ? "api.storekit-sandbox.itunes.apple.com" : "api.storekit.itunes.apple.com";
  const response = await fetch(`https://${host}/inApps/v1/transactions/${transactionId}`, {
    headers: {Authorization: `Bearer ${jwt}`},
  });
  return response;
}

/**
 * Verifies an iOS Boost purchase with the App Store Server API.
 * Does not trust a client "payment succeeded" flag.
 */
export class ApplePurchaseVerifier {
  async verify(request: VerifyBoostRequest): Promise<StoreVerificationResult> {
    const jwt = appStoreJwt();
    if (!jwt) {
      if (process.env.FUNCTIONS_EMULATOR === "true") {
        return {
          ok: true,
          productId: request.productId,
          transactionId: request.transactionId,
          purchaseTokenHashOrReference: request.signedTransaction
            ? sha256(request.signedTransaction)
            : undefined,
          purchasedAt: new Date(),
        };
      }
      logger.warn("Apple IAP credentials missing");
      return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "unavailable"};
    }

    try {
      let response = await fetchTransaction(request.transactionId, false, jwt);
      if (response.status === 404) {
        response = await fetchTransaction(request.transactionId, true, jwt);
      }
      if (!response.ok) {
        return {
          ok: false,
          productId: request.productId,
          transactionId: request.transactionId,
          error: response.status >= 500 ? "unavailable" : "invalid",
        };
      }
      const body = (await response.json()) as {signedTransactionInfo?: string};
      const info = decodeJwsPayload(body.signedTransactionInfo ?? request.signedTransaction ?? "");
      if (!info) {
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      if (info.bundleId && info.bundleId !== BOOST_PRODUCTS.bundleId) {
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      if (info.productId && info.productId !== request.productId) {
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      if (info.revocationDate) {
        return {ok: false, productId: request.productId, transactionId: request.transactionId, error: "invalid"};
      }
      const txId = String(info.transactionId ?? request.transactionId);
      return {
        ok: true,
        productId: String(info.productId ?? request.productId),
        transactionId: txId,
        originalTransactionId: info.originalTransactionId ? String(info.originalTransactionId) : undefined,
        purchaseTokenHashOrReference: sha256(request.signedTransaction ?? request.receiptData ?? txId),
        purchasedAt: info.purchaseDate ? new Date(Number(info.purchaseDate)) : new Date(),
      };
    } catch (error) {
      logger.warn("Apple verification unavailable", {error: String(error)});
      return {
        ok: false,
        productId: request.productId,
        transactionId: request.transactionId,
        error: "unavailable",
      };
    }
  }
}

function decodeJwsPayload(jws: string): Record<string, unknown> | null {
  const parts = jws.split(".");
  if (parts.length < 2) {
    return null;
  }
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}
