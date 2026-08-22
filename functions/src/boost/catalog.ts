import type {Firestore} from "firebase-admin/firestore";
import {BOOST_PRODUCT_IDS, LEGACY_DURATION_MS} from "./config.js";

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
}

export const DEFAULT_BOOST_PACKS: BoostPack[] = [
  {
    productId: BOOST_PRODUCT_IDS.week,
    boostCount: 0,
    displayOrder: 0,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: WEEK_MS,
    durationDays: 7,
    active: true,
    storefront: true,
    featured: false,
  },
  {
    productId: BOOST_PRODUCT_IDS.month,
    boostCount: 0,
    displayOrder: 1,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: MONTH_MS,
    durationDays: 30,
    active: true,
    storefront: true,
    featured: false,
  },
  {
    productId: BOOST_PRODUCT_IDS.year,
    boostCount: 0,
    displayOrder: 2,
    fallbackPriceAmount: 0,
    fallbackCurrency: "TRY",
    durationMs: YEAR_MS,
    durationDays: 365,
    active: true,
    storefront: true,
    featured: true,
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
  },
  {
    productId: process.env.BOOST_IOS_PRODUCT_ID ??
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
  },
];

export function isDurationPack(pack: BoostPack): boolean {
  return pack.durationMs >= 24 * 60 * 60 * 1000;
}

export function defaultPackFor(productId: string): BoostPack | null {
  const found = DEFAULT_BOOST_PACKS.find(
    (pack) => pack.productId === productId && pack.active && (pack.durationMs > 0 || pack.boostCount > 0),
  );
  return found ?? null;
}

export function isAllowedProduct(productId: string, _platform?: "ios" | "android"): boolean {
  return defaultPackFor(productId) != null;
}

function durationFromData(data: Record<string, unknown>): {durationMs: number; durationDays: number} {
  const days = Number(data.durationDays ?? 0);
  if (days > 0) {
    return {durationDays: days, durationMs: days * 24 * 60 * 60 * 1000};
  }
  const ms = Number(data.durationMs ?? 0);
  if (ms > 0) {
    return {durationMs: ms, durationDays: Math.round(ms / (24 * 60 * 60 * 1000))};
  }
  const minutes = Number(data.durationMinutes ?? 0);
  if (minutes > 0) {
    return {durationMs: minutes * 60 * 1000, durationDays: 0};
  }
  return {durationMs: 0, durationDays: 0};
}

export async function resolveBoostPack(db: Firestore, productId: string): Promise<BoostPack | null> {
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
  };
}

export async function ensureDefaultCatalog(db: Firestore): Promise<void> {
  const week = await db.doc(`boostProducts/${BOOST_PRODUCT_IDS.week}`).get();
  if (week.exists) {
    return;
  }
  const batch = db.batch();
  for (const pack of DEFAULT_BOOST_PACKS) {
    batch.set(db.doc(`boostProducts/${pack.productId}`), packDocument(pack), {merge: true});
  }
  await batch.commit();
}
