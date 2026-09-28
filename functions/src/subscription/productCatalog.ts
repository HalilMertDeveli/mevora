/**
 * Premium subscription product catalogue.
 *
 * Fail-closed by construction: a product only grants Premium if it appears
 * here AND the configured store identity matches. Nothing is inferred from
 * what the client sends, and an unconfigured environment grants nothing at
 * all rather than falling back to a guess.
 *
 * Real Play Console / App Store Connect identifiers are injected through
 * environment configuration, never hardcoded, because inventing an identifier
 * that does not exist in the store would make an unverifiable purchase look
 * legitimate.
 */

/** What a catalogue entry grants. Only one tier exists today. */
export type PremiumTier = "premium";

export interface PremiumProduct {
  productId: string;
  /** Google base plan, when the store models one. Null on Apple. */
  basePlanId: string | null;
  tier: PremiumTier;
}

function splitList(raw: string | undefined): string[] {
  return (raw ?? "")
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
}

/**
 * Parses `productId:basePlanId` pairs. A bare `productId` is accepted for
 * stores that do not model base plans; it then matches any base plan.
 */
function parseProducts(raw: string | undefined): PremiumProduct[] {
  return splitList(raw).map((entry) => {
    const [productId, basePlanId] = entry.split(":").map((part) => part.trim());
    return {
      productId,
      basePlanId: basePlanId ? basePlanId : null,
      tier: "premium" as const,
    };
  });
}

export interface PremiumCatalogue {
  androidPackageName: string;
  iosBundleId: string;
  android: PremiumProduct[];
  ios: PremiumProduct[];
}

/**
 * The catalogue the Functions emulator uses when nothing is configured.
 *
 * Deliberately not a real store identity: the package name says "emulator" so
 * it can never be mistaken for, or collide with, the production app. It exists
 * only so the emulator's test store has something to buy; the matching client
 * store lives in `EmulatorPremiumBillingRepository`.
 */
export const EMULATOR_PREMIUM_PACKAGE = "com.mevora.app.emulator";
export const EMULATOR_PREMIUM_PRODUCT_ID = "mevora_premium";

/**
 * Reads the catalogue from the environment on every call rather than at module
 * load, so a test can vary it and a deployed config change takes effect on the
 * next cold start without a code change.
 *
 * Under the Functions emulator, and only there, an empty Android configuration
 * falls back to the emulator catalogue. Anywhere else an empty configuration
 * stays empty and grants nothing.
 */
export function premiumCatalogue(
  env: NodeJS.ProcessEnv = process.env,
): PremiumCatalogue {
  const configured: PremiumCatalogue = {
    androidPackageName: (env.PREMIUM_ANDROID_PACKAGE_NAME ?? "").trim(),
    iosBundleId: (env.PREMIUM_IOS_BUNDLE_ID ?? "").trim(),
    android: parseProducts(env.PREMIUM_ANDROID_PRODUCT_IDS),
    ios: parseProducts(env.PREMIUM_IOS_PRODUCT_IDS),
  };
  const unconfiguredAndroid =
    configured.androidPackageName.length === 0 && configured.android.length === 0;
  if (env.FUNCTIONS_EMULATOR === "true" && unconfiguredAndroid) {
    return {
      ...configured,
      androidPackageName: EMULATOR_PREMIUM_PACKAGE,
      android: [
        {productId: EMULATOR_PREMIUM_PRODUCT_ID, basePlanId: "monthly", tier: "premium"},
        {productId: EMULATOR_PREMIUM_PRODUCT_ID, basePlanId: "yearly", tier: "premium"},
      ],
    };
  }
  return configured;
}

export type CatalogueRejection =
  | "not_configured"
  | "package_mismatch"
  | "unknown_product"
  | "unknown_base_plan";

export type CatalogueLookup =
  | {ok: true; product: PremiumProduct}
  | {ok: false; reason: CatalogueRejection};

/**
 * Resolves an Android purchase against the catalogue.
 *
 * An empty catalogue is `not_configured`, never a pass: until the real Play
 * Console products are configured, no Android purchase can grant Premium.
 */
export function resolveAndroidProduct(
  input: {packageName: string; productId: string; basePlanId?: string | null},
  catalogue: PremiumCatalogue = premiumCatalogue(),
): CatalogueLookup {
  if (catalogue.androidPackageName.length === 0 || catalogue.android.length === 0) {
    return {ok: false, reason: "not_configured"};
  }
  if (input.packageName !== catalogue.androidPackageName) {
    return {ok: false, reason: "package_mismatch"};
  }
  const matches = catalogue.android.filter(
    (product) => product.productId === input.productId,
  );
  if (matches.length === 0) {
    return {ok: false, reason: "unknown_product"};
  }
  // A catalogue entry without a base plan matches any base plan; one with a
  // base plan must match exactly, so a cheaper plan cannot claim a richer
  // product's entitlement.
  const basePlanId = input.basePlanId ?? null;
  const exact = matches.find((product) => product.basePlanId === basePlanId);
  if (exact) {
    return {ok: true, product: exact};
  }
  const wildcard = matches.find((product) => product.basePlanId === null);
  if (wildcard) {
    return {ok: true, product: wildcard};
  }
  return {ok: false, reason: "unknown_base_plan"};
}

/** Resolves an Apple purchase against the catalogue. Same fail-closed rules. */
export function resolveIosProduct(
  input: {bundleId: string; productId: string},
  catalogue: PremiumCatalogue = premiumCatalogue(),
): CatalogueLookup {
  if (catalogue.iosBundleId.length === 0 || catalogue.ios.length === 0) {
    return {ok: false, reason: "not_configured"};
  }
  if (input.bundleId !== catalogue.iosBundleId) {
    return {ok: false, reason: "package_mismatch"};
  }
  const product = catalogue.ios.find(
    (entry) => entry.productId === input.productId,
  );
  return product
    ? {ok: true, product}
    : {ok: false, reason: "unknown_product"};
}
