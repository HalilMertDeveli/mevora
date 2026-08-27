export type PartnerQuestionAnswerRow = {
  questionId: string;
  answerId: string;
  isVisible: boolean;
};

export type PartnerQuestionAnswersPayload = {
  locked: boolean;
  matchRequired: boolean;
  premiumRequired: boolean;
  isPremium: boolean;
  /** Always safe to send — question ids only (catalog is public). */
  questions: Array<{questionId: string}>;
  /** Answer fields only when Premium + active match. */
  answers: PartnerQuestionAnswerRow[];
};

/**
 * Pure gate: free clients never receive answerId / answer text.
 * Question ids remain visible so UI can show prompts with a Premium lock CTA.
 */
export function shapePartnerQuestionAnswers(input: {
  matched: boolean;
  isPremium: boolean;
  rows: PartnerQuestionAnswerRow[];
}): PartnerQuestionAnswersPayload {
  if (!input.matched) {
    return {
      locked: true,
      matchRequired: true,
      premiumRequired: false,
      isPremium: input.isPremium,
      questions: [],
      answers: [],
    };
  }

  const visible = input.rows.filter(
    (row) => row.isVisible && row.questionId.length > 0 && row.answerId.length > 0,
  );
  const questions = visible.map((row) => ({questionId: row.questionId}));

  if (!input.isPremium) {
    return {
      locked: true,
      matchRequired: false,
      premiumRequired: true,
      isPremium: false,
      questions,
      answers: [],
    };
  }

  return {
    locked: false,
    matchRequired: false,
    premiumRequired: false,
    isPremium: true,
    questions,
    answers: visible,
  };
}
