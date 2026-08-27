import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";
import type {NormalizedHumorContent} from "./normalizedContent.js";

export const HUMOR_PROVIDER_CACHE_COLLECTION = "humorProviderCache";
const DEFAULT_TTL_MS = 45 * 60 * 1000; // 45 minutes — metadata only

export type HumorProviderCacheDoc = {
  provider: string;
  queryKey: string;
  items: NormalizedHumorContent[];
  expiresAtMs: number;
  createdAt?: unknown;
  updatedAt?: unknown;
};

export function cacheDocId(provider: string, queryKey: string): string {
  const raw = `${provider}_${queryKey}`.toLowerCase().replace(/[^a-z0-9_-]/g, "_");
  return raw.slice(0, 140);
}

export async function readProviderCache(
  db: Firestore,
  provider: string,
  queryKey: string,
): Promise<NormalizedHumorContent[] | null> {
  const id = cacheDocId(provider, queryKey);
  const snap = await db.collection(HUMOR_PROVIDER_CACHE_COLLECTION).doc(id).get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() as HumorProviderCacheDoc;
  if (!data || Number(data.expiresAtMs ?? 0) < Date.now()) {
    return null;
  }
  return Array.isArray(data.items) ? data.items : null;
}

export async function writeProviderCache(
  db: Firestore,
  provider: string,
  queryKey: string,
  items: NormalizedHumorContent[],
  ttlMs = DEFAULT_TTL_MS,
): Promise<void> {
  const id = cacheDocId(provider, queryKey);
  await db
    .collection(HUMOR_PROVIDER_CACHE_COLLECTION)
    .doc(id)
    .set(
      {
        provider,
        queryKey,
        items,
        expiresAtMs: Date.now() + ttlMs,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
}

/** Drop a cached entry when content is deleted / unsafe. */
export async function invalidateProviderCache(
  db: Firestore,
  provider: string,
  queryKey: string,
): Promise<void> {
  const id = cacheDocId(provider, queryKey);
  await db.collection(HUMOR_PROVIDER_CACHE_COLLECTION).doc(id).delete().catch(() => undefined);
}
