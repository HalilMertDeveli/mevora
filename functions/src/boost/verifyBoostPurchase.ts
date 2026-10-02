import {FieldValue, Timestamp, getFirestore, type DocumentData, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {ApplePurchaseVerifier} from "./applePurchaseVerifier.js";
import {BoostActivationService} from "./boostActivationService.js";
import {ensureDefaultCatalog, isDurationPack, resolveBoostPack} from "./catalog.js";
import {expireDueBoosts} from "./expiry.js";
import {BoostCreditService} from "./creditService.js";
import {GooglePurchaseVerifier} from "./googlePurchaseVerifier.js";
import {PurchaseVerificationService, purchaseLedgerId} from "./purchaseVerificationService.js";
import {LEGACY_DURATION_MS, walletDocPath} from "./config.js";
import {sha256} from "./hash.js";
import type {Firestore} from "firebase-admin/firestore";
import type {ActiveBoostSnapshot, PurchaseLedger, VerifyBoostRequest} from "./types.js";
import {FcmTypes, sendUserPush} from "../notifications.js";
import {assertCallerAccountEligible} from "../accountGuard.js";
import {assertAppFeatureAvailable} from "../appOperations/appOperationsGate.js";
import {googlePlaySecrets} from "../googlePlayConfig.js";

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
    durationDays: Number(data.durationDays ?? 0),
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
    const started = data.startedAt as Timestamp | undefined;
    return {
      boostId: doc.id,
      userId: uid,
      status: data.status,
      startedAt: started?.toDate() ?? null,
      expiresAt: expires?.toDate() ?? null,
    };
  });
}

async function loadActiveBoostPayload(uid: string) {
  const db = getFirestore();
  const now = new Date();
  const snap = await db.collection(`users/${uid}/boosts`).where("status", "==", "active").get();
  const live = activation.activeBoost(toSnapshots(uid, snap.docs), now);
  if (!live) {
    return null;
  }
  const created = await db.doc(`users/${uid}/boosts/${live.boostId}`).get();
  return created.exists ? boostPayload(created.data() ?? {}, live.boostId) : null;
}

export const verifyBoostPurchase = onCall({...callableOptions, secrets: googlePlaySecrets}, async (request) => {
  const uid = requireUid(request);
  const payload = parseRequest(request.data);
  const db = getFirestore();
  return grantBoostPurchase({db, uid, payload, verification});
});

/**
 * Verifies a store purchase and grants it: once per purchase, to one account.
 *
 * The ledger entry is the proof of a grant. It is created in the same
 * transaction as the grant, under an id the client cannot choose, so a purchase
 * that comes back — a retry, a redelivery, a replay — finds it and is answered
 * from it instead of being granted again. Play consumes the purchase only
 * after that commit.
 */
