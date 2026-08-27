/**
 * Compatibility Reveal — build match discovery points from verified signals only.
 * Never invents Spotify / question / personality overlaps without real data.
 */

export type RevealPointKind =
  | "personality"
  | "questions"
  | "music"
  | "relationship"
  | "preference"
  | "lifestyle";

export type RevealPoint = {
  kind: RevealPointKind;
  /** Client l10n key — never free-form AI copy. */
  messageKey: string;
  messageArgs: string[];
  /** Optional category score when known (premium breakdown). */
  score?: number;
};

export type RevealBreakdownScores = {
  relationshipScore: number;
  interestScore: number;
  lifestyleScore: number;
  questionScore: number | null;
  musicScore: number | null;
  communicationScore: number | null;
};

export type CompatibilityRevealInput = {
  overallScore: number;
  isPremium: boolean;
  sharedInterests: string[];
  sameRelationshipGoal: boolean;
  relationshipGoalLabel?: string | null;
  questionAlignedCount: number | null;
  questionSharedCount: number | null;
  questionScore: number | null;
  /** Top relationship topics from aligned answers (e.g. personality, communication). */
  questionTopTopics: string[];
  musicScore: number | null;
  lifestyleScore: number | null;
  communicationScore: number | null;
  breakdown: RevealBreakdownScores;
};

export type CompatibilityRevealResult = {
  available: boolean;
  overallScore: number;
  isPremium: boolean;
  premiumRequired: boolean;
  /** Free: ≤2 basic points. Premium: ≤3. */
  points: RevealPoint[];
  /** Premium-only category scores. Empty for free. */
  breakdown: RevealBreakdownScores | null;
  reason?: string;
};

const FREE_LIMIT = 2;
const PREMIUM_LIMIT = 3;

function clampScore(score: number): number {
  return Math.max(0, Math.min(100, Math.round(score)));
}

/**
 * Ordered candidates. Only append when the underlying signal is present.
 */
export function collectRevealPoints(input: CompatibilityRevealInput): RevealPoint[] {
  const points: RevealPoint[] = [];

  const hasQuestions =
    input.questionSharedCount != null &&
    input.questionSharedCount > 0 &&
    input.questionAlignedCount != null &&
    input.questionAlignedCount > 0 &&
    input.questionScore != null;

  // 1) Personality tendency — only from verified question topics or lifestyle.
  const personalityTopics = new Set([
    "personality",
    "values",
    "life_values",
    "trust",
    "boundaries",
    "personalSpace",
    "expectations",
    "loyalty",
    "friendship",
  ]);
  const personalityTopic = input.questionTopTopics.find((topic) =>
    personalityTopics.has(topic),
  );
  if (hasQuestions && personalityTopic) {
    points.push({
      kind: "personality",
      messageKey: "compatRevealPersonalityAligned",
      messageArgs: [`${input.questionAlignedCount}`],
      score: input.questionScore ?? undefined,
    });
  } else if (
    input.lifestyleScore != null &&
    input.lifestyleScore >= 70 &&
    !personalityTopic
  ) {
    // Lifestyle similarity as a soft personality signal — only when score is real.
    points.push({
      kind: "personality",
      messageKey: "compatRevealSimilarPersonality",
      messageArgs: [],
      score: input.lifestyleScore,
    });
  }

  // 2) Question answers — counts only (never answer text).
  if (hasQuestions) {
    points.push({
      kind: "questions",
      messageKey: "compatReasonSameAnswers",
      messageArgs: [
        `${input.questionAlignedCount}`,
        `${input.questionSharedCount}`,
      ],
      score: input.questionScore ?? undefined,
    });
  }

  // 3) Music — only when both sides produced a real music score.
  if (input.musicScore != null && input.musicScore > 0) {
    points.push({
      kind: "music",
      messageKey: "compatReasonSimilarMusic",
      messageArgs: [`${clampScore(input.musicScore)}`],
      score: clampScore(input.musicScore),
    });
  }

  // 4) Relationship goal — only when both set the same goal.
  if (input.sameRelationshipGoal && input.relationshipGoalLabel) {
    points.push({
      kind: "relationship",
      messageKey: "compatReasonSameRelationshipGoal",
      messageArgs: [input.relationshipGoalLabel],
      score: input.breakdown.relationshipScore,
    });
  }

  // 5) Shared interests / preference.
  if (input.sharedInterests.length > 0) {
    points.push({
      kind: "preference",
      messageKey: "compatReasonSharedInterests",
      messageArgs: input.sharedInterests.slice(0, 3),
      score: input.breakdown.interestScore,
    });
  }

  // 6) Communication style from verified topics.
  if (
    input.communicationScore != null &&
    input.communicationScore >= 75 &&
    input.questionTopTopics.includes("communication")
  ) {
    points.push({
      kind: "lifestyle",
      messageKey: "compatReasonCommunication",
      messageArgs: [],
      score: input.communicationScore,
    });
  }

  return points;
}

export function buildCompatibilityReveal(
  input: CompatibilityRevealInput,
): CompatibilityRevealResult {
  const overallScore = clampScore(input.overallScore);
  const allPoints = collectRevealPoints(input);

  if (allPoints.length === 0 || overallScore <= 0) {
    return {
      available: false,
      overallScore,
      isPremium: input.isPremium,
      premiumRequired: !input.isPremium,
      points: [],
      breakdown: null,
      reason: "insufficient_data",
    };
  }

  const limit = input.isPremium ? PREMIUM_LIMIT : FREE_LIMIT;
  const points = allPoints.slice(0, limit);

  return {
    available: true,
    overallScore,
    isPremium: input.isPremium,
    premiumRequired: !input.isPremium,
    points,
    breakdown: input.isPremium ? input.breakdown : null,
  };
}
