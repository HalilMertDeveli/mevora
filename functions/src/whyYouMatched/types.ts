/** Sanitized Why You Matched reason DTO (client-safe). */
export type WhyYouMatchedReasonDto = {
  id: string;
  category: string;
  score: number;
  strength: "weak" | "moderate" | "strong";
  confidence: number;
  priority: number;
  titleKey: string;
  descriptionKey: string;
  descriptionArgs: string[];
  evidence: {
    type: string;
    values: Record<string, string | number | boolean | string[]>;
  };
};

export type WhyYouMatchedResponse = {
  available: boolean;
  reason?: string;
  overallScore: number | null;
  peerUid: string | null;
  distanceKm: number | null;
  reasons: WhyYouMatchedReasonDto[];
  cacheHit: boolean;
  generatedAtMs: number;
  /** Server-only bookkeeping — stripped before client response. */
  _reads?: number;
};

export const WHY_YOU_MATCHED_CACHE_TTL_MS = 30 * 60 * 1000; // 30 min
export const WHY_YOU_MATCHED_TOP_N = 3;
export const WHY_YOU_MATCHED_MAX_KM = 25;
