import type {DocumentData} from "firebase-admin/firestore";

export interface CompatibilityBreakdown {
  overallScore: number;
  relationshipScore: number;
  interestScore: number;
  lifestyleScore: number;
  questionScore: number | null;
  musicScore: number | null;
  communicationScore: number | null;
  proximityScore: number | null;
  activityScore: number | null;
  sharedInterests: string[];
  reasons: string[];
  questionAlignedCount: number | null;
  questionSharedCount: number | null;
}

const WEIGHTS = {
  profile: 0.4,
  questions: 0.3,
  music: 0.15,
} as const;

function normTags(values: string[] | undefined): Set<string> {
  return new Set((values ?? []).map((item) => item.trim().toLowerCase()).filter(Boolean));
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) {
    return 0.5;
  }
  let shared = 0;
  for (const item of a) {
    if (b.has(item)) {
      shared++;
    }
  }
  const union = new Set([...a, ...b]).size;
  return union === 0 ? 0.5 : shared / union;
}

function relationshipGoalScore(a: DocumentData, b: DocumentData): number {
  const ga = String(a.relationshipGoal ?? "").trim().toLowerCase();
  const gb = String(b.relationshipGoal ?? "").trim().toLowerCase();
  if (!ga || !gb) {
    return 50;
  }
  return ga === gb ? 100 : 35;
}

function lifestyleScore(a: DocumentData, b: DocumentData): number {
  const tagsA = normTags((a.lifestyle as string[]) ?? lifestyleTagsFromProfile(a));
  const tagsB = normTags((b.lifestyle as string[]) ?? lifestyleTagsFromProfile(b));
  if (tagsA.size === 0 || tagsB.size === 0) {
    return 50;
  }
  let shared = 0;
  for (const tag of tagsA) {
    if (tagsB.has(tag)) {
      shared++;
    }
  }
  return Math.round((shared / tagsA.size) * 100);
}

function lifestyleTagsFromProfile(data: DocumentData): string[] {
  const profile = data.lifestyleProfile as Record<string, string> | undefined;
  if (!profile) {
    return [];
  }
  return Object.entries(profile)
    .filter(([, value]) => value)
    .map(([key, value]) => `${key}:${value}`.toLowerCase());
}

function activityScore(data: DocumentData): number {
  const raw = data.lastActiveAt;
  if (!raw || typeof (raw as {toDate?: () => Date}).toDate !== "function") {
    return 40;
  }
  const hours = (Date.now() - (raw as {toDate: () => Date}).toDate().getTime()) / 3_600_000;
  if (hours <= 24) return 100;
  if (hours <= 72) return 70;
  if (hours <= 24 * 14) return 40;
  return 15;
}

function profileScore(viewer: DocumentData, candidate: DocumentData): number {
  const interests = Math.round(jaccard(normTags(viewer.interests as string[]), normTags(candidate.interests as string[])) * 100);
  const goal = relationshipGoalScore(viewer, candidate);
  const lifestyle = lifestyleScore(viewer, candidate);
  const activity = activityScore(candidate);
  return Math.round(interests * 0.35 + goal * 0.25 + lifestyle * 0.2 + activity * 0.2);
}

