import {FieldValue, Timestamp, getFirestore, type DocumentData, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {ApplePurchaseVerifier} from "./applePurchaseVerifier.js";
import {BoostActivationService} from "./boostActivationService.js";
import {ensureDefaultCatalog, resolveBoostPack} from "./catalog.js";
import {BoostCreditService} from "./creditService.js";
import {GooglePurchaseVerifier} from "./googlePurchaseVerifier.js";
import {PurchaseVerificationService} from "./purchaseVerificationService.js";
import {walletDocPath} from "./config.js";
import type {ActiveBoostSnapshot, PurchaseLedger, VerifyBoostRequest} from "./types.js";
import {FcmTypes, sendUserPush} from "../notifications.js";

const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

const verification = new PurchaseVerificationService(
  new ApplePurchaseVerifier(),
  new GooglePurchaseVerifier(),
);
const activation = new BoostActivationService();
const credit = new BoostCreditService();

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

function boostPayload(data: DocumentData, boostId: string) {
  const expires = data.expiresAt as Timestamp | undefined;
  const started = data.startedAt as Timestamp | undefined;
  return {
    boostId,
    userId: data.userId,
    productId: data.productId,
    purchaseId: data.purchaseId,
    status: data.status,
    startedAt: started?.toDate().toISOString() ?? null,
    expiresAt: expires?.toDate().toISOString() ?? null,
    createdAt: (data.createdAt as Timestamp | undefined)?.toDate().toISOString() ?? null,
  };
}

function walletPayload(balance: number) {
  return {balance};
}

function purchasePayload(data: DocumentData, purchaseId: string) {
  return {
    purchaseId,
    userId: data.userId,
    productId: data.productId,
    boostCount: Number(data.boostCount ?? 0),
    status: data.status,
    platform: data.platform,
    transactionId: data.transactionId,
  };
}

function toSnapshots(
  uid: string,
  docs: QueryDocumentSnapshot[],
): ActiveBoostSnapshot[] {
  return docs.map((doc) => {
    const data = doc.data();
    const expires = data.expiresAt as Timestamp | undefined;
    return {
      boostId: doc.id,
      userId: uid,
      status: data.status,
      expiresAt: expires?.toDate() ?? null,
    };
  });
}

export const verifyBoostPurchase = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const payload = parseRequest(request.data);
  const db = getFirestore();
  await ensureDefaultCatalog(db);
  const pack = await resolveBoostPack(db, payload.productId);
  const purchaseIdGuess = `${payload.platform}_${payload.transactionId}`;
  const existingSnap = await db.doc(`purchases/${purchaseIdGuess}`).get();
  const existing = existingSnap.exists
    ? ({
        purchaseId: existingSnap.id,
        userId: String(existingSnap.data()?.userId ?? ""),
        productId: String(existingSnap.data()?.productId ?? ""),
        platform: payload.platform,
        transactionId: String(existingSnap.data()?.transactionId ?? ""),
        status: existingSnap.data()?.status === "verified" ? "verified" : "pending",
      } satisfies PurchaseLedger)
    : null;

  const decision = await verification.verify({uid, request: payload, existing, pack});
  if (decision.outcome === "invalidUid") {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (
    decision.outcome === "invalidProduct" ||
    decision.outcome === "invalidTransaction" ||
    decision.outcome === "storeInvalid" ||
    decision.outcome === "duplicateOtherUser"
  ) {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }
  if (decision.outcome === "storeUnavailable") {
    throw new HttpsError("unavailable", "store-unavailable", {reason: "store-unavailable"});
  }

  const walletRef = db.doc(walletDocPath(uid));
  if (decision.outcome === "alreadyProcessed") {
    const purchase = await db.doc(`purchases/${decision.purchaseId}`).get();
    const wallet = await walletRef.get();
    logger.info("boost_purchase_idempotent", {userId: uid, purchaseId: decision.purchaseId});
    return {
      ok: true,
      alreadyProcessed: true,
      purchase: purchase.exists ? purchasePayload(purchase.data() ?? {}, decision.purchaseId) : null,
      wallet: walletPayload(Number(wallet.data()?.balance ?? 0)),
      boost: null,
    };
  }

  const purchaseId = decision.purchaseId;
  const store = decision.store;
  const now = new Date();

  const result = await db.runTransaction(async (tx) => {
    const purchaseRef = db.doc(`purchases/${purchaseId}`);
    const again = await tx.get(purchaseRef);
    const walletSnap = await tx.get(walletRef);
    const currentBalance = Number(walletSnap.data()?.balance ?? 0);
    if (again.exists && again.data()?.status === "verified") {
      return {
        alreadyProcessed: true as const,
        balance: currentBalance,
        boostCount: Number(again.data()?.boostCount ?? pack?.boostCount ?? 0),
      };
    }
    const plan = credit.credit({
      boostCount: pack!.boostCount,
      currentBalance,
      alreadyCredited: false,
    });
    if ("invalidPack" in plan) {
      return {invalidPack: true as const};
    }
    tx.set(purchaseRef, {
      purchaseId,
      userId: uid,
      productId: payload.productId,
      boostCount: plan.added,
      platform: payload.platform,
      transactionId: store.transactionId,
      purchaseTokenHashOrReference: store.purchaseTokenHashOrReference ?? null,
      status: "verified",
      purchasedAt: Timestamp.fromDate(store.purchasedAt ?? now),
      verifiedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      walletRef,
      {
        balance: plan.balance,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return {credited: true as const, balance: plan.balance, boostCount: plan.added};
  });

  if ("invalidPack" in result) {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }

  logger.info("boost_credited", {
    userId: uid,
    purchaseId,
    productId: payload.productId,
    boostCount: result.boostCount,
  });
  return {
    ok: true,
    alreadyProcessed: "alreadyProcessed" in result,
    purchase: {
      purchaseId,
      userId: uid,
      productId: payload.productId,
      boostCount: result.boostCount,
      status: "verified",
      platform: payload.platform,
      transactionId: store.transactionId,
    },
    wallet: walletPayload(result.balance),
    boost: null,
  };
});

export const activateBoost = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const db = getFirestore();
  const now = new Date();
  const walletRef = db.doc(walletDocPath(uid));
  const result = await db.runTransaction(async (tx) => {
    const walletSnap = await tx.get(walletRef);
    const balance = Number(walletSnap.data()?.balance ?? 0);
    const activeSnap = await tx.get(db.collection(`users/${uid}/boosts`).where("status", "==", "active"));
    for (const doc of activeSnap.docs) {
      const expires = doc.data().expiresAt as Timestamp | undefined;
      if (expires && expires.toMillis() <= now.getTime()) {
        tx.update(doc.ref, {status: "expired"});
      }
    }
    const currentActive = activation.activeBoost(toSnapshots(uid, activeSnap.docs), now);
    const plan = activation.decide({now, currentActive, balance});
    if ("alreadyActive" in plan) {
      return {alreadyActive: true as const};
    }
    if ("insufficientBalance" in plan) {
      return {insufficientBalance: true as const};
    }
    const boostRef = db.collection(`users/${uid}/boosts`).doc();
    tx.set(walletRef, {balance: balance - 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    tx.set(boostRef, {
      boostId: boostRef.id,
      userId: uid,
      productId: "activate",
      purchaseId: null,
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(plan.expiresAt),
      createdAt: FieldValue.serverTimestamp(),
    });
    return {activated: true as const, boostId: boostRef.id, expiresAt: plan.expiresAt, startedAt: plan.startedAt, balance: balance - 1};
  });

  if ("alreadyActive" in result) {
    throw new HttpsError("failed-precondition", "already-active", {reason: "already-active"});
  }
  if ("insufficientBalance" in result) {
    throw new HttpsError("failed-precondition", "insufficient-balance", {reason: "insufficient-balance"});
  }

  const created = await db.doc(`users/${uid}/boosts/${result.boostId}`).get();
  logger.info("boost_activated", {userId: uid, boostId: result.boostId});
  await sendUserPush({
    uid,
    type: FcmTypes.boostActivated,
    data: {boostId: result.boostId},
    prefKey: "notificationsEnabled",
  });
  return {
    ok: true,
    wallet: walletPayload(result.balance),
    boost: created.exists
      ? boostPayload(created.data() ?? {}, result.boostId)
      : {
          boostId: result.boostId,
          userId: uid,
          productId: "activate",
          purchaseId: null,
          status: "active",
          startedAt: result.startedAt.toISOString(),
          expiresAt: result.expiresAt.toISOString(),
        },
  };
});

export const expireBoost = onSchedule(
  {schedule: "every 15 minutes", region: "europe-west1"},
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const snap = await db.collectionGroup("boosts").where("status", "==", "active").get();
    const expiredDocs: Array<{uid: string; boostId: string}> = [];
    const batch = db.batch();
    for (const doc of snap.docs) {
      const expires = doc.data().expiresAt as Timestamp | undefined;
      if (expires && expires.toMillis() <= now.toMillis()) {
        batch.update(doc.ref, {status: "expired"});
        expiredDocs.push({uid: String(doc.data().userId ?? ""), boostId: doc.id});
        logger.info("boost_expired", {userId: doc.data().userId, boostId: doc.id});
      }
    }
    if (expiredDocs.length) {
      await batch.commit();
      for (const item of expiredDocs) {
        if (!item.uid) {
          continue;
        }
        await sendUserPush({
          uid: item.uid,
          type: FcmTypes.boostExpired,
          data: {boostId: item.boostId},
          prefKey: "notificationsEnabled",
        });
      }
    }
  },
);