export async function grantBoostPurchase(params: {
  db: Firestore;
  uid: string;
  payload: VerifyBoostRequest;
  verification: PurchaseVerificationService;
}) {
  const {db, uid, payload, verification: verifier} = params;
  await ensureDefaultCatalog(db);
  const pack = await resolveBoostPack(db, payload.productId);
  const existing = await findPurchaseLedger(db, uid, payload);

  const decision = await verifier.verify({uid, request: payload, existing, pack});
  if (decision.outcome === "invalidUid") {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  if (decision.outcome === "duplicateOtherUser") {
    logger.warn("boost_purchase_owned_by_other_account", {userId: uid, purchaseId: decision.purchaseId});
    throw purchaseAlreadyRedeemed();
  }
  if (
    decision.outcome === "invalidProduct" ||
    decision.outcome === "invalidTransaction" ||
    decision.outcome === "storeInvalid"
  ) {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }
  if (decision.outcome === "storeUnavailable") {
    throw new HttpsError("unavailable", "store-unavailable", {reason: "store-unavailable"});
  }
  if (decision.outcome === "voided") {
    logger.info("boost_purchase_voided_resubmitted", {userId: uid, purchaseId: decision.purchaseId});
    throw purchaseVoided();
  }

  const walletRef = db.doc(walletDocPath(uid));
  if (decision.outcome === "alreadyProcessed") {
    const purchase = await db.doc(`purchases/${decision.purchaseId}`).get();
    if (purchase.exists && !purchase.data()?.consumedAt) {
      // The grant landed earlier but Play never confirmed the consume. Finish
      // it, for the product on the ledger rather than the one in this request.
      await consumeGrantedPurchase(db, verifier, decision.purchaseId, {
        ...payload,
        productId: String(purchase.data()?.productId ?? payload.productId),
      });
    }
    const wallet = await walletRef.get();
    logger.info("boost_purchase_idempotent", {userId: uid, purchaseId: decision.purchaseId});
    return {
      ok: true,
      alreadyProcessed: true,
      purchase: purchase.exists ? purchasePayload(purchase.data() ?? {}, decision.purchaseId) : null,
      wallet: walletPayload(Number(wallet.data()?.balance ?? 0)),
      boost: await loadActiveBoostPayload(uid),
    };
  }

  const purchaseId = decision.purchaseId;
  const store = decision.store;
  const durationPack = pack != null && isDurationPack(pack);

  const result = await db.runTransaction(async (tx) => {
    const now = Timestamp.now().toDate();
    const purchaseRef = db.doc(`purchases/${purchaseId}`);
    const again = await tx.get(purchaseRef);
    const walletSnap = await tx.get(walletRef);
    const currentBalance = Number(walletSnap.data()?.balance ?? 0);
    if (again.exists && String(again.data()?.userId ?? "") !== uid) {
      // Another account recorded this purchase between the lookup and here.
      return {otherAccount: true as const};
    }
    if (again.exists && again.data()?.status === "verified") {
      return {
        alreadyProcessed: true as const,
        consumed: Boolean(again.data()?.consumedAt),
        balance: currentBalance,
        boostCount: Number(again.data()?.boostCount ?? pack?.boostCount ?? 0),
        boostId: null as string | null,
      };
    }
    if (again.exists && again.data()?.status === "voided") {
      // Voided between the lookup and here. Writing a grant over it would
      // undo the void.
      return {voided: true as const};
    }

    const activeSnap = await tx.get(db.collection(`users/${uid}/boosts`).where("status", "==", "active"));
    for (const doc of activeSnap.docs) {
      const expires = doc.data().expiresAt as Timestamp | undefined;
      if (expires && expires.toMillis() <= now.getTime()) {
        tx.update(doc.ref, {status: "expired"});
      }
    }

    const ledgerEntry = {
      purchaseId,
      userId: uid,
      productId: payload.productId,
      boostCount: durationPack ? 0 : pack!.boostCount,
      durationDays: pack!.durationDays,
      durationMs: pack!.durationMs,
      platform: payload.platform,
      transactionId: store.transactionId,
      purchaseTokenHashOrReference: store.purchaseTokenHashOrReference ?? null,
      status: "verified",
      purchasedAt: Timestamp.fromDate(store.purchasedAt ?? now),
      verifiedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    };

    if (!durationPack) {
      tx.set(purchaseRef, ledgerEntry);
      const plan = credit.credit({
        boostCount: pack!.boostCount,
        currentBalance,
        alreadyCredited: false,
      });
      if ("invalidPack" in plan) {
        return {invalidPack: true as const};
      }
      tx.set(
        walletRef,
        {
          balance: plan.balance,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return {credited: true as const, balance: plan.balance, boostCount: plan.added, boostId: null as string | null};
    }

    const currentActive = activation.activeBoost(toSnapshots(uid, activeSnap.docs), now);
    const grant = activation.decide({
      now,
      currentActive,
      durationMs: pack!.durationMs,
      requireBalance: false,
    });
    const boostRef = grant.shouldActivate
      ? grant.extendBoostId
        ? db.doc(`users/${uid}/boosts/${grant.extendBoostId}`)
        : db.collection(`users/${uid}/boosts`).doc()
      : null;
    // Which Boost this purchase paid for, and where its time ends. A voided
    // purchase takes back what is still ahead of that point, and nothing else.
    tx.set(
      purchaseRef,
      grant.shouldActivate && boostRef
        ? {...ledgerEntry, boostId: boostRef.id, boostExpiresAt: Timestamp.fromDate(grant.expiresAt)}
        : ledgerEntry,
    );
    if (!grant.shouldActivate || !boostRef) {
      return {invalidPack: true as const};
    }
    const boostId = boostRef.id;
    if (grant.extendBoostId) {
      tx.update(boostRef, {
        productId: payload.productId,
        purchaseId,
        status: "active",
        expiresAt: Timestamp.fromDate(grant.expiresAt),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      tx.set(boostRef, {
        boostId,
        userId: uid,
        productId: payload.productId,
        purchaseId,
        status: "active",
        startedAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromDate(grant.expiresAt),
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return {
      activated: true as const,
      balance: currentBalance,
      boostCount: 0,
      boostId,
      expiresAt: grant.expiresAt,
      startedAt: grant.startedAt,
    };
  });

  if ("otherAccount" in result) {
    logger.warn("boost_purchase_owned_by_other_account", {userId: uid, purchaseId});
    throw purchaseAlreadyRedeemed();
  }
  if ("invalidPack" in result) {
    throw new HttpsError("invalid-argument", "verification-failed", {reason: "verification-failed"});
  }
  if ("voided" in result) {
    throw purchaseVoided();
  }

  // The grant is on the ledger — written just now, or by a call that raced this
  // one. Only from here on may Play consume the purchase.
  if (!("alreadyProcessed" in result) || !result.consumed) {
    await consumeGrantedPurchase(db, verifier, purchaseId, payload);
  }

  if ("alreadyProcessed" in result) {
    logger.info("boost_purchase_idempotent", {userId: uid, purchaseId});
    return {
      ok: true,
      alreadyProcessed: true,
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
      boost: await loadActiveBoostPayload(uid),
    };
  }

  let boost = null;
  if ("activated" in result && result.boostId && result.startedAt && result.expiresAt) {
    const created = await db.doc(`users/${uid}/boosts/${result.boostId}`).get();
    boost = created.exists
      ? boostPayload(created.data() ?? {}, result.boostId)
      : {
          boostId: result.boostId,
          userId: uid,
          productId: payload.productId,
          purchaseId,
          status: "active",
          startedAt: result.startedAt.toISOString(),
          expiresAt: result.expiresAt.toISOString(),
        };
    logger.info("boost_purchase_success", {
      userId: uid,
      purchaseId,
      productId: payload.productId,
      boostId: result.boostId,
    });
    await sendUserPush({
      uid,
      type: FcmTypes.boostActivated,
      data: {boostId: result.boostId},
      prefKey: "notificationsEnabled",
    });
  } else {
    logger.info("boost_credited", {
      userId: uid,
      purchaseId,
      productId: payload.productId,
      boostCount: result.boostCount,
    });
  }

  return {
    ok: true,
    alreadyProcessed: false,
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
    boost,
  };
}

/** How many pre-token-key entries to read for one token; replays under the old key could leave several. */
const LEGACY_LEDGER_SCAN = 10;

/**
 * The ledger entry that already records this purchase, if any.
 *
 * Entries written before the token became the key sit under the transaction id
 * the client sent, but they carry the token hash, so they are found by that
 * field and still block a second grant.
 */
async function findPurchaseLedger(
  db: Firestore,
  uid: string,
  payload: VerifyBoostRequest,
): Promise<PurchaseLedger | null> {
  const purchaseId = purchaseLedgerId(payload);
  if (!purchaseId) {
    return null;
  }
  const toLedger = (id: string, data: DocumentData): PurchaseLedger => ({
    purchaseId: id,
    userId: String(data.userId ?? ""),
    productId: String(data.productId ?? ""),
    platform: payload.platform,
    transactionId: String(data.transactionId ?? ""),
    status: data.status === "verified" || data.status === "voided" ? data.status : "pending",
  });
  const direct = await db.doc(`purchases/${purchaseId}`).get();
  if (direct.exists) {
    return toLedger(direct.id, direct.data() ?? {});
  }
  if (payload.platform !== "android" || !payload.purchaseToken) {
    return null;
  }
  const legacy = await db
    .collection("purchases")
    .where("purchaseTokenHashOrReference", "==", sha256(payload.purchaseToken))
    .limit(LEGACY_LEDGER_SCAN)
    .get();
  // The caller's own entry answers a retry; anyone else's rejects the request.
  const entry = legacy.docs.find((doc) => doc.data().userId === uid) ?? legacy.docs[0];
  return entry ? toLedger(entry.id, entry.data()) : null;
}

/**
 * Consumes a purchase whose grant is on the ledger, and records that Play
 * confirmed it. A failure changes nothing for the member: the grant stands,
 * the entry keeps the token from being granted again, and the next
 * verification of the same token retries the consume.
 */
async function consumeGrantedPurchase(
  db: Firestore,
  verifier: PurchaseVerificationService,
  purchaseId: string,
  payload: VerifyBoostRequest,
): Promise<void> {
  try {
    if (await verifier.consume(payload)) {
      await db.doc(`purchases/${purchaseId}`).update({consumedAt: FieldValue.serverTimestamp()});
    }
  } catch (error) {
    logger.warn("boost_purchase_consume_not_recorded", {purchaseId, error: String(error)});
  }
}

/** A purchase that is already another account's. Says nothing about whose. */
function purchaseAlreadyRedeemed(): HttpsError {
  return new HttpsError("already-exists", "already-processed", {reason: "already-processed"});
}

/**
 * A purchase Play has since voided. The client treats any `invalid-argument`
 * as a failed verification and leaves the purchase alone, which is right: there
 * is nothing left to grant.
 */
function purchaseVoided(): HttpsError {
  return new HttpsError("invalid-argument", "purchase-voided", {reason: "purchase-voided"});
}

export const activateBoost = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const db = getFirestore();
  await assertCallerAccountEligible(db, uid);
  await assertAppFeatureAvailable(db, "boost");
  const result = await db.runTransaction(async (tx) => {
    const now = Timestamp.now().toDate();
    const walletRef = db.doc(walletDocPath(uid));
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
    const plan = activation.decide({
      now,
      currentActive,
      balance,
      durationMs: LEGACY_DURATION_MS,
      requireBalance: true,
    });
    if ("alreadyActive" in plan) {
      return {alreadyActive: true as const};
    }
    if ("insufficientBalance" in plan) {
      return {insufficientBalance: true as const};
    }
    tx.set(walletRef, {balance: balance - 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    if (plan.extendBoostId) {
      tx.update(db.doc(`users/${uid}/boosts/${plan.extendBoostId}`), {
        status: "active",
        expiresAt: Timestamp.fromDate(plan.expiresAt),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        activated: true as const,
        boostId: plan.extendBoostId,
        expiresAt: plan.expiresAt,
        startedAt: plan.startedAt,
        balance: balance - 1,
      };
    }
    const boostRef = db.collection(`users/${uid}/boosts`).doc();
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
    return {
      activated: true as const,
      boostId: boostRef.id,
      expiresAt: plan.expiresAt,
      startedAt: plan.startedAt,
      balance: balance - 1,
    };
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
    await expireDueBoosts(getFirestore(), {
      now: Timestamp.now(),
      notify: (item) =>
        sendUserPush({
          uid: item.uid,
          type: FcmTypes.boostExpired,
          data: {boostId: item.boostId},
          prefKey: "notificationsEnabled",
        }),
    });
  },
);
