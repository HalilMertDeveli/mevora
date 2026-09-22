const DAY_MS = 24 * 60 * 60 * 1000;
export const BOOST_DURATION_MS = 7 * DAY_MS;
export const LEGACY_DURATION_MS = 30 * 60 * 1000;
export const ALLOW_STACKING = true;

/**
 * The single source of Boost strength. Every ranking lever lives here so the
 * advantage can be tuned, reasoned about and measured in one place.
 *
 * Boost buys visibility among candidates who already passed every eligibility,
 * preference and safety filter. It never touches compatibility.
 */
export const BOOST_STRENGTH = {
  /**
   * How far Boost can carry a profile past a better-matched rival, in
   * compatibility points. Distance and question alignment are decided first,
   * so this is the whole of the ranking advantage: among candidates at the
   * same distance, a boosted profile outranks anyone within `priorityBonus`
   * compatibility points of it, and loses to anyone further ahead than that.
   */
  priorityBonus: 35,
  /** Boosted profiles stay eligible up to +25% beyond the viewer radius. */
  radiusExtensionRatio: 0.25,
  /**
   * Quality gate, on the 0-100 compatibility scale. Below this, Boost grants
   * nothing at all — so paying can never float a poor match past a good one.
   * This is what keeps compatibility meaningful rather than purchasable.
   */
  minCompatibility: 45,
  /**
   * Density cap: at most `maxPerWindow` boosted profiles in any
   * `densityWindow` consecutive results, so Boost buyers cannot take over a
   * page however many of them are active.
   */
  densityWindow: 3,
  maxPerWindow: 1,
} as const;

export const BOOST_PRODUCT_IDS = {
  week: "mevora_boost_7_days",
  month: "mevora_boost_1_month",
  year: "mevora_boost_1_year",
} as const;

export const BOOST_PRODUCTS = {
  iosProductId: process.env.BOOST_IOS_PRODUCT_ID ?? BOOST_PRODUCT_IDS.week,
  androidProductId: process.env.BOOST_ANDROID_PRODUCT_ID ?? BOOST_PRODUCT_IDS.week,
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
