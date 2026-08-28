/**
 * Documented WYM calculation thresholds shared between client generators and
 * server reasonBuilder semantics. Values mirror Dart unless noted.
 */

/** Humor Lab — humorScoreForPair + HumorReasonCalculator */
export const WYM_HUMOR_LAB_MIN_SCORE = 60;
export const WYM_HUMOR_LAB_MIN_CONFIDENCE = 0.15;

/** Music — requires both users connected; score-only fallback min */
export const WYM_MUSIC_SCORE_ONLY_MIN = 70;
export const WYM_MUSIC_SCORE_ONLY_CONFIDENCE = 0.45;

/** Interests — InterestComparator + reasonBuilder floor */
export const WYM_INTEREST_MIN_COMMON = 1;
export const WYM_INTEREST_MIN_SCORE = 40;

/** Lifestyle tag overlap (server reasonBuilder) */
export const WYM_LIFESTYLE_MIN_SCORE = 70;
export const WYM_LIFESTYLE_MIN_SHARED_TAGS = 1;

/** Communication / relationship Q&A topic */
export const WYM_COMMUNICATION_MIN_SCORE = 75;
export const WYM_COMMUNICATION_ALIGNED_RATIO = 0.75;

/** Distance — rounded km only in evidence */
export const WYM_DISTANCE_MAX_KM = 25;
export const WYM_DISTANCE_NEARBY_KM = 5;

/** Evidence type strings (client + server must stay aligned). */
export const WYM_EVIDENCE_TYPES = [
  "commonInterests",
  "commonArtists",
  "commonTracks",
  "commonGenres",
  "musicSimilarity",
  "sharedHumorAnswers",
  "humorVectorSimilarity",
  "lifestyleOverlap",
  "sharedLanguages",
  "communicationAlignment",
  "proximityKm",
] as const;

export type WymEvidenceType = (typeof WYM_EVIDENCE_TYPES)[number];
