import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {isHumorCategory} from "./categories.js";
import {humorScoreForPair} from "./compatibility.js";
import {
  INTERNAL_HUMOR_SEED,
  upsertHumorContentDoc,
  type UpsertHumorContentInput,
} from "./contentRepository.js";
import {buildHumorFeed, loadUserHumorProfile} from "./feed.js";
import {
  getHumorProfileView,
  isValidHumorRating,
  submitHumorFeedbackTx,
} from "./feedback.js";
import {classifyHumorSafety, emptySafetyFlags} from "./moderation.js";
import {applyHumorAiTagging} from "./aiTagging.js";
import {safeLogMeta} from "../security/logHygiene.js";
import type {HumorContentType, HumorSafetyStatus} from "./types.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const auth = getAuth();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {enforceAppCheck, region: "europe-west1" as const};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

async function requireAdmin(uid: string): Promise<void> {
  const user = await auth.getUser(uid);
  if (user.customClaims?.admin !== true) {
    throw new HttpsError("permission-denied", "admin-required");
  }
}

export const getHumorFeed = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  try {
    const feed = await buildHumorFeed({
      db,
      uid,
      languages: Array.isArray(data.languages) ? data.languages.map(String) : undefined,
      limit: typeof data.limit === "number" ? data.limit : undefined,
      cursor: typeof data.cursor === "string" ? data.cursor : null,
    });
    return feed;
  } catch (error) {
    logger.error("getHumorFeed failed", safeLogMeta({uid, error: String(error)}));
    throw new HttpsError("internal", "feed-unavailable");
  }
});

export const submitHumorFeedback = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = String(data.contentId ?? "").trim();
  if (!contentId || contentId.length > 128) {
    throw new HttpsError("invalid-argument", "contentId");
  }
  if (!isValidHumorRating(data.rating)) {
    throw new HttpsError("invalid-argument", "rating");
  }
  try {
    return await submitHumorFeedbackTx({
      db,
      uid,
      contentId,
      rating: data.rating,
      dwellMs: typeof data.dwellMs === "number" ? data.dwellMs : 0,
      replayCount: typeof data.replayCount === "number" ? data.replayCount : 0,
      skipped: data.skipped === true,
      saved: data.saved === true,
      gestureHints:
        data.gestureHints && typeof data.gestureHints === "object"
          ? (data.gestureHints as {swipeUp?: boolean; swipeDown?: boolean})
          : null,
    });
  } catch (error) {
    const message = String(error);
    if (message.includes("content-unavailable")) {
      throw new HttpsError("not-found", "content-unavailable");
    }
    logger.error("submitHumorFeedback failed", safeLogMeta({uid, error: message}));
    throw new HttpsError("internal", "feedback-unavailable");
  }
});

export const getHumorProfile = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const detailed = request.data?.detailed === true;
  // MVP: basic always free; detailed allowed (premium gating soft — V2).
  return getHumorProfileView(db, uid, detailed);
});

/**
 * Match humor compatibility. MVP: available as standalone callable.
 * Does NOT feed Discover / calculateCompatibility.
 */
export const getMatchHumorCompatibility = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const matchId = String(request.data?.matchId ?? "").trim();
  if (!matchId) {
    throw new HttpsError("invalid-argument", "matchId");
  }
  const matchSnap = await db.doc(`matches/${matchId}`).get();
  if (!matchSnap.exists) {
    throw new HttpsError("not-found", "match");
  }
  const userIds = (matchSnap.data()?.userIds ?? []) as string[];
  if (!userIds.includes(uid) || matchSnap.data()?.isActive === false) {
    throw new HttpsError("permission-denied", "match");
  }
  const otherUid = userIds.find((id) => id !== uid);
  if (!otherUid) {
    return {available: false, score: null, reason: "invalid-match"};
  }
  const [a, b] = await Promise.all([
    loadUserHumorProfile(db, uid),
    loadUserHumorProfile(db, otherUid),
  ]);
  return humorScoreForPair(a, b);
});

