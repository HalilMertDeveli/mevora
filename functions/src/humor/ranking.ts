import {
  HUMOR_CATEGORIES,
  normalizeHumorVector,
  normalizeProfileVector,
  type HumorCategory,
} from "./categories.js";
import {affinityScore} from "./profile.js";
import type {HumorContentDoc, UserHumorProfileDoc} from "./types.js";

const W_AFFINITY = 0.55;
const W_NOVELTY = 0.15;
const W_EXPLORATION = 0.15;
const W_QUALITY = 0.1;
const W_LANGUAGE = 0.05;

/** Target exploration fraction per page (15–20%). */
export const EXPLORATION_FRACTION = 0.18;

export type HumorCandidateScore = {
  contentId: string;
  total: number;
  affinity: number;
  novelty: number;
  exploration: number;
  quality: number;
  language: number;
};

function qualityScore(content: HumorContentDoc): number {
  const stats = content.stats ?? {viewCount: 0, ratingCount: 0, avgRating: 0};
  const count = Math.max(0, stats.ratingCount ?? 0);
  const avg = typeof stats.avgRating === "number" ? stats.avgRating : 0;
  // avgRating expected roughly -1..1 or 0..1; normalize softly.
  const normalizedAvg = Math.min(1, Math.max(0, (avg + 1) / 2));
  const prior = 0.55;
  const weight = Math.min(1, count / 20);
  return prior * (1 - weight) + normalizedAvg * weight;
}

function languageScore(contentLang: string, userLanguages: string[]): number {
  const lang = contentLang.trim().toLowerCase();
  if (!lang) {
    return 0.5;
  }
  if (userLanguages.length === 0) {
    return 0.7;
  }
  return userLanguages.some((l) => l.trim().toLowerCase() === lang) ? 1 : 0.15;
}

function explorationBonus(profile: UserHumorProfileDoc, content: HumorContentDoc): number {
  const explored = new Set((profile.exploredCategories ?? []).map((c) => c.toLowerCase()));
  const category = String(content.category ?? "").toLowerCase();
  if (!category) {
    return 0.5;
  }
  if (!explored.has(category)) {
    return 1;
  }
  // Prefer under-confident dims that this content emphasizes.
  const vector = normalizeProfileVector(profile.vector, 50);
  const contentVec = normalizeHumorVector(content.humorVector, 0);
  let underExploredMass = 0;
  for (const dim of HUMOR_CATEGORIES) {
    if (vector[dim] < 55 && contentVec[dim] >= 0.5) {
      underExploredMass += contentVec[dim];
    }
  }
  return Math.min(1, 0.35 + underExploredMass);
}

export function scoreHumorCandidate(input: {
  profile: UserHumorProfileDoc;
  content: HumorContentDoc;
  seen: boolean;
  userLanguages: string[];
}): HumorCandidateScore {
  const profileVec = normalizeProfileVector(input.profile.vector, 50);
  const contentVec = normalizeHumorVector(input.content.humorVector, 0);
  const affinity = affinityScore(profileVec, contentVec);
  const novelty = input.seen ? 0 : 1;
  const exploration = explorationBonus(input.profile, input.content);
  const quality = qualityScore(input.content);
  const language = languageScore(input.content.language, input.userLanguages);
  const total =
    W_AFFINITY * affinity +
    W_NOVELTY * novelty +
    W_EXPLORATION * exploration +
    W_QUALITY * quality +
    W_LANGUAGE * language;
  return {
    contentId: input.content.contentId,
    total,
    affinity,
    novelty,
    exploration,
    quality,
    language,
  };
}

/**
 * Rank candidates and inject ~18% exploration slots from the lower-affinity pool.
 * Dedupes by contentId. Seen items are heavily deprioritized via novelty=0.
 */
export function rankHumorFeed(input: {
  profile: UserHumorProfileDoc;
  items: Array<{content: HumorContentDoc; seen: boolean}>;
  userLanguages: string[];
  limit: number;
}): HumorContentDoc[] {
  const scored = input.items
    .map((item) => ({
      content: item.content,
      score: scoreHumorCandidate({
        profile: input.profile,
        content: item.content,
        seen: item.seen,
        userLanguages: input.userLanguages,
      }),
    }))
    .sort((a, b) => b.score.total - a.score.total);

  const limit = Math.max(1, Math.min(15, input.limit));
  const explorationSlots = Math.max(1, Math.round(limit * EXPLORATION_FRACTION));
  const exploitSlots = Math.max(0, limit - explorationSlots);
  const picked = new Set<string>();
  const result: HumorContentDoc[] = [];

  for (const row of scored) {
    if (result.length >= exploitSlots) {
      break;
    }
    if (picked.has(row.content.contentId)) {
      continue;
    }
    picked.add(row.content.contentId);
    result.push(row.content);
  }

  // Exploration: pick from items with lower affinity / higher exploration bonus.
  const explorationPool = [...scored].sort(
    (a, b) => b.score.exploration - a.score.exploration || a.score.affinity - b.score.affinity,
  );
  for (const row of explorationPool) {
    if (result.length >= limit) {
      break;
    }
    if (picked.has(row.content.contentId)) {
      continue;
    }
    picked.add(row.content.contentId);
    result.push(row.content);
  }

  // Fill remaining from top score if needed.
  for (const row of scored) {
    if (result.length >= limit) {
      break;
    }
    if (picked.has(row.content.contentId)) {
      continue;
    }
    picked.add(row.content.contentId);
    result.push(row.content);
  }

  return result;
}

export function underExploredCategories(profile: UserHumorProfileDoc): HumorCategory[] {
  const explored = new Set((profile.exploredCategories ?? []).map((c) => c.toLowerCase()));
  return HUMOR_CATEGORIES.filter((c) => !explored.has(c));
}

export function profileAsHumorVector(profile: UserHumorProfileDoc) {
  return normalizeProfileVector(profile.vector, 50);
}
