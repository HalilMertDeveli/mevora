import {answerAgreement, learningTopicOf} from "./catalog.js";
import {EVIDENCE} from "./config.js";

/**
 * Relationship-question compatibility between two members, from the answers
 * they gave to the SAME question ids (a versioned id is never compared with
 * another version). Each shared question contributes its agreement (0..1)
 * under the question's own rule — exact, distance or matrix.
 *
 * Pure: two answer maps in, one result out.
 */

export interface LearningPairScore {
  /** Questions both answered. */
  shared: number;
  /** Sum of per-question agreement. */
  agreement: number;
  /** Shared questions with agreement >= EVIDENCE.alignedAtLeast. */
  aligned: number;
  /** Topic -> aligned count, for "why this person" copy. */
  topicHits: Map<string, number>;
}

export function scoreLearningAnswers(
  viewer: Record<string, string>,
  candidate: Record<string, string>,
): LearningPairScore {
  const result: LearningPairScore = {shared: 0, agreement: 0, aligned: 0, topicHits: new Map()};
  for (const [questionId, viewerAnswer] of Object.entries(viewer)) {
    const candidateAnswer = candidate[questionId];
    if (candidateAnswer === undefined) continue;
    const agreement = answerAgreement(questionId, viewerAnswer, candidateAnswer);
    if (agreement === null) continue;
    result.shared += 1;
    result.agreement += agreement;
    if (agreement >= EVIDENCE.alignedAtLeast) {
      result.aligned += 1;
      const topic = learningTopicOf(questionId);
      if (topic) result.topicHits.set(topic, (result.topicHits.get(topic) ?? 0) + 1);
    }
  }
  return result;
}

/**
 * Confidence in a question score from how many answers two people share:
 * shared / (shared + prior). A pair with 10 shared answers is not treated
 * like a pair with 200.
 */
export function evidenceConfidence(shared: number): number {
  if (!Number.isFinite(shared) || shared <= 0) return 0;
  return shared / (shared + EVIDENCE.priorSharedAnswers);
}

/** Shrinks a 0-100 agreement score toward the neutral 50 by confidence. */
export function confidentScore(rawScore: number, shared: number): number {
  const confidence = evidenceConfidence(shared);
  const score = 50 + (rawScore - 50) * confidence;
  return Math.max(0, Math.min(100, Math.round(score)));
}
