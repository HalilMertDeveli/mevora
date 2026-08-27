import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {calculateCompatibility} from "./compatibility/compatibilityEngine.js";
import {
  buildCompatibilityReveal,
  type CompatibilityRevealResult,
} from "./compatibilityRevealEngine.js";
import {resolveMatchParticipant} from "./compatibilityRevealGate.js";
import {canonicalMatchId} from "./ids.js";
import {isUserPremium} from "./premium.js";
import {relationshipScoreForPair} from "./relationshipMatch.js";
import {musicScoreForPair} from "./spotifyMusic.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", field);
  }
  return value.trim();
}

function goalLabel(raw: unknown): string | null {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!value) return null;
  const normalized = value.replace(/_/g, "").toLowerCase();
  if (normalized === "longterm") return "longTerm";
  if (normalized === "casual") return "casual";
  if (normalized === "figuringout" || normalized === "figuring_out") {
    return "figuringOut";
  }
  return value;
}

function sameGoal(a: DocumentData, b: DocumentData): boolean {
  const ga = goalLabel(a.relationshipGoal);
  const gb = goalLabel(b.relationshipGoal);
  return ga != null && gb != null && ga === gb;
}

async function requireActiveMatchParticipant(
  matchId: string,
  uid: string,
): Promise<{peerUid: string}> {
  const snap = await db.doc(`matches/${matchId}`).get();
  const data = snap.data() ?? {};
  const gated = resolveMatchParticipant({
    matchId,
    uid,
    matchExists: snap.exists,
    isActive: data.isActive as boolean | undefined,
    userIds: data.userIds,
    canonicalMatchId,
  });
  if (!gated.ok) {
    if (gated.code === "not-found") {
      throw new HttpsError("not-found", "match-not-found");
    }
    if (gated.code === "match-inactive") {
      throw new HttpsError("failed-precondition", "match-inactive");
    }
    if (gated.code === "not-a-participant" || gated.code === "match-id-mismatch") {
      throw new HttpsError("permission-denied", gated.code);
    }
    throw new HttpsError("failed-precondition", gated.code);
  }
  return {peerUid: gated.peerUid};
}

/**
 * Post-match Compatibility Reveal.
 *
 * Free: overall score + up to 2 basic verified reasons (no answer text).
 * Premium: up to 3 reasons + category breakdown.
 * Never fabricates music/question/personality overlaps without real data.
 */
export const getMatchCompatibilityReveal = onCall(
  callableOptions,
  async (request): Promise<CompatibilityRevealResult> => {
    const uid = requireUid(request);
    const matchId = requireString(request.data?.matchId, "matchId");
    const {peerUid} = await requireActiveMatchParticipant(matchId, uid);
    const premium = await isUserPremium(uid);

    const [viewerSnap, peerSnap, relationship, music] = await Promise.all([
      db.doc(`profiles/${uid}`).get(),
      db.doc(`profiles/${peerUid}`).get(),
      relationshipScoreForPair(uid, peerUid),
      musicScoreForPair(uid, peerUid),
    ]);

    if (!viewerSnap.exists || !peerSnap.exists) {
      return {
        available: false,
        overallScore: 0,
        isPremium: premium,
        premiumRequired: !premium,
        points: [],
        breakdown: null,
        reason: "profile_missing",
      };
    }

    const viewer = viewerSnap.data() ?? {};
    const peer = peerSnap.data() ?? {};
    const musicScore =
      music && typeof music.score === "number" && music.score > 0
        ? music.score
        : null;

    const compat = calculateCompatibility({
      viewerProfile: viewer,
      candidateProfile: peer,
      relationship: relationship
        ? {
            score: relationship.score,
            alignedCount: relationship.alignedCount,
            sharedQuestionCount: relationship.sharedQuestionCount,
            topTopics: relationship.topTopics ?? [],
          }
        : null,
      musicScore,
    });

    const label = goalLabel(viewer.relationshipGoal);

    return buildCompatibilityReveal({
      overallScore: compat.overallScore,
      isPremium: premium,
      sharedInterests: compat.sharedInterests,
      sameRelationshipGoal: sameGoal(viewer, peer),
      relationshipGoalLabel: sameGoal(viewer, peer) ? label : null,
      questionAlignedCount: compat.questionAlignedCount,
      questionSharedCount: compat.questionSharedCount,
      questionScore: compat.questionScore,
      questionTopTopics: relationship?.topTopics ?? [],
      musicScore,
      lifestyleScore: compat.lifestyleScore,
      communicationScore: compat.communicationScore,
      breakdown: {
        relationshipScore: compat.relationshipScore,
        interestScore: compat.interestScore,
        lifestyleScore: compat.lifestyleScore,
        questionScore: compat.questionScore,
        musicScore: compat.musicScore,
        communicationScore: compat.communicationScore,
      },
    });
  },
);
