const DAY_MS = 24 * 60 * 60 * 1000;

export const PREMIUM_PRODUCT_IDS = {
  month: "mevora_premium_1_month",
  year: "mevora_premium_1_year",
} as const;

export interface PremiumPack {
  productId: string;
  durationMs: number;
  durationDays: number;
  displayOrder: number;
  active: boolean;
}

export const DEFAULT_PREMIUM_PACKS: PremiumPack[] = [
  {
    productId: PREMIUM_PRODUCT_IDS.month,
    durationMs: 30 * DAY_MS,
    durationDays: 30,
    displayOrder: 0,
    active: true,
  },
  {
    productId: PREMIUM_PRODUCT_IDS.year,
    durationMs: 365 * DAY_MS,
    durationDays: 365,
    displayOrder: 1,
    active: true,
  },
];

export function isPremiumProduct(productId: string): boolean {
  return DEFAULT_PREMIUM_PACKS.some((p) => p.productId === productId && p.active);
}

export function resolvePremiumPack(productId: string): PremiumPack | null {
  return DEFAULT_PREMIUM_PACKS.find((p) => p.productId === productId && p.active) ?? null;
}
