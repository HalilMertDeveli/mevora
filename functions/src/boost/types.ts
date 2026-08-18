export type StorePlatform = "ios" | "android";

export interface VerifyBoostRequest {
  platform: StorePlatform;
  productId: string;
  transactionId: string;
  purchaseToken?: string;
  signedTransaction?: string;
  receiptData?: string;
}

export interface StoreVerificationResult {
  ok: boolean;
  productId: string;
  transactionId: string;
  originalTransactionId?: string;
  purchaseTokenHashOrReference?: string;
  purchasedAt?: Date;
  error?: "invalid" | "unavailable";
}

export interface PurchaseLedger {
  purchaseId: string;
  userId: string;
  productId: string;
  platform: StorePlatform;
  transactionId: string;
  status: "pending" | "verified" | "failed";
}

export interface ActiveBoostSnapshot {
  boostId: string;
  userId: string;
  status: "pending" | "active" | "expired" | "cancelled";
  expiresAt: Date | null;
}

export interface VerifiedPurchasePayload {
  uid: string;
  platform: StorePlatform;
  productId: string;
  transactionId: string;
  purchaseTokenHashOrReference?: string;
  purchasedAt: Date;
}
