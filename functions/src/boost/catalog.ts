import type {Firestore} from "firebase-admin/firestore";

const DEFAULT_DURATION_MS = 30 * 60 * 1000;

export interface BoostPack {
  productId: string;
  boostCount: number;
  displayOrder: number;
  fallbackPriceAmount: number;
  fallbackCurrency: string;
  durationMs: number;
  active: boolean;
}

export const DEFAULT_BOOST_PACKS: BoostPack[] = [
  {
    productId: "com.mevora.app.boost.1",
    boostCount: 1,
    displayOrder: 0,
    fallbackPriceAmount: 49.99,
    fallbackCurrency: "TRY",
    durationMs: DEFAULT_DURATION_MS,
    active: true,
  },
  {
    productId: "com.mevora.app.boost.5",
    boostCount: 5,
    displayOrder: 1,
    fallbackPriceAmount: 199.99,
    fallbackCurrency: "TRY",
    durationMs: DEFAULT_DURATION_MS,
    active: true,
  },
  {
    productId: "com.mevora.app.boost.10",
    boostCount: 10,
    displayOrder: 2,
    fallbackPriceAmount: 349.99,
    fallbackCurrency: "TRY",
    durationMs: DEFAULT_DURATION_MS,
    active: true,
  },
  {
    productId: process.env.BOOST_IOS_PRODUCT_ID ?? process.env.BOOST_ANDROID_PRODUCT_ID ?? "com.mevora.app.boost",
    boostCount: 1,
    displayOrder: 99,
    fallbackPriceAmount: 49.99,
    fallbackCurrency: "TRY",
    durationMs: DEFAULT_DURATION_MS,
    active: true,
  },
];

export function defaultPackFor(productId: string): BoostPack | null {
  const found = DEFAULT_BOOST_PACKS.find((pack) => pack.productId === productId && pack.active && pack.boostCount > 0);
  return found ?? null;
}

export function isAllowedProduct(productId: string, _platform?: "ios" | "android"): boolean {
  return defaultPackFor(productId) != null;
}

export async function resolveBoostPack(db: Firestore, productId: string): Promise<BoostPack | null> {
  if (!productId) {
    return null;
  }
  const snap = await db.doc(`boostProducts/${productId}`).get();
  if (snap.exists) {
    const data = snap.data() ?? {};
    if (data.active === false) {
      return null;
    }
    const boostCount = Number(data.boostCount ?? 0);
    if (boostCount < 1) {
      return null;
    }
    return {
      productId,
      boostCount,
      displayOrder: Number(data.displayOrder ?? 0),
      fallbackPriceAmount: Number(data.fallbackPriceAmount ?? 0),
      fallbackCurrency: String(data.fallbackCurrency ?? "TRY"),
      durationMs:
        Number(data.durationMs ?? 0) > 0
          ? Number(data.durationMs)
          : Number(data.durationMinutes ?? 0) > 0
            ? Number(data.durationMinutes) * 60 * 1000
            : DEFAULT_DURATION_MS,
      active: true,
    };
  }
  return defaultPackFor(productId);
}

export async function ensureDefaultCatalog(db: Firestore): Promise<void> {
  const existing = await db.collection("boostProducts").limit(1).get();
  if (!existing.empty) {
    return;
  }
  const batch = db.batch();
  for (const pack of DEFAULT_BOOST_PACKS) {
    batch.set(db.doc(`boostProducts/${pack.productId}`), {
      productId: pack.productId,
      sku: pack.productId,
      boostCount: pack.boostCount,
      displayOrder: pack.displayOrder,
      fallbackPriceAmount: pack.fallbackPriceAmount,
      fallbackCurrency: pack.fallbackCurrency,
      durationMinutes: Math.round(pack.durationMs / 60000),
      active: pack.active,
    });
  }
  await batch.commit();
}
