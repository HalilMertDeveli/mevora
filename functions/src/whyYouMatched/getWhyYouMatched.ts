import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {calculateCompatibility} from "../compatibility/compatibilityEngine.js";
import {humorScoreForPair} from "../humor/compatibility.js";
import {loadUserHumorProfile} from "../humor/feed.js";
import {relationshipScoreForPair} from "../relationshipMatch.js";
import {musicScoreForPair} from "../spotifyMusic.js";
import {buildWhyYouMatchedReasons} from "./reasonBuilder.js";
import {compareHumorAnswers} from "./humorAnswerComparison.js";
import {loadRelationshipAnswers} from "./relationshipAnswersLoader.js";
import {pickRequestFields, sanitizeForClient} from "./sanitize.js";
import {
  WHY_YOU_MATCHED_CACHE_TTL_MS,
  type WhyYouMatchedResponse,
} from "./types.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const sLat = Math.sin(dLat / 2);
  const sLng = Math.sin(dLng / 2);
  const h =
    sLat * sLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sLng * sLng;
  return 2 * 6371 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

function asStringList(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.map((item) => String(item ?? "").trim()).filter(Boolean);
}

const LIFESTYLE_SCALAR_FIELDS = [
  "smoking",
  "drinking",
  "exercise",
  "pets",
  "socialRhythm",
  "socialLevel",
  "cohabitationPreference",
] as const;

const LIFESTYLE_EXCLUDED_PROFILE_FIELDS = new Set([
  "partnerSmokingPref",
  "partnerDrinkingPref",
  "childrenPreference",
  "partnerChildrenPref",
  "weekendPreferences",
]);

function lifestyleTagsFromProfile(data: DocumentData | undefined): string[] {
  if (!data) return [];
  const tags = asStringList(data.lifestyle);
  if (tags.length) return tags.map((t) => t.toLowerCase());

  const profile = data.lifestyleProfile as Record<string, unknown> | undefined;
  if (!profile) return [];

  const out: string[] = [];
  for (const field of LIFESTYLE_SCALAR_FIELDS) {
    const value = profile[field];
    if (typeof value === "string" && value.trim()) {
      out.push(`${field}:${value.trim().toLowerCase()}`);
    }
  }

  const weekends = profile.weekendPreferences;
  if (Array.isArray(weekends)) {
    for (const pref of weekends) {
      if (typeof pref === "string" && pref.trim()) {
        out.push(`weekend:${pref.trim().toLowerCase()}`);
      }
    }
  }

  // Ignore partner preference / children fields — not shared lifestyle evidence.
  for (const key of Object.keys(profile)) {
    if (
      LIFESTYLE_EXCLUDED_PROFILE_FIELDS.has(key) ||
      LIFESTYLE_SCALAR_FIELDS.includes(key as (typeof LIFESTYLE_SCALAR_FIELDS)[number])
    ) {
      continue;
    }
  }

  return out;
}

function cacheDocPath(matchId: string, viewerUid: string): string {
  return `matches/${matchId}/meta/whyYouMatched_${viewerUid}`;
}

function emptyResponse(
  reason: string,
  extras: Partial<WhyYouMatchedResponse> = {},
): WhyYouMatchedResponse {
  return sanitizeForClient({
    available: false,
    reason,
    overallScore: null,
    peerUid: null,
    distanceKm: null,
    reasons: [],
    cacheHit: false,
    generatedAtMs: Date.now(),
    ...extras,
  });
}

/**
 * Match-scoped Why You Matched reasons.
 *
 * Client/server split:
 * - Server: authoritative scores + evidence aggregates (this callable)
 * - Client: localization / display only — must not invent reasons or override scores
 *
 * Reads (cold miss): match(1) + cache(1) + profiles(2) + locations(2) +
 * music(2) + relationship(2) + humor(2) = 12 docs; warm: match + cache = 2;
 * forceRefresh: 11 (skips cache read).
 */
