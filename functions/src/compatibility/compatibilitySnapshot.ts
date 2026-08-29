import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {calculateCompatibility} from "./compatibilityEngine.js";
import {musicScoreForPair} from "../spotifyMusic.js";
import {relationshipScoreForPair} from "../relationshipMatch.js";

const db = getFirestore();

/** Firestore-safe snapshot for one viewer's perspective of a pair. */
export type CompatibilitySnapshotPayload = {
  compatibilityScore: number;
  compatibilityBreakdown: {
    overallScore: number;
    relationshipScore: number;
    interestScore: number;
    lifestyleScore: number;
    questionScore: number | null;
    musicScore: number | null;
    communicationScore: number | null;
  };
  sharedInterests: string[];
  compatibilityReasons: string[];
};

export type MatchCompatibilityFields = {
  compatibilitySnapshots: Record<string, CompatibilitySnapshotPayload>;
  compatibilityCalculatedAt: ReturnType<typeof FieldValue.serverTimestamp>;
};

function payloadFromBreakdown(
  compat: ReturnType<typeof calculateCompatibility>,
): CompatibilitySnapshotPayload {
  return {
    compatibilityScore: compat.overallScore,
    compatibilityBreakdown: {
      overallScore: compat.overallScore,
      relationshipScore: compat.relationshipScore,
      interestScore: compat.interestScore,
      lifestyleScore: compat.lifestyleScore,
      questionScore: compat.questionScore,
      musicScore: compat.musicScore,
      communicationScore: compat.communicationScore,
    },
    sharedInterests: compat.sharedInterests,
    compatibilityReasons: compat.reasons,
  };
}

/**
 * Build a single-perspective snapshot from already-loaded profiles.
 * Does not fetch music/relationship — callers may pass those when available.
 * Uses the same calculateCompatibility() as Discovery.
 */
export function buildCompatibilitySnapshotFromProfiles(input: {
  viewerProfile: DocumentData;
  candidateProfile: DocumentData;
  relationship?: {
    score: number;
    alignedCount: number;
    sharedQuestionCount: number;
    topTopics: string[];
  } | null;
  musicScore?: number | null;
}): CompatibilitySnapshotPayload {
  const compat = calculateCompatibility({
    viewerProfile: input.viewerProfile,
    candidateProfile: input.candidateProfile,
    relationship: input.relationship ?? null,
    musicScore: input.musicScore ?? null,
  });
  return payloadFromBreakdown(compat);
}

/**
 * Dual-perspective match snapshot at mutual-match time.
 * Failures return empty object so match creation is never blocked.
 */
export async function buildMatchCompatibilityFields(
  uidA: string,
  uidB: string,
): Promise<Partial<MatchCompatibilityFields>> {
  try {
    const [profileA, profileB, music, relationshipAB, relationshipBA] = await Promise.all([
      db.doc(`profiles/${uidA}`).get(),
      db.doc(`profiles/${uidB}`).get(),
      musicScoreForPair(uidA, uidB),
      relationshipScoreForPair(uidA, uidB),
      relationshipScoreForPair(uidB, uidA),
    ]);
    if (!profileA.exists || !profileB.exists) {
      return {};
    }
    const dataA = profileA.data() ?? {};
    const dataB = profileB.data() ?? {};
    const musicScore = music?.score ?? null;

    const forA = buildCompatibilitySnapshotFromProfiles({
      viewerProfile: dataA,
      candidateProfile: dataB,
      relationship: relationshipAB
        ? {
            score: relationshipAB.score,
            alignedCount: relationshipAB.alignedCount,
            sharedQuestionCount: relationshipAB.sharedQuestionCount,
            topTopics: relationshipAB.topTopics ?? [],
          }
        : null,
      musicScore,
    });
    const forB = buildCompatibilitySnapshotFromProfiles({
      viewerProfile: dataB,
      candidateProfile: dataA,
      relationship: relationshipBA
        ? {
            score: relationshipBA.score,
            alignedCount: relationshipBA.alignedCount,
            sharedQuestionCount: relationshipBA.sharedQuestionCount,
            topTopics: relationshipBA.topTopics ?? [],
          }
        : null,
      musicScore,
    });

    return {
      compatibilitySnapshots: {
        [uidA]: forA,
        [uidB]: forB,
      },
      compatibilityCalculatedAt: FieldValue.serverTimestamp(),
    };
  } catch (error) {
    console.error("buildMatchCompatibilityFields failed", {uidA, uidB, error});
    return {};
  }
}

/**
 * Preserve prior compatibility snapshots on rematch only when recalculation
 * fails; otherwise callers replace with a fresh snapshot.
 */
export function preservedCompatibilityFields(existing?: DocumentData | null): Record<string, unknown> {
  if (!existing) {
    return {};
  }
  const out: Record<string, unknown> = {};
  if (existing.compatibilitySnapshots && typeof existing.compatibilitySnapshots === "object") {
    out.compatibilitySnapshots = existing.compatibilitySnapshots;
  }
  if (existing.compatibilityCalculatedAt) {
    out.compatibilityCalculatedAt = existing.compatibilityCalculatedAt;
  }
  return out;
}
