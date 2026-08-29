import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {ApplePurchaseVerifier} from "../boost/applePurchaseVerifier.js";
import {GooglePurchaseVerifier} from "../boost/googlePurchaseVerifier.js";
import {purchaseDocId} from "../boost/config.js";
import type {VerifyBoostRequest} from "../boost/types.js";
import {isPremiumProduct, resolvePremiumPack, type PremiumPack} from "./catalog.js";

const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

const apple = new ApplePurchaseVerifier();
const google = new GooglePurchaseVerifier();

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function parseRequest(data: unknown): VerifyBoostRequest {
  const raw = (data ?? {}) as Record<string, unknown>;
  const platform = raw.platform === "ios" ? "ios" : raw.platform === "android" ? "android" : null;
  if (!platform) {
    throw new HttpsError("invalid-argument", "invalid-platform", {reason: "invalid-transaction"});
  }
  return {
    platform,
    productId: String(raw.productId ?? ""),
    transactionId: String(raw.transactionId ?? ""),
    purchaseToken: typeof raw.purchaseToken === "string" ? raw.purchaseToken : undefined,
    signedTransaction: typeof raw.signedTransaction === "string" ? raw.signedTransaction : undefined,
    receiptData: typeof raw.receiptData === "string" ? raw.receiptData : undefined,
  };
}

/**
 * Verifies a store Premium duration pack and writes
 * users/{uid}/subscription/current (Admin-only write path).
 * Client "purchase success" alone never grants Premium.
 */
export const verifyPremiumPurchase = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const body = parseRequest(request.data);
  if (!isPremiumProduct(body.productId)) {
    throw new HttpsError("invalid-argument", "invalid-product", {reason: "invalid-product"});
  }
  const pack = resolvePremiumPack(body.productId);
  if (!pack) {
    throw new HttpsError("invalid-argument", "invalid-product", {reason: "invalid-product"});
  }
  if (!body.transactionId.trim()) {
    throw new HttpsError("invalid-argument", "invalid-transaction", {reason: "invalid-transaction"});
  }

  const db = getFirestore();
  const purchaseId = purchaseDocId(body.platform, body.transactionId);
  const purchaseRef = db.doc(`purchases/${purchaseId}`);
  const existing = await purchaseRef.get();
  if (existing.exists) {
    const data = existing.data() ?? {};
    if (data.userId !== uid) {
      throw new HttpsError("already-exists", "purchase-owned-by-other-user");
    }
    if (data.status === "verified" && data.kind === "premium") {
      const sub = await db.doc(`users/${uid}/subscription/current`).get();
      return {
        alreadyProcessed: true,
        purchaseId,
        productId: body.productId,
        subscription: sub.data() ?? null,
      };
    }
  }

  const store =
    body.platform === "ios" ? await apple.verify(body) : await google.verify(body);
  if (!store.ok) {
    logger.warn("premium store verify failed", {
      uid,
      productId: body.productId,
      error: store.error,
    });
    throw new HttpsError(
      store.error === "unavailable" ? "unavailable" : "failed-precondition",
      store.error === "unavailable" ? "store-unavailable" : "store-invalid",
    );
  }
  if (store.productId !== body.productId) {
    throw new HttpsError("invalid-argument", "invalid-product", {reason: "product-mismatch"});
  }

  const now = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(now.toMillis() + pack.durationMs);
  const subscriptionRef = db.doc(`users/${uid}/subscription/current`);
  const current = await subscriptionRef.get();
  let effectiveExpires = expiresAt;
  if (current.exists) {
    const cur = current.data() ?? {};
    if (cur.isPremium === true && cur.expiresAt && typeof (cur.expiresAt as Timestamp).toMillis === "function") {
      const curExp = (cur.expiresAt as Timestamp).toMillis();
      if (curExp > now.toMillis()) {
        effectiveExpires = Timestamp.fromMillis(curExp + pack.durationMs);
      }
    }
  }

  await db.runTransaction(async (tx) => {
    tx.set(purchaseRef, {
      userId: uid,
      productId: body.productId,
      platform: body.platform,
      transactionId: store.transactionId,
      status: "verified",
      kind: "premium",
      durationDays: pack.durationDays,
      verifiedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      purchaseTokenHash: store.purchaseTokenHashOrReference ?? null,
    }, {merge: true});
    tx.set(subscriptionRef, {
      isPremium: true,
      productId: body.productId,
      expiresAt: effectiveExpires,
      updatedAt: FieldValue.serverTimestamp(),
      source: "store_verify",
      platform: body.platform,
    }, {merge: true});
  });

  return {
    alreadyProcessed: false,
    purchaseId,
    productId: body.productId,
    subscription: {
      isPremium: true,
      productId: body.productId,
      expiresAt: effectiveExpires.toDate().toISOString(),
    },
  };
});

export type {PremiumPack};
