/**
 * A Boost purchase that Google Play voided — refunded, charged back, revoked.
 *
 * The member keeps what they have already used and loses what they have not:
 * the part of a time-boxed Boost that still lies ahead, or the wallet credits
 * that are still there. The ledger entry stays, marked voided, so the token
 * can never be granted again and the entry itself records what was taken back.
 *
 * Voiding is idempotent. Play delivers a notification at least once and the
 * Voided Purchases sweep sees the same purchase every day for a month, so an
 * entry that is already voided is left exactly as the first void wrote it.
 */
import {
  FieldValue,
  Timestamp,
  type DocumentData,
  type DocumentReference,
  type Firestore,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {BoostActivationService} from "./boostActivationService.js";
import {purchaseDocId, walletDocPath} from "./config.js";
import {sha256} from "./hash.js";
import type {ActiveBoostSnapshot} from "./types.js";

/** How Mevora learned that Play voided the purchase. */
export type BoostVoidSource = "rtdn_voided" | "rtdn_one_time_canceled" | "voided_purchases_api";

export interface BoostVoidInput {
  /** The Play purchase token. Hashed to find the ledger entry; never stored. */
  purchaseToken: string;
  source: BoostVoidSource;
  orderId?: string | null;
  /** When Play says the purchase was voided. */
  voidedAt?: Date | null;
  /** Play's `voidedReason` and `voidedSource`, where the source reports them. */
  voidedReason?: number | null;
  voidedSource?: number | null;
  now?: Date;
}

export interface VoidedLedgerEntry {
  purchaseId: string;
  userId: string;
  outcome: "voided" | "alreadyVoided";
  revokedDurationMs: number;
  revokedCredits: number;
}

export interface BoostVoidResult {
  /** `notFound`: the token never bought a Boost here, so there is nothing to take back. */
  outcome: "voided" | "alreadyVoided" | "notFound";
  entries: VoidedLedgerEntry[];
}

/** Entries written before the token became the ledger key; a replayed token could leave several. */
const LEGACY_LEDGER_SCAN = 10;

const activation = new BoostActivationService();

export async function voidBoostPurchase(db: Firestore, input: BoostVoidInput): Promise<BoostVoidResult> {
  const entries: VoidedLedgerEntry[] = [];
  for (const ref of await ledgerEntriesFor(db, input.purchaseToken)) {
    const entry = await voidLedgerEntry(db, ref, input);
    if (entry) {
      entries.push(entry);
    }
  }
  if (entries.length === 0) {
    return {outcome: "notFound", entries};
  }
  return {outcome: entries.some((entry) => entry.outcome === "voided") ? "voided" : "alreadyVoided", entries};
}

/**
 * The ledger entries this token was granted under: the one keyed by its hash,
 * or, for a grant older than that key, every entry that carries the hash.
 */
async function ledgerEntriesFor(db: Firestore, purchaseToken: string): Promise<DocumentReference[]> {
  if (!purchaseToken) {
    return [];
  }
  const hash = sha256(purchaseToken);
  const direct = db.doc(`purchases/${purchaseDocId("android", hash)}`);
  if ((await direct.get()).exists) {
    return [direct];
  }
  const legacy = await db
    .collection("purchases")
    .where("purchaseTokenHashOrReference", "==", hash)
    .limit(LEGACY_LEDGER_SCAN)
    .get();
  return legacy.docs.map((doc) => doc.ref);
}

async function voidLedgerEntry(
  db: Firestore,
  ref: DocumentReference,
  input: BoostVoidInput,
): Promise<VoidedLedgerEntry | null> {
  const entry = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return null;
    }
    const data = snap.data() ?? {};
    const userId = String(data.userId ?? "");
    if (data.status === "voided") {
      return {purchaseId: ref.id, userId, outcome: "alreadyVoided" as const, revokedDurationMs: 0, revokedCredits: 0};
    }

    const now = input.now ?? Timestamp.now().toDate();
    // Only a verified entry ever granted anything.
    const granted = data.status === "verified" && userId !== "";
    const credits = granted ? wholeNumber(data.boostCount) : 0;
    // A count pack carries a duration too (how long one activation lasts); it
    // paid for credits, not for time.
    const durationMs = granted && credits === 0 ? Math.max(0, Number(data.durationMs ?? 0) || 0) : 0;

    const walletRef = granted ? db.doc(walletDocPath(userId)) : null;
    const walletSnap = walletRef && credits > 0 ? await tx.get(walletRef) : null;
    const activeSnap =
      durationMs > 0 ? await tx.get(db.collection(`users/${userId}/boosts`).where("status", "==", "active")) : null;

    let revokedCredits = 0;
    let balanceBefore: number | null = null;
    let balanceAfter: number | null = null;
    if (walletRef && walletSnap) {
      // Credits already spent are gone; the wallet stops at zero.
      balanceBefore = wholeNumber(walletSnap.data()?.balance);
      revokedCredits = Math.min(credits, balanceBefore);
      balanceAfter = balanceBefore - revokedCredits;
      if (revokedCredits > 0) {
        tx.set(walletRef, {balance: balanceAfter, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      }
    }

    let revokedDurationMs = 0;
    let boostId: string | null = null;
    let boostEnded = false;
    let boostExpiresAtBefore: Timestamp | null = null;
    let boostExpiresAtAfter: Timestamp | null = null;
    if (activeSnap) {
      const live = activation.activeBoost(
        activeSnap.docs.map((doc) => boostSnapshot(userId, doc.id, doc.data())),
        now,
      );
      revokedDurationMs = live?.expiresAt
        ? unusedDurationMs({data, durationMs, live, expiresAt: live.expiresAt, now})
        : 0;
      if (live?.expiresAt && revokedDurationMs > 0) {
        const endsAt = new Date(live.expiresAt.getTime() - revokedDurationMs);
        boostId = live.boostId;
        boostEnded = endsAt.getTime() <= now.getTime();
        boostExpiresAtBefore = Timestamp.fromDate(live.expiresAt);
        boostExpiresAtAfter = Timestamp.fromDate(boostEnded ? now : endsAt);
        tx.update(db.doc(`users/${userId}/boosts/${live.boostId}`), {
          expiresAt: boostExpiresAtAfter,
          updatedAt: FieldValue.serverTimestamp(),
          ...(boostEnded ? {status: "cancelled", endedReason: "purchase_voided"} : {}),
        });
      }
    }

    tx.update(ref, {
      status: "voided",
      voidedAt: FieldValue.serverTimestamp(),
      // The audit record: who said so, and exactly what was taken back.
      void: {
        source: input.source,
        orderId: input.orderId ?? null,
        storeVoidedAt: input.voidedAt ? Timestamp.fromDate(input.voidedAt) : null,
        voidedReason: input.voidedReason ?? null,
        voidedSource: input.voidedSource ?? null,
        statusBefore: String(data.status ?? ""),
        revokedDurationMs,
        revokedCredits,
        boostId,
        boostEnded,
        boostExpiresAtBefore,
        boostExpiresAtAfter,
        balanceBefore,
        balanceAfter,
      },
    });
    return {
      purchaseId: ref.id,
      userId,
      outcome: "voided" as const,
      revokedDurationMs,
      revokedCredits,
      boostId,
      boostEnded,
    };
  });

  if (entry?.outcome === "voided") {
    logger.info("boost_purchase_voided", {
      userId: entry.userId,
      purchaseId: entry.purchaseId,
      source: input.source,
      revokedDurationMs: entry.revokedDurationMs,
      revokedCredits: entry.revokedCredits,
      boostId: entry.boostId,
      boostEnded: entry.boostEnded,
    });
  }
  return entry;
}

