import {purchaseDocId} from "./config.js";
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

    const purchaseId = purchaseDocId(platform, request.transactionId);
    if (existing) {
      if (existing.userId !== uid) {
        return {outcome: "duplicateOtherUser", purchaseId};
      }
      if (existing.status === "verified") {
        return {outcome: "alreadyProcessed", purchaseId};
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
}
