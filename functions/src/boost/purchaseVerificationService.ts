import {purchaseDocId} from "./config.js";
import {sha256} from "./hash.js";
import type {BoostPack} from "./catalog.js";
import type {ApplePurchaseVerifier} from "./applePurchaseVerifier.js";
import type {GooglePurchaseVerifier} from "./googlePurchaseVerifier.js";
import type {
  PurchaseLedger,
  StorePlatform,
  StoreVerificationResult,
  VerifyBoostRequest,
} from "./types.js";

export type VerificationDecision =
  | {outcome: "proceed"; purchaseId: string; store: StoreVerificationResult}
  | {outcome: "alreadyProcessed"; purchaseId: string}
  | {outcome: "invalidProduct"}
  | {outcome: "invalidUid"}
  | {outcome: "invalidTransaction"}
  | {outcome: "duplicateOtherUser"; purchaseId: string}
  | {outcome: "storeInvalid"}
  | {outcome: "storeUnavailable"};

export class PurchaseVerificationService {
  constructor(
    private readonly apple: ApplePurchaseVerifier,
    private readonly google: GooglePurchaseVerifier,
  ) {}

  async verify(params: {
    uid: string;
    request: VerifyBoostRequest;
    pack?: BoostPack | null;
    existing?: PurchaseLedger | null;
  }): Promise<VerificationDecision> {
    const {uid, request, existing, pack} = params;
    if (!uid.trim()) {
      return {outcome: "invalidUid"};
    }
    if (!request.transactionId?.trim()) {
      return {outcome: "invalidTransaction"};
    }
    const platform: StorePlatform = request.platform === "ios" ? "ios" : "android";
    if (!pack || pack.productId !== request.productId || (pack.durationMs < 1 && pack.boostCount < 1)) {
      return {outcome: "invalidProduct"};
    }

    const purchaseId = purchaseLedgerId(request);
    if (!purchaseId) {
      return {outcome: "invalidTransaction"};
    }
    if (existing) {
      if (existing.userId !== uid) {
        return {outcome: "duplicateOtherUser", purchaseId: existing.purchaseId};
      }
      if (existing.status === "verified") {
        return {outcome: "alreadyProcessed", purchaseId: existing.purchaseId};
      }
    }

    const store =
      platform === "ios" ? await this.apple.verify(request) : await this.google.verify(request);
    if (!store.ok) {
      return {outcome: store.error === "unavailable" ? "storeUnavailable" : "storeInvalid"};
    }
    if (store.productId !== request.productId) {
      return {outcome: "invalidProduct"};
    }
    return {outcome: "proceed", purchaseId, store};
  }

  /**
   * Consumes the store purchase behind a grant that is already on the ledger.
   * Resolves to whether the store confirmed it; never throws.
   */
  async consume(request: VerifyBoostRequest): Promise<boolean> {
    // An App Store consumable is finished by the client; there is nothing to do here.
    return request.platform === "android" ? this.google.consume(request) : false;
  }
}

/**
 * The ledger identity of a store purchase: `purchases/{id}`.
 *
 * On Android it is the hash of the Play purchase token — the one value Google
 * verifies and that a client cannot vary. The transaction id in the request is
 * whatever the client chose to send, so keying on it let one token be granted
 * once per invented id. On iOS the transaction id is the identity itself: the
 * App Store is asked for exactly that transaction.
 */
export function purchaseLedgerId(request: VerifyBoostRequest): string | null {
  if (request.platform === "ios") {
    return request.transactionId?.trim() ? purchaseDocId("ios", request.transactionId) : null;
  }
  return request.purchaseToken ? purchaseDocId("android", sha256(request.purchaseToken)) : null;
}
