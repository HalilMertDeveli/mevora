import type {Firestore} from "firebase-admin/firestore";
import {
  BOOST_PRODUCT_IDS,
  LEGACY_DURATION_MS,
  SMART_BOOST_DURATION_MS,
  SMART_BOOST_MULTIPLIER,
} from "./config.js";

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const MONTH_MS = 30 * 24 * 60 * 60 * 1000;
const YEAR_MS = 365 * 24 * 60 * 60 * 1000;

export interface BoostPack {
  productId: string;
  boostCount: number;
  displayOrder: number;
  fallbackPriceAmount: number;
  fallbackCurrency: string;
  durationMs: number;
  durationDays: number;
  active: boolean;
  storefront: boolean;
  featured: boolean;
  boostType?: "smart" | "classic";
  multiplier?: number;
  title?: string;
}

export const DEFAULT_BOOST_PACKS: BoostPack[] = [
  {
    productId: BOOST_PRODUCT_IDS.starter30m,
    boostCount: 0,
    displayOrder: 0,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: SMART_BOOST_DURATION_MS.starter30m,
    durationDays: 0,
    active: true,
    storefront: true,
    featured: false,
    boostType: "smart",
    multiplier: SMART_BOOST_MULTIPLIER,
    title: "Starter",
  },
  {
    productId: BOOST_PRODUCT_IDS.popular1h,
    boostCount: 0,
    displayOrder: 1,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: SMART_BOOST_DURATION_MS.popular1h,
    durationDays: 0,
    active: true,
    storefront: true,
    featured: true,
    boostType: "smart",
    multiplier: SMART_BOOST_MULTIPLIER,
    title: "Popular",
  },
  {
    productId: BOOST_PRODUCT_IDS.power24h,
    boostCount: 0,
    displayOrder: 2,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: SMART_BOOST_DURATION_MS.power24h,
    durationDays: 1,
    active: true,
    storefront: true,
    featured: false,
    boostType: "smart",
    multiplier: SMART_BOOST_MULTIPLIER,
    title: "Power",
  },
  {
    productId: BOOST_PRODUCT_IDS.week,
    boostCount: 0,
    displayOrder: 10,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: WEEK_MS,
    durationDays: 7,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId: BOOST_PRODUCT_IDS.month,
    boostCount: 0,
    displayOrder: 11,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: MONTH_MS,
    durationDays: 30,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId: BOOST_PRODUCT_IDS.year,
    boostCount: 0,
    displayOrder: 12,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: YEAR_MS,
    durationDays: 365,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId: "com.mevora.app.boost.1",
    boostCount: 1,
    displayOrder: 90,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: LEGACY_DURATION_MS,
    durationDays: 0,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId: "com.mevora.app.boost.5",
    boostCount: 5,
    displayOrder: 91,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: LEGACY_DURATION_MS,
    durationDays: 0,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId: "com.mevora.app.boost.10",
    boostCount: 10,
    displayOrder: 92,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: LEGACY_DURATION_MS,
    durationDays: 0,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
  {
    productId:
      process.env.BOOST_IOS_PRODUCT_ID ??
      process.env.BOOST_ANDROID_PRODUCT_ID ??
      "com.mevora.app.boost",
    boostCount: 1,
    displayOrder: 99,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: LEGACY_DURATION_MS,
    durationDays: 0,
    active: true,
    storefront: false,
    featured: false,
    boostType: "classic",
    multiplier: SMART_BOOST_MULTIPLIER,
  },
];

/**
 * Duration packs auto-activate (including Smart Boost 30m / 1h / 24h).
 * Credit packs keep boostCount >= 1.
 */
export function isDurationPack(pack: BoostPack): boolean {
  return pack.durationMs > 0 && pack.boostCount === 0;
}

export function defaultPackFor(productId: string): BoostPack | null {
  const found = DEFAULT_BOOST_PACKS.find(
    (pack) =>
      pack.productId === productId &&
      pack.active &&
      (pack.durationMs > 0 || pack.boostCount > 0),
  );
  return found ?? null;
}

export function isAllowedProduct(
  productId: string,
  _platform?: "ios" | "android",
): boolean {
  return defaultPackFor(productId) != null;
}

function durationFromData(data: Record<string, unknown>): {
  durationMs: number;
  durationDays: number;
} {
  const days = Number(data.durationDays ?? 0);
  if (days > 0) {
    return {durationDays: days, durationMs: days * 24 * 60 * 60 * 1000};
  }
  const ms = Number(data.durationMs ?? 0);
  if (ms > 0) {
    return {
      durationMs: ms,
      durationDays: Math.round(ms / (24 * 60 * 60 * 1000)),
    };
  }
  const minutes = Number(data.durationMinutes ?? 0);
  if (minutes > 0) {
    return {durationMs: minutes * 60 * 1000, durationDays: 0};
  }
  return {durationMs: 0, durationDays: 0};
}

export async function resolveBoostPack(
  db: Firestore,
  productId: string,
): Promise<BoostPack | null> {
  if (!productId) {
    return null;
  }
  const snap = await db.doc(`boostProducts/${productId}`).get();
  if (snap.exists) {
    const data = (snap.data() ?? {}) as Record<string, unknown>;
    if (data.active === false) {
      return null;
    }
    const boostCount = Number(data.boostCount ?? 0);
    const duration = durationFromData(data);
    if (boostCount < 1 && duration.durationMs < 1) {
      return null;
    }
    return {
      productId,
      boostCount,
      displayOrder: Number(data.displayOrder ?? 0),
      fallbackPriceAmount: Number(data.fallbackPriceAmount ?? 0),
      fallbackCurrency: String(data.fallbackCurrency ?? "TRY"),
      durationMs: duration.durationMs,
      durationDays: duration.durationDays,
      active: true,
      storefront: data.storefront !== false,
      featured: data.featured === true,
      boostType: data.boostType === "smart" ? "smart" : "classic",
      multiplier: Number(data.multiplier ?? SMART_BOOST_MULTIPLIER),
      title: typeof data.title === "string" ? data.title : undefined,
    };
  }
  return defaultPackFor(productId);
}

function packDocument(pack: BoostPack) {
  return {
    productId: pack.productId,
    sku: pack.productId,
    boostCount: pack.boostCount,
    displayOrder: pack.displayOrder,
    fallbackPriceAmount: pack.fallbackPriceAmount,
    fallbackCurrency: pack.fallbackCurrency,
    durationMs: pack.durationMs,
    durationDays: pack.durationDays,
    durationMinutes: Math.round(pack.durationMs / 60000),
    active: pack.active,
    storefront: pack.storefront,
    featured: pack.featured,
    boostType: pack.boostType ?? "classic",
    multiplier: pack.multiplier ?? SMART_BOOST_MULTIPLIER,
    title: pack.title ?? null,
  };
}

/** Seeds any missing default products (idempotent per product id). */
export async function ensureDefaultCatalog(db: Firestore): Promise<void> {
  const batch = db.batch();
  let writes = 0;
  for (const pack of DEFAULT_BOOST_PACKS) {
    const ref = db.doc(`boostProducts/${pack.productId}`);
    const snap = await ref.get();
    if (!snap.exists) {
      batch.set(ref, packDocument(pack), {merge: true});
      writes++;
    }
  }
  if (writes > 0) {
    await batch.commit();
  }
}
