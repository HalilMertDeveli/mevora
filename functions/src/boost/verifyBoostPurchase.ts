import {FieldValue, Timestamp, getFirestore, type DocumentData, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {ApplePurchaseVerifier} from "./applePurchaseVerifier.js";
import {BoostActivationService} from "./boostActivationService.js";
import {GooglePurchaseVerifier} from "./googlePurchaseVerifier.js";
import {PurchaseVerificationService} from "./purchaseVerificationService.js";
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

  const decision = await verification.verify({uid, request: payload, existing});
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
  if (decision.outcome === "alreadyProcessed") {
    const boosts = await db
      .collection(`users/${uid}/boosts`)
      .where("purchaseId", "==", decision.purchaseId)
      .limit(1)
      .get();
    const doc = boosts.docs[0];
    return {
      ok: true,
      alreadyProcessed: true,
      boost: doc ? boostPayload(doc.data(), doc.id) : null,
    };
  }

  const purchaseId = decision.purchaseId;
  const store = decision.store;
  const boostId = purchaseId;
  const now = new Date();

  const result = await db.runTransaction(async (tx) => {
    const purchaseRef = db.doc(`purchases/${purchaseId}`);
    const again = await tx.get(purchaseRef);
    if (again.exists && again.data()?.status === "verified") {
      return {alreadyProcessed: true as const};
    }
    const activeSnap = await tx.get(db.collection(`users/${uid}/boosts`).where("status", "==", "active"));
    const currentActive = activation.activeBoost(toSnapshots(uid, activeSnap.docs), now);
    const plan = activation.decide({now, currentActive});

    tx.set(purchaseRef, {
      purchaseId,
      userId: uid,
      productId: payload.productId,
      platform: payload.platform,
      transactionId: store.transactionId,
      purchaseTokenHashOrReference: store.purchaseTokenHashOrReference ?? null,
      status: "verified",
      purchasedAt: Timestamp.fromDate(store.purchasedAt ?? now),
      verifiedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    });

    if (!plan.shouldActivate) {
      return {alreadyActive: true as const};
    }

    const boostRef = db.doc(`users/${uid}/boosts/${boostId}`);
    tx.set(boostRef, {
      boostId,
      userId: uid,
      productId: payload.productId,
      purchaseId,
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(plan.expiresAt),
      createdAt: FieldValue.serverTimestamp(),
    });
    return {activated: true as const, expiresAt: plan.expiresAt, startedAt: plan.startedAt};
  });

  if ("alreadyProcessed" in result) {
    const boosts = await db.collection(`users/${uid}/boosts`).where("purchaseId", "==", purchaseId).limit(1).get();
    const doc = boosts.docs[0];
    return {ok: true, alreadyProcessed: true, boost: doc ? boostPayload(doc.data(), doc.id) : null};
  }
  if ("alreadyActive" in result) {
    throw new HttpsError("failed-precondition", "already-active", {reason: "already-active"});
  }

  const created = await db.doc(`users/${uid}/boosts/${boostId}`).get();
  logger.info("boost_activated", {userId: uid, boostId, productId: payload.productId});
  await sendUserPush({
    uid,
    type: FcmTypes.boostActivated,
    data: {boostId},
    prefKey: "notificationsEnabled",
  });
  return {
    ok: true,
    boost: created.exists
      ? boostPayload(created.data() ?? {}, boostId)
      : {
          boostId,
          userId: uid,
          productId: payload.productId,
          purchaseId,
          status: "active",
          startedAt: result.startedAt.toISOString(),
          expiresAt: result.expiresAt.toISOString(),
        },
  };
});

export const activateBoost = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const purchaseId = String(request.data?.purchaseId ?? "");
  if (!purchaseId) {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }
  const db = getFirestore();
  const purchaseRef = db.doc(`purchases/${purchaseId}`);
  const purchase = await purchaseRef.get();
  const data = purchase.data();
  if (!purchase.exists || data?.userId !== uid || data?.status !== "verified") {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }
  const now = new Date();
  const result = await db.runTransaction(async (tx) => {
    const existing = await tx.get(db.collection(`users/${uid}/boosts`).where("purchaseId", "==", purchaseId).limit(1));
    if (!existing.empty) {
      return {alreadyProcessed: true as const, boostId: existing.docs[0].id};
    }
    const activeSnap = await tx.get(db.collection(`users/${uid}/boosts`).where("status", "==", "active"));
    const currentActive = activation.activeBoost(toSnapshots(uid, activeSnap.docs), now);
    const plan = activation.decide({now, currentActive});
    if (!plan.shouldActivate) {
      return {alreadyActive: true as const};
    }
    const boostId = purchaseId;
    tx.set(db.doc(`users/${uid}/boosts/${boostId}`), {
      boostId,
      userId: uid,
      productId: String(data?.productId ?? ""),
      purchaseId,
      status: "active",
      startedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromDate(plan.expiresAt),
      createdAt: FieldValue.serverTimestamp(),
    });
    return {activated: true as const, boostId, expiresAt: plan.expiresAt};
  });
  if ("alreadyActive" in result) {
    throw new HttpsError("failed-precondition", "already-active", {reason: "already-active"});
  }
  const created = await db.doc(`users/${uid}/boosts/${result.boostId}`).get();
  if ("activated" in result) {
    await sendUserPush({
      uid,
      type: FcmTypes.boostActivated,
      data: {boostId: result.boostId},
      prefKey: "notificationsEnabled",
    });
  }
  return {ok: true, boost: created.exists ? boostPayload(created.data() ?? {}, result.boostId) : null};
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

