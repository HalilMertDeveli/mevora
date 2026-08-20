export const BOOST_DURATION_MS = 30 * 60 * 1000;
export const BOOST_RANK_BONUS = 1000;
export const ALLOW_STACKING = false;

export const BOOST_PRODUCTS = {
  iosProductId: process.env.BOOST_IOS_PRODUCT_ID ?? "com.mevora.app.boost",
  androidProductId: process.env.BOOST_ANDROID_PRODUCT_ID ?? "com.mevora.app.boost",
  durationMs: Number(process.env.BOOST_DURATION_MS ?? BOOST_DURATION_MS),
  bundleId: process.env.IOS_BUNDLE_ID ?? "com.mevora.app",
  androidPackageName: process.env.ANDROID_PACKAGE_NAME ?? "com.mevora.app",
  displayOrder: Number(process.env.BOOST_DISPLAY_ORDER ?? 0),
} as const;

export function productIdFor(platform: "ios" | "android"): string {
  return platform === "ios" ? BOOST_PRODUCTS.iosProductId : BOOST_PRODUCTS.androidProductId;
}

export {isAllowedProduct} from "./catalog.js";

export function purchaseDocId(platform: "ios" | "android", transactionId: string): string {
  return `${platform}_${transactionId}`;
}

export function walletDocPath(uid: string): string {
  return `users/${uid}/boostWallet/current`;
}
