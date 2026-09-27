import type {HumorCategory, HumorVector} from "./categories.js";

export type HumorContentType = "image" | "video" | "text" | "meme";

export type HumorSafetyStatus = "pending" | "approved" | "rejected" | "needs_review";

/**
 * Stage of the structured initial calibration. Declared here rather than in
 * `calibration.ts` so the content/feed types can reference it without the two
 * modules importing each other.
 */
export type HumorCalibrationStage =
  | "anchor"
  | "adaptive"
  | "exploration"
  | "complete";

export type HumorRating =
  | "very_funny"
  | "funny"
  | "neutral"
  | "not_funny"
  | "not_at_all";

export const HUMOR_RATINGS: readonly HumorRating[] = [
  "very_funny",
  "funny",
  "neutral",
  "not_funny",
  "not_at_all",
] as const;

export type HumorSafetyFlags = {
  nsfw: boolean;
  hate: boolean;
  harassment: boolean;
  violent: boolean;
  illegal: boolean;
  sexual: boolean;
  minorRelated: boolean;
  extreme: boolean;
};

export type HumorMedia = {
  storagePath?: string | null;
  downloadUrl?: string | null;
  thumbUrl?: string | null;
  durationMs?: number | null;
  aspectRatio?: number | null;
  textBody?: string | null;
};

export type HumorSource = {
  type: "internal" | "licensed_api";
  provider?: string | null;
  licenseRef?: string | null;
};

/**
 * Calibration curation for a content item.
 *
 * Defaults are deliberately closed: content that says nothing about
 * calibration parses as `eligible: false`, so bulk-ingested provider content
 * can never drift into the anchor pools. Only an explicit admin upsert — or the
 * curated internal seed — opts an item in.
 */
export type HumorCalibrationMeta = {
  /** May be served during initial calibration at all. */
  eligible: boolean;
  /** Anchor slot this item can fill. `null` means adaptive/exploration only. */
  slot: string | null;
  /** Calibration version this curation was authored against. */
  version: number;
};

export type HumorContentStats = {
  viewCount: number;
  ratingCount: number;
  avgRating: number;
};

export type HumorContentDoc = {
  contentId: string;
  type: HumorContentType;
  language: string;
  category: HumorCategory;
  humorTags: string[];
  humorVector: HumorVector;
  media: HumorMedia;
  safetyStatus: HumorSafetyStatus;
  safetyFlags: HumorSafetyFlags;
  source: HumorSource;
  calibration: HumorCalibrationMeta;
  createdAt?: unknown;
  updatedAt?: unknown;
  active: boolean;
  stats: HumorContentStats;
};

export type UserHumorProfileDoc = {
  vector: HumorVector;
  confidence: number;
  interactionCount: number;
  exploredCategories: string[];
  lastUpdatedAt?: unknown;
  version: number;
};

/**
 * `users/{uid}/humorInteractions/{contentId}`. Any document here — rated,
 * skipped or reported — keeps the item out of the user's feed. Only a valid
 * `rating` makes it count as rated; a skip or report marker carries none, so a
 * later real rating is still that item's first.
 */
export type HumorInteractionDoc = {
  contentId: string;
  rating: HumorRating | null;
  /**
   * Per-dimension change this rating applied to the profile vector, so a
   * changed rating can replace its contribution instead of stacking on it.
   */
  appliedDelta?: Partial<Record<HumorCategory, number>>;
  dwellMs?: number;
  replayCount?: number;
  skipped: boolean;
  /** Written only when the client explicitly sends it. */
  saved?: boolean;
  /** Set by `reportHumorContent`. */
  reported?: boolean;
  gestureHints?: {swipeUp: boolean; swipeDown: boolean} | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

/**
 * Feed-safe card — no internal vectors, safety flags or anchor slot ids.
 *
 * `calibrationStage` is the one calibration detail the client gets: it needs to
 * label the card, but it must not learn which slot the item fills or how the
 * selector scored it.
 */
export type HumorFeedItem = {
  contentId: string;
  type: HumorContentType;
  language: string;
  category: HumorCategory;
  humorTags: string[];
  media: HumorMedia;
  calibrationStage?: HumorCalibrationStage | null;
};

/**
 * Server-owned initial calibration state, persisted at
 * `users/{uid}/humor/calibration`.
 *
 * It lives beside `users/{uid}/humor/summary` on purpose: the existing rules
 * (`match /humor/{docId}` — owner-read, client-write denied) and the existing
 * account-deletion sweep of `users/{uid}/humor` both cover it without change.
 */
export type UserHumorCalibrationDoc = {
  version: number;
  /** Successful *new* rated interactions counted toward calibration (0..15). */
  completedCount: number;
  stage: HumorCalibrationStage;
  complete: boolean;
  /** Content already consumed by calibration — never served twice. */
  ratedContentIds: string[];
  /** Anchor slots already satisfied. */
  coveredSlots: string[];
  /** Humor dimensions measured so far; drives adaptive + exploration picks. */
  coveredDimensions: string[];
  /**
   * Positions filled below the designed measurement quality: uncurated
   * content (adaptive/exploration, or an anchor position once the curated
   * pool is exhausted for this user), or an anchor position that measured no
   * new slot. Calibration still completes — a dead calibration state would be
   * worse — but the degradation is recorded, and surfaced as the view's
   * `degraded` flag, rather than hidden.
   */
  degradedCount: number;
  startedAt?: unknown;
  completedAt?: unknown;
  updatedAt?: unknown;
};

export type HumorCompatibilityResult = {
  available: boolean;
  score: number | null;
  strongestShared: HumorCategory[];
  differences: Array<{dim: HumorCategory; a: number; b: number}>;
  confidence: number;
  reason?: string;
};

export const HUMOR_PROFILE_VERSION = 1;
export const HUMOR_FEED_PAGE_SIZE = 12;
export const HUMOR_PROFILE_BUILDING_THRESHOLD = 15;
