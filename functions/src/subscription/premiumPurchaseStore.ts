/**
 * Entitlement persistence for the purchase path.
 *
 * The ordinary `FirestoreEntitlementStore` only touches the subscription
 * document. A store purchase additionally has to claim the purchase token, and
 * the two writes must commit together: if the claim and the entitlement write
 * were separate transactions, two devices restoring the same purchase at once
 * could both see an unclaimed token and both write Premium, and a crash
 * between them could grant an entitlement nobody owns.
 *
 * Ownership conflicts abort the whole transaction, so a token that belongs to
 * another account writes nothing at all.
 */
import {
  FieldValue,
  getFirestore,
  type Firestore,
} from "firebase-admin/firestore";
import type {EntitlementPersistence} from "./entitlementWriter.js";
import type {CanonicalSubscription} from "./types.js";
import {
  fromDocument,
  subscriptionDocPath,
  toDocument,
} from "./firestoreEntitlementStore.js";
import {ownershipRef, purchaseTokenKey} from "./purchaseOwnership.js";

/** Thrown when the token is already owned by a different account. */
export class PurchaseOwnershipConflict extends Error {
  constructor(readonly ownerUserId: string) {
    super("purchase token is owned by another account");
    this.name = "PurchaseOwnershipConflict";
  }
}

export interface PremiumPurchaseStoreInput {
  userId: string;
  purchaseToken: string;
  platform: "android" | "ios";
  productId: string;
  /** Token this purchase supersedes, when the store reports one. */
  linkedPurchaseToken?: string | null;
}

export class PremiumPurchaseStore implements EntitlementPersistence {
  constructor(
    private readonly input: PremiumPurchaseStoreInput,
    private readonly db: Firestore = getFirestore(),
  ) {}

  async transact(
    userId: string,
    mutate: (
      current: CanonicalSubscription | null,
    ) => CanonicalSubscription | null,
  ): Promise<CanonicalSubscription> {
    const db = this.db;
    const tokenRef = ownershipRef(db, this.input.purchaseToken);
    const linkedRef = this.input.linkedPurchaseToken
      ? ownershipRef(db, this.input.linkedPurchaseToken)
      : null;
    const subRef = db.doc(subscriptionDocPath(userId));

    return db.runTransaction(async (tx) => {
      // Every read happens before any write: Firestore rejects a transaction
      // that reads after it writes.
      const [tokenSnap, linkedSnap, subSnap] = await Promise.all([
        tx.get(tokenRef),
        linkedRef ? tx.get(linkedRef) : Promise.resolve(null),
        tx.get(subRef),
      ]);

      const existingOwner = tokenSnap.exists
        ? String(tokenSnap.data()?.userId ?? "")
        : "";
      if (existingOwner && existingOwner !== this.input.userId) {
        throw new PurchaseOwnershipConflict(existingOwner);
      }

      // An upgrade, downgrade or re-signup issues a fresh token that supersedes
      // an old one. The new token is unclaimed, so without this a different
      // account could claim it and take over a subscription someone else pays
      // for.
      if (!existingOwner && linkedSnap?.exists) {
        const linkedOwner = String(linkedSnap.data()?.userId ?? "");
        if (linkedOwner && linkedOwner !== this.input.userId) {
          throw new PurchaseOwnershipConflict(linkedOwner);
        }
      }

      const current = fromDocument(userId, subSnap.data());
      const next = mutate(current);

      if (next) {
        tx.set(subRef, toDocument(next), {merge: true});
      }

      if (tokenSnap.exists) {
        tx.set(
          tokenRef,
          {productId: this.input.productId, lastSeenAt: FieldValue.serverTimestamp()},
          {merge: true},
        );
      } else {
        tx.set(tokenRef, {
          userId: this.input.userId,
          platform: this.input.platform,
          productId: this.input.productId,
          linkedFromKey: this.input.linkedPurchaseToken
            ? purchaseTokenKey(this.input.linkedPurchaseToken)
            : null,
          claimedAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
        });
      }

      return next ?? current ?? ({userId} as CanonicalSubscription);
    });
  }
}