export const reportHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = String(data.contentId ?? "").trim();
  if (!contentId) {
    throw new HttpsError("invalid-argument", "contentId");
  }
  const reason = String(data.reason ?? "other").slice(0, 64);
  const details = String(data.details ?? "").slice(0, 500);
  const reportId = `${uid}_${contentId}`;
  await db.doc(`humorReports/${reportId}`).set(
    {
      reportId,
      reporterId: uid,
      contentId,
      reason,
      details,
      status: "open",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`humorModerationQueue/${contentId}`).set(
    {
      contentId,
      status: "needs_review",
      source: "user_report",
      lastReporterId: uid,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return {ok: true};
});

export const upsertHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = String(data.contentId ?? "").trim();
  if (!contentId) {
    throw new HttpsError("invalid-argument", "contentId");
  }
  const category = String(data.category ?? "");
  if (!isHumorCategory(category)) {
    throw new HttpsError("invalid-argument", "category");
  }
  const type = String(data.type ?? "text");
  const tagged = applyHumorAiTagging({
    suggestedCategory: category,
    suggestedTags: Array.isArray(data.humorTags) ? data.humorTags.map(String) : [],
    suggestedVector: (data.humorVector as Record<string, number> | undefined) ?? undefined,
    suggestedSafetyFlags:
      (data.safetyFlags as Parameters<typeof applyHumorAiTagging>[0]["suggestedSafetyFlags"]) ??
      undefined,
  });
  const input: UpsertHumorContentInput = {
    contentId,
    type: (["image", "video", "text", "meme"].includes(type)
      ? type
      : "text") as HumorContentType,
    language: String(data.language ?? "en"),
    category: tagged.category,
    humorTags: tagged.humorTags,
    humorVector: tagged.humorVector,
    media: (data.media as UpsertHumorContentInput["media"]) ?? {},
    safetyFlags: tagged.safetyFlags,
    safetyStatus:
      typeof data.safetyStatus === "string"
        ? (data.safetyStatus as HumorSafetyStatus)
        : tagged.safetyStatus,
    active: data.active === true,
    sourceType: data.sourceType === "licensed_api" ? "licensed_api" : "internal",
    provider: typeof data.provider === "string" ? data.provider : undefined,
    licenseRef: typeof data.licenseRef === "string" ? data.licenseRef : null,
  };
  const doc = await upsertHumorContentDoc(db, input);
  return {
    ok: true,
    contentId: doc.contentId,
    safetyStatus: doc.safetyStatus,
    active: doc.active,
  };
});

export const runHumorModeration = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = String(data.contentId ?? "").trim();
  if (!contentId) {
    throw new HttpsError("invalid-argument", "contentId");
  }
  const ref = db.doc(`humorContent/${contentId}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "content");
  }
  const classified = classifyHumorSafety(
    emptySafetyFlags(
      (data.safetyFlags as Parameters<typeof emptySafetyFlags>[0]) ??
        snap.data()?.safetyFlags,
    ),
  );
  const safetyStatus = (data.forceStatus as HumorSafetyStatus | undefined) ?? classified.status;
  const active =
    safetyStatus === "approved" && snap.data()?.active !== false
      ? safetyStatus === "approved"
      : safetyStatus === "approved";
  await ref.set(
    {
      safetyFlags: classified.flags,
      safetyStatus,
      active: safetyStatus === "approved" ? active : false,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`humorModerationQueue/${contentId}`).set(
    {
      contentId,
      status: safetyStatus,
      updatedAt: FieldValue.serverTimestamp(),
      moderatedBy: uid,
    },
    {merge: true},
  );
  return {ok: true, contentId, safetyStatus, active: safetyStatus === "approved"};
});

/** Admin-only: seed internal repository (no scraping). */
export const seedInternalHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  let count = 0;
  for (const item of INTERNAL_HUMOR_SEED) {
    await upsertHumorContentDoc(db, {
      ...item,
      safetyStatus: "approved",
      active: true,
    });
    count += 1;
  }
  return {ok: true, seeded: count};
});

/**
 * Admin: pull licensed Giphy content (lang=tr preferred) into humorContent.
 * Requires GIPHY_API_KEY secret/env. No scraping.
 */
export const syncHumorFromProvider = onCall(
  {
    ...callableOptions,
    // Secret optional at deploy; runtime checks configuration.
    secrets: [],
  },
  async (request) => {
    const uid = requireUid(request);
    await requireAdmin(uid);
    const data = (request.data ?? {}) as {language?: string; limit?: number};
    const {syncHumorFromGiphy} = await import("./ingest.js");
    const {isGiphyConfigured} = await import("./humorApiConfig.js");
    if (!isGiphyConfigured()) {
      return {
        ok: false,
        configured: false,
        message: "Set GIPHY_API_KEY (firebase functions:secrets:set GIPHY_API_KEY).",
      };
    }
    const result = await syncHumorFromGiphy({
      db,
      language: data.language ?? "tr",
      limit: typeof data.limit === "number" ? data.limit : 24,
      probe: true,
    });
    return {ok: true, ...result};
  },
);

export {isGiphyConfigured} from "./humorApiConfig.js";
export {GiphyHumorSource} from "./giphySource.js";
export {validateHumorSourceItem} from "./contentValidation.js";
export {syncHumorFromGiphy} from "./ingest.js";

// Re-export pure helpers for tests / future V3 wiring (not used by Discover in MVP).
export {humorScoreForPair} from "./compatibility.js";
export {
  applyFeedbackToProfile,
  confidenceFromInteractions,
  ratingWeight,
} from "./profile.js";
export {rankHumorFeed, scoreHumorCandidate} from "./ranking.js";
export {classifyHumorSafety} from "./moderation.js";
export {applyHumorAiTagging} from "./aiTagging.js";
export {INTERNAL_HUMOR_SEED} from "./contentRepository.js";