/**
 * How much of the running Boost this purchase paid for and has not been used.
 *
 * Purchases stack: each one extends the running Boost, so its time is the
 * stretch that ends where the Boost ended right after the grant. What is still
 * ahead of `now` in that stretch is unused — never more than the purchase
 * bought, and never more than the Boost has left, so a Boost cannot end
 * before now and time other purchases paid for is kept.
 */
function unusedDurationMs(params: {
  data: DocumentData;
  durationMs: number;
  live: ActiveBoostSnapshot;
  expiresAt: Date;
  now: Date;
}): number {
  const {data, durationMs, live, expiresAt, now} = params;
  // The Boost this purchase extended has ended; the one running now was paid
  // for by something else.
  if (typeof data.boostId === "string" && data.boostId !== live.boostId) {
    return 0;
  }
  const paidUntil = paidUntilMs(data, durationMs);
  if (paidUntil === null) {
    return 0;
  }
  const remainingMs = expiresAt.getTime() - now.getTime();
  return Math.max(0, Math.min(durationMs, paidUntil - now.getTime(), remainingMs));
}

/**
 * Where this purchase's time ends. A grant records it; an entry older than
 * that is assumed to have started the day it was verified, which undercounts a
 * stacked purchase rather than taking time it cannot account for.
 */
function paidUntilMs(data: DocumentData, durationMs: number): number | null {
  if (data.boostExpiresAt instanceof Timestamp) {
    return data.boostExpiresAt.toMillis();
  }
  const grantedAt = [data.verifiedAt, data.purchasedAt, data.createdAt].find((value) => value instanceof Timestamp);
  return grantedAt ? (grantedAt as Timestamp).toMillis() + durationMs : null;
}

function boostSnapshot(userId: string, boostId: string, data: DocumentData): ActiveBoostSnapshot {
  return {
    boostId,
    userId,
    status: data.status,
    startedAt: (data.startedAt as Timestamp | undefined)?.toDate() ?? null,
    expiresAt: (data.expiresAt as Timestamp | undefined)?.toDate() ?? null,
  };
}

/** A stored count as a whole number that is never negative. */
function wholeNumber(value: unknown): number {
  const parsed = Math.floor(Number(value ?? 0));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}