export function calculateCompatibility(input: {
  viewerProfile: DocumentData;
  candidateProfile: DocumentData;
  relationship?: {
    score: number;
    alignedCount: number;
    sharedQuestionCount: number;
    topTopics: string[];
  } | null;
  musicScore?: number | null;
}): CompatibilityBreakdown {
  const viewer = input.viewerProfile;
  const candidate = input.candidateProfile;
  const viewerInterests = normTags(viewer.interests as string[]);
  const sharedInterests = ((candidate.interests as string[]) ?? []).filter((item) =>
    viewerInterests.has(item.trim().toLowerCase()),
  );

  const relationshipScore = relationshipGoalScore(viewer, candidate);
  const interestScore = Math.round(
    jaccard(viewerInterests, normTags(candidate.interests as string[])) * 100,
  );
  const lifestyle = lifestyleScore(viewer, candidate);
  const activity = activityScore(candidate);
  const profile = profileScore(viewer, candidate);

  const questionScore = input.relationship?.sharedQuestionCount
    ? input.relationship.score
    : null;
  const musicScore = input.musicScore ?? null;

  const parts: Array<{weight: number; score: number}> = [{weight: WEIGHTS.profile, score: profile}];
  if (questionScore != null) {
    parts.push({weight: WEIGHTS.questions, score: questionScore});
  }
  if (musicScore != null) {
    parts.push({weight: WEIGHTS.music, score: musicScore});
  }
  const weightSum = parts.reduce((sum, part) => sum + part.weight, 0);
  const overallScore = Math.round(
    parts.reduce((sum, part) => sum + part.score * part.weight, 0) / weightSum,
  );

  const reasons: string[] = [];
  if (sharedInterests.length) reasons.push("Shared interests");
  if (relationshipScore >= 85) reasons.push("Same relationship goal");
  if (questionScore != null && (input.relationship?.alignedCount ?? 0) > 0) {
    reasons.push("Similar relationship views");
  }
  if (musicScore != null && musicScore >= 70) reasons.push("Similar music taste");
  if (lifestyle >= 70) reasons.push("Similar lifestyle");

  const communicationScore =
    input.relationship?.topTopics?.includes("communication") && questionScore != null
      ? questionScore
      : null;

  return {
    overallScore: Math.min(100, Math.max(0, overallScore)),
    relationshipScore,
    interestScore,
    lifestyleScore: lifestyle,
    questionScore,
    musicScore,
    communicationScore,
    proximityScore: null,
    activityScore: activity,
    sharedInterests,
    reasons,
    questionAlignedCount: input.relationship?.alignedCount ?? null,
    questionSharedCount: input.relationship?.sharedQuestionCount ?? null,
  };
}

/**
 * Which of the profile-based dimensions above rest on real data from both
 * sides, rather than on the neutral 50 the engine substitutes when either
 * person left that part of their profile empty.
 *
 * The scores stay what they are; this only says which of them count as
 * evidence. A feature that explains a recommendation must not cite a
 * dimension that was never measured.
 */
export interface CompatibilityEvidence {
  relationshipGoal: boolean;
  interests: boolean;
  lifestyle: boolean;
}

export function compatibilityEvidence(
  viewer: DocumentData,
  candidate: DocumentData,
): CompatibilityEvidence {
  const goal = (data: DocumentData) => String(data.relationshipGoal ?? "").trim().length > 0;
  const lifestyleTags = (data: DocumentData) =>
    normTags((data.lifestyle as string[]) ?? lifestyleTagsFromProfile(data));
  return {
    relationshipGoal: goal(viewer) && goal(candidate),
    interests:
      normTags(viewer.interests as string[]).size > 0 &&
      normTags(candidate.interests as string[]).size > 0,
    lifestyle: lifestyleTags(viewer).size > 0 && lifestyleTags(candidate).size > 0,
  };
}

/** Legacy ranking helper — keeps old additive formula for tests if needed. */
export function legacyCompatibilityScore(viewer: DocumentData, candidate: DocumentData) {
  const viewerInterests = new Set<string>((viewer.interests as string[]) ?? []);
  const shared = ((candidate.interests as string[]) ?? []).filter((item) =>
    viewerInterests.has(item),
  );
  const sharedScore = Math.min(25, shared.length * 5);
  const goalScore =
    viewer.relationshipGoal && viewer.relationshipGoal === candidate.relationshipGoal ? 20 : 0;
  return {
    score: Math.round(sharedScore + goalScore),
    sharedInterests: shared,
    reasons: [
      ...(shared.length ? ["Shared interests"] : []),
      ...(goalScore ? ["Same relationship goal"] : []),
    ],
  };
}
