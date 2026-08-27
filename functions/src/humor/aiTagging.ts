import {
  isHumorCategory,
  normalizeHumorVector,
  type HumorCategory,
  type HumorVector,
} from "./categories.js";
import {classifyHumorSafety, emptySafetyFlags} from "./moderation.js";
import type {HumorSafetyFlags, HumorSafetyStatus} from "./types.js";

const DEFAULT_CATEGORY: HumorCategory = "silly";

export type HumorAiTaggingInput = {
  suggestedCategory?: string;
  suggestedTags?: string[];
  suggestedVector?: Partial<HumorVector> | Record<string, number>;
  suggestedSafetyFlags?: Partial<HumorSafetyFlags>;
};

export type HumorAiTaggingResult = {
  category: HumorCategory;
  humorTags: string[];
  humorVector: HumorVector;
  safetyFlags: HumorSafetyFlags;
  safetyStatus: HumorSafetyStatus;
  /** Always false — AI never drives user humor scoring. */
  usedForUserScoring: false;
};

/**
 * Pure sanitizer for AI (or human CMS) proposals. Safe to unit-test without an LLM.
 */
export function applyHumorAiTagging(input: HumorAiTaggingInput): HumorAiTaggingResult {
  const category =
    input.suggestedCategory && isHumorCategory(input.suggestedCategory)
      ? input.suggestedCategory
      : DEFAULT_CATEGORY;
  const tags = (input.suggestedTags ?? [])
    .map((t) => String(t).trim().toLowerCase())
    .filter(Boolean)
    .slice(0, 12);
  const humorVector = normalizeHumorVector(input.suggestedVector, 0);
  // Ensure primary category has mass if vector empty.
  const hasMass = Object.values(humorVector).some((v) => v > 0);
  if (!hasMass) {
    humorVector[category] = 0.7;
  }
  const classified = classifyHumorSafety(emptySafetyFlags(input.suggestedSafetyFlags ?? {}));
  return {
    category,
    humorTags: tags,
    humorVector,
    safetyFlags: classified.flags,
    safetyStatus: classified.status,
    usedForUserScoring: false,
  };
}
