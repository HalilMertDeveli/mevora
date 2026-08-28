import {
  QUESTION_TOPICS,
  normalizeAnswerId,
  type RelationshipAnswers,
} from "../relationshipCompatibility.js";

/**
 * Humor-tagged relationship question IDs with category `fun` in Flutter catalog.
 * Keep in sync with lib/features/relationship/data/catalog/relationship_catalog_entries.dart
 * (do not edit relationship_questions.dart — read-only classification mirror).
 */
export const FUN_CATEGORY_QUESTION_IDS = new Set<string>([
  "rq_002",
  "rq_005",
  "rq_008",
  "rq_011",
  "rq_014",
  "rq_017",
  "rq_020",
  "rq_023",
  "rq_026",
  "rq_029",
  "rq_032",
  "rq_035",
  "rq_038",
  "rq_041",
  "rq_044",
  "rq_049",
  "rq_052",
  "rq_055",
  "rq_058",
  "rq_061",
  "rq_066",
  "rq_069",
  "rq_072",
  "rq_075",
  "rq_078",
  "rq_083",
  "rq_086",
  "rq_091",
  "rq_094",
  "rq_099",
  "rq_102",
  "rq_107",
  "rq_110",
]);

/** Mirrors HumorAnswerComparator thresholds (Dart). */
export const HUMOR_QA_MIN_COMPARABLE = 2;
export const HUMOR_QA_MIN_MATCHING = 1;
export const HUMOR_QA_MIN_SCORE = 60;
export const HUMOR_QA_STRONG_MIN_SCORE = 75;
export const HUMOR_QA_STRONG_MIN_COMPARABLE = 3;

export type HumorAnswerComparison = {
  comparableAnswers: number;
  matchingAnswers: number;
  similarity: number;
  score: number;
};

export const EMPTY_HUMOR_ANSWER_COMPARISON: HumorAnswerComparison = {
  comparableAnswers: 0,
  matchingAnswers: 0,
  similarity: 0,
  score: 0,
};

/** Same rules as HumorAnswerComparator.isHumorQuestion (Dart). */
export function isHumorQuestionId(questionId: string): boolean {
  if (FUN_CATEGORY_QUESTION_IDS.has(questionId)) {
    return true;
  }
  const topic = QUESTION_TOPICS[questionId];
  return topic === "flirting" || topic === "socialLife";
}

export function normalizeAnswerMap(
  raw: RelationshipAnswers,
): RelationshipAnswers {
  const out: RelationshipAnswers = {};
  for (const [questionId, answerId] of Object.entries(raw)) {
    const normalized = normalizeAnswerId(answerId) ?? answerId?.trim();
    if (!questionId.trim() || !normalized) {
      continue;
    }
    out[questionId.trim()] = normalized;
  }
  return out;
}

/**
 * Compare humor-tagged relationship answers for two users.
 * Never returns raw answer maps — only aggregate counts/score.
 */
export function compareHumorAnswers(
  viewer: RelationshipAnswers,
  candidate: RelationshipAnswers,
): HumorAnswerComparison {
  const a = normalizeAnswerMap(viewer);
  const b = normalizeAnswerMap(candidate);
  if (Object.keys(a).length === 0 || Object.keys(b).length === 0) {
    return EMPTY_HUMOR_ANSWER_COMPARISON;
  }

  let comparable = 0;
  let matching = 0;

  for (const [questionId, viewerAnswer] of Object.entries(a)) {
    const candidateAnswer = b[questionId];
    if (candidateAnswer == null) {
      continue;
    }
    if (!isHumorQuestionId(questionId)) {
      continue;
    }
    comparable++;
    if (viewerAnswer === candidateAnswer) {
      matching++;
    }
  }

  if (comparable === 0) {
    return EMPTY_HUMOR_ANSWER_COMPARISON;
  }

  const similarity = matching / comparable;
  const score = Math.round(similarity * 100);

  return {
    comparableAnswers: comparable,
    matchingAnswers: matching,
    similarity,
    score: Math.min(100, Math.max(0, score)),
  };
}

export function meetsHumorAnswerReasonThreshold(
  comparison: HumorAnswerComparison,
): boolean {
  return (
    comparison.comparableAnswers >= HUMOR_QA_MIN_COMPARABLE &&
    comparison.matchingAnswers >= HUMOR_QA_MIN_MATCHING &&
    comparison.score >= HUMOR_QA_MIN_SCORE
  );
}

/** Mirrors HumorAnswerComparator.confidence (Dart). */
export function humorAnswerConfidence(
  comparison: HumorAnswerComparison,
): number {
  if (comparison.comparableAnswers <= 0) {
    return 0;
  }
  const coverage = Math.min(1, comparison.comparableAnswers / 5);
  const alignment = comparison.similarity;
  return Math.min(1, Math.max(0.35, 0.5 * coverage + 0.5 * alignment));
}

export function humorAnswerStrength(
  comparison: HumorAnswerComparison,
): "weak" | "moderate" | "strong" {
  if (
    meetsHumorAnswerReasonThreshold(comparison) &&
    comparison.score >= HUMOR_QA_STRONG_MIN_SCORE &&
    comparison.comparableAnswers >= HUMOR_QA_STRONG_MIN_COMPARABLE
  ) {
    return "strong";
  }
  if (
    meetsHumorAnswerReasonThreshold(comparison) &&
    comparison.comparableAnswers < HUMOR_QA_STRONG_MIN_COMPARABLE
  ) {
    // Insufficient sample — never emit strong even if score is high (Dart parity).
    return comparison.score >= 50 ? "moderate" : "weak";
  }
  if (comparison.score >= 50) {
    return "moderate";
  }
  return "weak";
}
