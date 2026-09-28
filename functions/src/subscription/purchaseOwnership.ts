/**
 * Purchase-token ownership ledger.
 *
 * One store purchase must grant Premium to exactly one Mevora account. Without
 * this, the same Play purchase token could be replayed by any number of
 * accounts and each would be verified as genuine by Google — the token really
 * is valid, it just does not belong to them.
 *
 * Ownership is keyed by the purchase token, not by an order id: Google rotates
 * the order id on every renewal, so an order-keyed ledger would treat each
 * renewal as a fresh unclaimed purchase.
 *
 * Tokens are hashed before they become document ids. A raw Play token is a
 * bearer credential for the purchase; it must not sit in a document path that
 * appears in logs, metrics or an index.
 */
import {createHash} from "node:crypto";
import {
  FieldValue,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";

export const OWNERSHIP_COLLECTION = "subscriptionPurchases";

export function purchaseTokenKey(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export type OwnershipOutcome =
  /** This user now owns the token (first claim). */
  | "claimed"
  /** This user already owned it; a renewal or a repeated restore. */
  | "already_owner"
  /** Someone else owns it — the caller must not be granted anything. */
  | "owned_by_other";

export interface OwnershipRecord {
  userId: string;
  platform: "android" | "ios";
  productId: string;
  /** Set when Google reports this token superseded an earlier one. */
  linkedFromKey?: string | null;
}

export interface ClaimResult {
  outcome: OwnershipOutcome;
  ownerUserId: string;
}

/**
 * Claims a purchase token for a user inside `tx`.
 *
 * Runs in the caller's transaction so the claim and the entitlement write
 * commit together: two devices racing the same restore cannot both observe an
 * unclaimed token and both write Premium.
 */
export function claimPurchaseTokenTx(
  tx: Transaction,
  db: Firestore,
  input: {
    token: string;
    userId: string;
    platform: "android" | "ios";
    productId: string;
    linkedPurchaseToken?: string | null;
  },
  existing: FirebaseFirestore.DocumentSnapshot,
): ClaimResult {
  const ref = db.doc(`${OWNERSHIP_COLLECTION}/${purchaseTokenKey(input.token)}`);

  if (existing.exists) {
    const ownerUserId = String(existing.data()?.userId ?? "");
    if (ownerUserId && ownerUserId !== input.userId) {
      return {outcome: "owned_by_other", ownerUserId};
    }
    tx.set(
      ref,
      {
        productId: input.productId,
        lastSeenAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return {outcome: "already_owner", ownerUserId: input.userId};
  }

  tx.set(ref, {
    userId: input.userId,
    platform: input.platform,
    productId: input.productId,
    linkedFromKey: input.linkedPurchaseToken
      ? purchaseTokenKey(input.linkedPurchaseToken)
      : null,
    claimedAt: FieldValue.serverTimestamp(),
    lastSeenAt: FieldValue.serverTimestamp(),
  });
  return {outcome: "claimed", ownerUserId: input.userId};
}

/** Document reference for a token, for the caller's pre-transaction read. */
export function ownershipRef(db: Firestore, token: string) {
  return db.doc(`${OWNERSHIP_COLLECTION}/${purchaseTokenKey(token)}`);
}

/**
 * Decides whether a replacement token may inherit an existing owner.
 *
 * Upgrades, downgrades and re-signups issue a new token that supersedes an old
 * one through `linkedPurchaseToken`. The new token is unclaimed, so a naive
 * ledger would let a different account claim it and take over a subscription
 * someone else is paying for. Inheriting the previous owner closes that.
 */
export function resolveInheritedOwner(input: {
  linkedOwnerUserId: string | null;
  claimantUserId: string;
}): "inherit_ok" | "owned_by_other" | "no_link" {
  if (!input.linkedOwnerUserId) {
    return "no_link";
  }
  return input.linkedOwnerUserId === input.claimantUserId
    ? "inherit_ok"
    : "owned_by_other";
}
