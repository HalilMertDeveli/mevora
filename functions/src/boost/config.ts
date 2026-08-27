const DAY_MS = 24 * 60 * 60 * 1000;
const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

export const BOOST_DURATION_MS = 7 * DAY_MS;
export const LEGACY_DURATION_MS = 30 * MINUTE_MS;
/** Controlled visibility lift among eligible candidates only. */
export const SMART_BOOST_MULTIPLIER = Number(
  process.env.SMART_BOOST_MULTIPLIER ?? 1.25,
);
export const BOOST_RANK_BONUS = 1000;
export const ALLOW_STACKING = true;

export const BOOST_PRODUCT_IDS = {
  /** Starter — 30 minutes */
  starter30m: "mevora_smart_boost_30m",
  /** Popular — 1 hour */
  popular1h: "mevora_smart_boost_1h",
  /** Power — 24 hours */
  power24h: "mevora_smart_boost_24h",
  week: "mevora_boost_7_days",
  month: "mevora_boost_1_month",
  year: "mevora_boost_1_year",
} as const;

export const SMART_BOOST_DURATION_MS = {
  starter30m: 30 * MINUTE_MS,
  popular1h: HOUR_MS,
  power24h: 24 * HOUR_MS,
} as const;

export const BOOST_PRODUCTS = {
  iosProductId:
    process.env.BOOST_IOS_PRODUCT_ID ?? BOOST_PRODUCT_IDS.starter30m,
  androidProductId:
    process.env.BOOST_ANDROID_PRODUCT_ID ?? BOOST_PRODUCT_IDS.starter30m,
  durationMs: Number(
    process.env.BOOST_DURATION_MS ?? SMART_BOOST_DURATION_MS.starter30m,
  ),
  bundleId: process.env.IOS_BUNDLE_ID ?? "com.mevora.app",
  androidPackageName: process.env.ANDROID_PACKAGE_NAME ?? "com.mevora.app",
  displayOrder: Number(process.env.BOOST_DISPLAY_ORDER ?? 0),
} as const;

export function productIdFor(platform: "ios" | "android"): string {
  return platform === "ios"
    ? BOOST_PRODUCTS.iosProductId
    : BOOST_PRODUCTS.androidProductId;
}

export {isAllowedProduct} from "./catalog.js";

export function purchaseDocId(
  platform: "ios" | "android",
  transactionId: string,
): string {
  return `${platform}_${transactionId}`;
}

export function walletDocPath(uid: string): string {
  return `users/${uid}/boostWallet/current`;
}
