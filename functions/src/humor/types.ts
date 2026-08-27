import type {HumorCategory, HumorVector} from "./categories.js";

export type HumorContentType = "image" | "video" | "text" | "meme";

export type HumorSafetyStatus = "pending" | "approved" | "rejected" | "needs_review";

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
  /** YouTube / iframe embed — never download into Storage. */
  embedUrl?: string | null;
  attributionRequired?: boolean;
};

export type HumorSource = {
  type: "internal" | "licensed_api";
  provider?: string | null;
  licenseRef?: string | null;
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

export type HumorInteractionDoc = {
  contentId: string;
  rating: HumorRating;
  dwellMs: number;
  replayCount: number;
  skipped: boolean;
  saved: boolean;
  gestureHints?: {swipeUp?: boolean; swipeDown?: boolean} | null;
  createdAt?: unknown;
  updatedAt?: unknown;
};

/** Feed-safe card — no internal vectors / safety flags. */
export type HumorFeedItem = {
  contentId: string;
  type: HumorContentType;
  language: string;
  category: HumorCategory;
  humorTags: string[];
  media: HumorMedia;
  provider?: string | null;
  /** Provider-native id (e.g. YouTube videoId) when contentId is ext_<provider>_<id>. */
  sourceId?: string | null;
  attributionRequired?: boolean;
  sourceUrl?: string | null;
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
