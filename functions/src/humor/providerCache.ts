import type {Firestore} from "firebase-admin/firestore";
import {FieldValue} from "firebase-admin/firestore";
import type {NormalizedHumorContent} from "./normalizedContent.js";

export const HUMOR_PROVIDER_CACHE_COLLECTION = "humorProviderCache";
const DEFAULT_TTL_MS = 45 * 60 * 1000; // 45 minutes — metadata only

export type HumorProviderCacheDoc = {
  provider: string;
  queryKey: string;
  items: NormalizedHumorContent[];
  /** YouTube search.list / GIPHY next page cursor — omit search.list when cache hit is enough. */
  nextPageToken?: string | null;
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
  const page = await readProviderCachePage(db, provider, queryKey);
  return page?.items ?? null;
}

export async function readProviderCachePage(
  db: Firestore,
  provider: string,
  queryKey: string,
): Promise<{items: NormalizedHumorContent[]; nextPageToken: string | null} | null> {
  const id = cacheDocId(provider, queryKey);
  const snap = await db.collection(HUMOR_PROVIDER_CACHE_COLLECTION).doc(id).get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() as HumorProviderCacheDoc;
  if (!data || Number(data.expiresAtMs ?? 0) < Date.now()) {
    return null;
  }
  return {
    items: Array.isArray(data.items) ? data.items : [],
    nextPageToken: data.nextPageToken ?? null,
  };
}

export async function writeProviderCache(
  db: Firestore,
  provider: string,
  queryKey: string,
  items: NormalizedHumorContent[],
  ttlMs = DEFAULT_TTL_MS,
  nextPageToken: string | null = null,
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
        nextPageToken,
        expiresAtMs: Date.now() + ttlMs,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
}

/** Merge unique items by id; keep latest nextPageToken. */
export function mergeProviderCacheItems(
  existing: NormalizedHumorContent[],
  incoming: NormalizedHumorContent[],
): NormalizedHumorContent[] {
  const byId = new Map<string, NormalizedHumorContent>();
  for (const item of existing) {
    if (item?.id) byId.set(item.id, item);
  }
  for (const item of incoming) {
    if (item?.id) byId.set(item.id, item);
  }
  return [...byId.values()];
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
