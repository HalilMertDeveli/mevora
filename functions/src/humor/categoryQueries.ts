import type {HumorCategory} from "./categories.js";

/**
 * Product-facing humor search buckets (allowlisted only).
 * Never pass raw user input as a provider query.
 */
export const HUMOR_SEARCH_BUCKETS = [
  "absurd",
  "dark",
  "situational",
  "social",
  "animal",
  "fail",
  "prank",
  "turkish",
  "british",
  "meme",
  "sketch",
  "reaction",
] as const;

export type HumorSearchBucket = (typeof HUMOR_SEARCH_BUCKETS)[number];

export function isHumorSearchBucket(value: string): value is HumorSearchBucket {
  return (HUMOR_SEARCH_BUCKETS as readonly string[]).includes(value);
}

/** Map product search buckets → existing Humor Lab vector dimensions. */
export const BUCKET_TO_CATEGORY: Record<HumorSearchBucket, HumorCategory> = {
  absurd: "absurd",
  dark: "dark",
  situational: "situational",
  social: "teasing",
  animal: "silly",
  fail: "cringe",
  prank: "teasing",
  turkish: "situational",
  british: "dry",
  meme: "meme",
  sketch: "situational",
  reaction: "meme",
};

/** Turkish-first allowlisted queries per bucket. */
export const BUCKET_QUERIES_TR: Record<HumorSearchBucket, readonly string[]> = {
  absurd: ["absürt", "absürt komedi", "absürt komik", "saçma komik kısa"],
  dark: ["kara mizah", "karanlık mizah komik"],
  situational: ["situasyon komedisi", "komik anlar", "günlük komedi"],
  social: ["sosyal mizah", "sosyal komedi kısa", "sarkastik"],
  animal: ["komik kedi", "komik köpek", "hayvan komik", "komik hayvanlar"],
  fail: ["fail komik", "komik fail", "epic fail short"],
  prank: ["prank komik", "şaka videosu kısa", "funny prank short"],
  turkish: ["türk komedi", "türk mizahı", "komik video türkçe", "mizah", "kahkaha", "komik"],
  british: ["british humor short", "ingiliz mizahı"],
  meme: ["meme", "komik meme", "türk meme"],
  sketch: ["komik skeç", "kısa skeç", "comedy sketch short"],
  reaction: ["komik tepki", "komik reaksiyon", "reaction komik", "funny reaction short"],
};

export const BUCKET_QUERIES_EN: Record<HumorSearchBucket, readonly string[]> = {
  absurd: ["absurd comedy short", "surreal funny short"],
  dark: ["dark humor funny short", "black comedy short"],
  situational: ["situational comedy short", "funny everyday moments"],
  social: ["social comedy short", "awkward social funny"],
  animal: ["funny animals short", "cute funny pets"],
  fail: ["fail compilation short", "epic fail funny"],
  prank: ["prank short funny", "harmless prank comedy"],
  turkish: ["turkish comedy short", "turkish funny video"],
  british: ["british humor short", "dry british comedy"],
  meme: ["meme funny short", "viral meme comedy"],
  sketch: ["comedy sketch short", "short sketch funny"],
  reaction: ["funny reaction short", "reaction meme funny"],
};

/** Extra short-form YouTube filters / suffixes. */
export const SHORT_FORM_HINTS = ["#shorts", "kısa", "short"] as const;

export function queriesForBucket(
  bucket: HumorSearchBucket,
  language: string,
): readonly string[] {
  const lang = language.toLowerCase().startsWith("tr") ? "tr" : "en";
  return lang === "tr" ? BUCKET_QUERIES_TR[bucket] : BUCKET_QUERIES_EN[bucket];
}

export function pickBucketQuery(
  bucket: HumorSearchBucket,
  language: string,
  salt = Date.now(),
): string {
  const queries = queriesForBucket(bucket, language);
  return queries[Math.abs(salt) % queries.length] ?? queries[0];
}

export function pickBalancedBuckets(count: number, salt = Date.now()): HumorSearchBucket[] {
  const rotated = [...HUMOR_SEARCH_BUCKETS];
  const start = Math.abs(salt) % rotated.length;
  const ordered = [...rotated.slice(start), ...rotated.slice(0, start)];
  const out: HumorSearchBucket[] = [];
  for (let i = 0; i < Math.max(1, count); i += 1) {
    out.push(ordered[i % ordered.length]);
  }
  return out;
}