export const getWhyYouMatched = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const {matchId, forceRefresh} = pickRequestFields(request.data);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "matchId");
  }

  const matchRef = db.doc(`matches/${matchId}`);
  const matchSnap = await matchRef.get();

  if (!matchSnap.exists || matchSnap.data()?.isActive !== true) {
    return emptyResponse("no_match");
  }

  const userIds = (matchSnap.data()?.userIds as string[]) ?? [];
  if (!userIds.includes(uid) || userIds.length !== 2) {
    throw new HttpsError("permission-denied", "not-participant");
  }
  const peerUid = userIds.find((id) => id !== uid);
  if (!peerUid) {
    return emptyResponse("invalid_match");
  }

  const cacheRef = db.doc(cacheDocPath(matchId, uid));
  if (!forceRefresh) {
    const cacheSnap = await cacheRef.get();
    if (cacheSnap.exists) {
      const cached = cacheSnap.data() as WhyYouMatchedResponse & {
        expiresAtMs?: number;
      };
      if (
        cached?.available &&
        typeof cached.expiresAtMs === "number" &&
        cached.expiresAtMs > Date.now() &&
        Array.isArray(cached.reasons)
      ) {
        return sanitizeForClient({
          ...cached,
          peerUid,
          cacheHit: true,
        });
      }
    }
  }

  const [viewerProfileSnap, peerProfileSnap, locA, locB, viewerAnswers, peerAnswers, music, relationship, humorA, humorB] = await Promise.all([
    db.doc(`profiles/${uid}`).get(),
    db.doc(`profiles/${peerUid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.doc(`userLocation/${peerUid}`).get(),
    loadRelationshipAnswers(db, uid),
    loadRelationshipAnswers(db, peerUid),
    musicScoreForPair(uid, peerUid),
    relationshipScoreForPair(uid, peerUid),
    loadUserHumorProfile(db, uid),
    loadUserHumorProfile(db, peerUid),
  ]);

  const viewerProfile = viewerProfileSnap.data() ?? {};
  const peerProfile = peerProfileSnap.data() ?? {};

  const humorQa = compareHumorAnswers(viewerAnswers, peerAnswers);
  const humor = humorScoreForPair(humorA, humorB);
  const compat = calculateCompatibility({
    viewerProfile,
    candidateProfile: peerProfile,
    relationship: relationship
      ? {
          score: relationship.score,
          alignedCount: relationship.alignedCount,
          sharedQuestionCount: relationship.sharedQuestionCount,
          topTopics: relationship.topTopics ?? [],
        }
      : null,
    musicScore: music?.score ?? null,
  });

  let distanceKm: number | null = null;
  const a = locA.data();
  const b = locB.data();
  if (
    a &&
    b &&
    typeof a.lat === "number" &&
    typeof a.lng === "number" &&
    typeof b.lat === "number" &&
    typeof b.lng === "number"
  ) {
    const km = haversineKm(a.lat, a.lng, b.lat, b.lng);
    if (Number.isFinite(km) && km >= 0) {
      distanceKm = Math.round(km * 10) / 10;
    }
  }

  const topTopics = relationship?.topTopics ?? [];
  const reasons = buildWhyYouMatchedReasons({
    viewerUid: uid,
    peerUid,
    viewerInterests: asStringList(viewerProfile.interests),
    peerInterests: asStringList(peerProfile.interests),
    viewerLanguages: asStringList(viewerProfile.languages),
    peerLanguages: asStringList(peerProfile.languages),
    viewerLifestyleTags: lifestyleTagsFromProfile(viewerProfile),
    peerLifestyleTags: lifestyleTagsFromProfile(peerProfile),
    musicScore: music?.score ?? null,
    sharedArtistNames: (music?.sharedArtistNames ?? []).slice(0, 5),
    sharedArtistCount: music?.sharedArtists?.length ?? 0,
    sharedTrackCount: music?.sharedTracks?.length ?? 0,
    sharedGenreNames: (music?.sharedGenres ?? []).slice(0, 5),
    humorScore: humor.available ? humor.score : null,
    humorConfidence: humor.confidence ?? 0,
    humorSharedDims: (humor.strongestShared ?? []).map(String).slice(0, 5),
    humorMatchingAnswers:
      humorQa.comparableAnswers >= 2 ? humorQa.matchingAnswers : null,
    humorComparableAnswers:
      humorQa.comparableAnswers >= 2 ? humorQa.comparableAnswers : null,
    questionAlignedCount: relationship?.alignedCount ?? null,
    questionSharedCount: relationship?.sharedQuestionCount ?? null,
    communicationTopic: topTopics.some(
      (t: string) => String(t).toLowerCase() === "communication",
    ),
    distanceKm,
    overallScore: compat.overallScore,
  });

  const generatedAtMs = Date.now();
  const payload: WhyYouMatchedResponse = {
    available: reasons.length > 0,
    reason: reasons.length > 0 ? undefined : "not_enough_data",
    overallScore: compat.overallScore,
    peerUid,
    distanceKm,
    reasons,
    cacheHit: false,
    generatedAtMs,
  };

  const sanitized = sanitizeForClient(payload);

  // Cache for participants (Admin SDK). Clients cannot write this meta doc.
  await cacheRef.set(
    {
      ...sanitized,
      expiresAtMs: generatedAtMs + WHY_YOU_MATCHED_CACHE_TTL_MS,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  return sanitizeForClient({...sanitized, cacheHit: false});
});
