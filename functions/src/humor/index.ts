import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {HUMOR_CALIBRATION_VERSION, isAnchorSlotId} from "./calibration.js";
import {isHumorCategory} from "./categories.js";
import {giphyApiKey} from "./humorApiConfig.js";
import {
  humorScoreForPair,
  isHumorCalibrationReady,
  isValidMatchId,
  unavailableHumorCompatibility,
} from "./compatibility.js";
import {
  upsertHumorContentDoc,
  type UpsertHumorContentInput,
} from "./contentRepository.js";
import {buildHumorFeed, loadUserHumorProfile} from "./feed.js";
import {
  getHumorProfileView,
  parseSubmitHumorFeedbackInput,
  submitHumorFeedbackTx,
} from "./feedback.js";
import {isHumorSafetyStatus} from "./moderation.js";
import {applyHumorAiTagging} from "./aiTagging.js";
import {
  applyHumorModerationDecision,
  parseHumorContentId,
  submitHumorReport,
} from "./reports.js";
import {safeLogMeta} from "../security/logHygiene.js";
import type {HumorContentType} from "./types.js";

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
  await assertAppFeatureAvailable(db, "humorLab");
  const data = (request.data ?? {}) as Record<string, unknown>;
  try {
    const feed = await buildHumorFeed({
      db,
      uid,
      // Bounded before any work: ≤ 5 language codes of ≤ 8 characters, and a
      // cursor no longer than a real one can be. Oversized input degrades to
      // the defaults instead of costing CPU.
      languages: Array.isArray(data.languages)
        ? data.languages
            .slice(0, 5)
            .map(String)
            .filter((l) => l.length > 0 && l.length <= 8)
        : undefined,
      limit: typeof data.limit === "number" ? data.limit : undefined,
      cursor:
        typeof data.cursor === "string" && data.cursor.length <= 512 ? data.cursor : null,
    });
    return feed;
  } catch (error) {
    logger.error("getHumorFeed failed", safeLogMeta({uid, error: String(error)}));
    throw new HttpsError("internal", "feed-unavailable");
  }
});

export const submitHumorFeedback = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, "humorLab");
  // `rating` may be omitted only for a skip; `saved` is forwarded only when it
  // is an explicit boolean; `gestureHints` is reduced to two booleans.
  const parsed = parseSubmitHumorFeedbackInput(request.data);
  if (!parsed.ok) {
    throw new HttpsError("invalid-argument", parsed.field);
  }
  try {
    return await submitHumorFeedbackTx({db, uid, ...parsed.value});
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
 *
 * Payload is exactly {available, score, strongestShared, reason}. Available
 * only when both members finished their initial calibration and both profiles
 * carry signal.
 */
export const getMatchHumorCompatibility = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertCallerAccountEligible(db, uid);
  const rawMatchId = request.data?.matchId;
  const matchId = typeof rawMatchId === "string" ? rawMatchId.trim() : "";
  // A `/` would let the lookup resolve to a nested document a participant can
  // write (e.g. matches/{m}/messages/{x}) and forge `userIds` on.
  if (!isValidMatchId(matchId)) {
    throw new HttpsError("invalid-argument", "matchId");
  }
  const matchSnap = await db.collection("matches").doc(matchId).get();
  if (!matchSnap.exists) {
    throw new HttpsError("not-found", "match");
  }
  const match = matchSnap.data() ?? {};
  const userIds: unknown[] = Array.isArray(match.userIds) ? match.userIds : [];
  if (!userIds.includes(uid) || match.isActive !== true) {
    throw new HttpsError("permission-denied", "match");
  }
  const otherUid = userIds.find((id) => id !== uid);
  if (
    userIds.length !== 2 ||
    typeof otherUid !== "string" ||
    !otherUid ||
    otherUid.includes("/")
  ) {
    return unavailableHumorCompatibility("invalid-match");
  }
  const [profileA, profileB, calibrationA, calibrationB] = await Promise.all([
    loadUserHumorProfile(db, uid),
    loadUserHumorProfile(db, otherUid),
    db.doc(`users/${uid}/humor/calibration`).get(),
    db.doc(`users/${otherUid}/humor/calibration`).get(),
  ]);
  return humorScoreForPair(profileA, profileB, {
    readyA: isHumorCalibrationReady(calibrationA.data(), profileA),
    readyB: isHumorCalibrationReady(calibrationB.data(), profileB),
  });
});

/**
 * Today's daily humor set for the caller: the same ten items, in the same
 * order, for every eligible member on the canonical day. Feed-safe cards,
 * resumable progress. The server clock picks the day — the client sends
 * nothing that could choose another one.
 */
export const getDailyHumorSet = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, "humorLab");
  const {getDailyHumorSetView} = await import("./dailyService.js");
  try {
    return await getDailyHumorSetView({db, uid, nowMs: Date.now()});
  } catch (error) {
    logger.error("getDailyHumorSet failed", safeLogMeta({uid, error: String(error)}));
    throw new HttpsError("internal", "daily-unavailable");
  }
});

/**
 * One answer in today's daily set: a rating, or a `media_failed` skip.
 * Same rating semantics as `submitHumorFeedback`; idempotent per slot.
 */
export const submitDailyHumorResponse = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, "humorLab");
  const {DailyResponseRejected, parseDailyResponseInput, submitDailyHumorResponse: submit} =
    await import("./dailyService.js");
  const parsed = parseDailyResponseInput(request.data);
  if (!parsed.ok) {
    throw new HttpsError("invalid-argument", parsed.field);
  }
  try {
    return await submit({db, uid, nowMs: Date.now(), response: parsed.value});
  } catch (error) {
    if (error instanceof DailyResponseRejected) {
      throw new HttpsError("failed-precondition", error.reason);
    }
    const message = String(error);
    if (message.includes("content-unavailable")) {
      throw new HttpsError("not-found", "content-unavailable");
    }
    logger.error("submitDailyHumorResponse failed", safeLogMeta({uid, error: message}));
    throw new HttpsError("internal", "daily-unavailable");
  }
});

/**
 * Admin-only: publish (or return) the daily set for a day. Production accepts
 * only today and tomorrow; any other day works only inside the emulator.
 */
export const publishDailyHumorSet = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const {adminDayAllowed, ensureDailySet, isEmulatorProcess, resolveDailyToday} = await import(
    "./dailyService.js"
  );
  const nowMs = Date.now();
  const todayId = await resolveDailyToday(db, nowMs);
  const dayId = request.data?.dayId == null ? todayId : String(request.data.dayId);
  if (!adminDayAllowed(dayId, todayId, isEmulatorProcess())) {
    throw new HttpsError("invalid-argument", "dayId");
  }
  const result = await ensureDailySet({db, dayId, nowMs, publishedBy: `admin:${uid}`, force: true});
  return result.status === "published"
    ? {
        ok: true,
        dayId,
        status: "published",
        created: result.created,
        version: result.manifest.version,
        total: result.manifest.contentIds.length,
      }
    : {ok: true, dayId, status: "not_ready", eligiblePoolSize: result.eligiblePoolSize};
});

/** Admin-only: explicitly replace one slot of a published set (versioned). */
export const repairDailyHumorSlot = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const {adminDayAllowed, isEmulatorProcess, repairDailySlot, resolveDailyToday} = await import(
    "./dailyService.js"
  );
  const data = (request.data ?? {}) as Record<string, unknown>;
  const nowMs = Date.now();
  const todayId = await resolveDailyToday(db, nowMs);
  const dayId = String(data.dayId ?? "");
  if (!adminDayAllowed(dayId, todayId, isEmulatorProcess())) {
    throw new HttpsError("invalid-argument", "dayId");
  }
  const reason = typeof data.reason === "string" ? data.reason.trim() : "";
  if (!reason) {
    throw new HttpsError("invalid-argument", "reason");
  }
  try {
    return await repairDailySlot({
      db,
      dayId,
      index: Number(data.index),
      reason,
      adminUid: uid,
      nowMs,
    });
  } catch (error) {
    throw new HttpsError("failed-precondition", String((error as Error).message ?? error));
  }
});

export const reportHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  return submitHumorReport(db, uid, data);
});

export const upsertHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const contentId = parseHumorContentId(data.contentId);
  if (data.safetyStatus != null && !isHumorSafetyStatus(data.safetyStatus)) {
    throw new HttpsError("invalid-argument", "safetyStatus");
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
    safetyStatus: isHumorSafetyStatus(data.safetyStatus)
      ? data.safetyStatus
      : tagged.safetyStatus,
    active: data.active === true,
    sourceType: data.sourceType === "licensed_api" ? "licensed_api" : "internal",
    provider: typeof data.provider === "string" ? data.provider : undefined,
    licenseRef: typeof data.licenseRef === "string" ? data.licenseRef : null,
    // Calibration curation is an explicit admin act. An unrecognised slot is
    // rejected outright rather than silently downgraded, so a typo cannot
    // quietly drop an item out of the anchor pool it was meant to fill.
    calibration: parseCalibrationInput(data.calibration),
  };
  const doc = await upsertHumorContentDoc(db, input);
  return {
    ok: true,
    contentId: doc.contentId,
    safetyStatus: doc.safetyStatus,
    active: doc.active,
    calibration: doc.calibration,
  };
});

function parseCalibrationInput(
  raw: unknown,
): UpsertHumorContentInput["calibration"] {
  if (!raw || typeof raw !== "object") {
    return undefined;
  }
  const value = raw as Record<string, unknown>;
  if (value.eligible !== true) {
    return {eligible: false};
  }
  const slot = value.slot == null ? null : String(value.slot);
  if (slot !== null && !isAnchorSlotId(slot)) {
    throw new HttpsError("invalid-argument", "calibration-slot");
  }
  return {eligible: true, slot, version: HUMOR_CALIBRATION_VERSION};
}

/** Admin-only: is the calibration catalog healthy enough to ship? */
export const getHumorCalibrationPoolReport = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const {buildCalibrationPoolReport} = await import("./calibrationPoolReport.js");
  return buildCalibrationPoolReport(db);
});

export const runHumorModeration = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const data = (request.data ?? {}) as Record<string, unknown>;
  return applyHumorModerationDecision(db, uid, data);
});

/**
 * Admin-only: seed the active curated calibration catalogue (no scraping) and
 * retire the documents it replaced. Same code path as the emulator seeder.
 */
export const seedInternalHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  const {seedCalibrationCatalog} = await import("./calibrationCatalog.js");
  const result = await seedCalibrationCatalog(db);
  return {ok: true, seeded: result.written, retired: result.retired, catalog: result.kind};
});

/**
 * Admin-only, EMULATOR-ONLY curator tool: search GIPHY and return candidate
 * items (own title, credit, rating, renditions with sizes, still, relevance
 * verdict) for a human to pick the curated catalogue from. Writes nothing.
 *
 * Inert when deployed: it refuses before reading auth or input unless it runs
 * inside the Functions emulator. The emulator is also where the GIPHY key
 * lives for development (functions/.secret.local); the key never leaves this
 * process — results carry media URLs only, errors a status code only.
 */
export const searchHumorProviderCandidates = onCall(
  {...callableOptions, secrets: [giphyApiKey]},
  async (request) => {
    if (process.env.FUNCTIONS_EMULATOR !== "true") {
      throw new HttpsError("failed-precondition", "emulator-only");
    }
    const uid = requireUid(request);
    await requireAdmin(uid);
    const {parseProviderCandidateSearchInput, searchProviderCandidates} = await import(
      "./providerCandidates.js"
    );
    const parsed = parseProviderCandidateSearchInput(request.data);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", parsed.field);
    }
    const {GiphyHumorSource} = await import("./giphySource.js");
    const source = GiphyHumorSource.tryCreate({rating: parsed.value.rating});
    if (!source) {
      return {ok: false, configured: false};
    }
    const result = await searchProviderCandidates(source, parsed.value);
    return {ok: true, configured: true, ...result};
  },
);

/**
 * Admin: pull licensed Giphy content (lang=tr preferred) into humorContent.
 * Requires GIPHY_API_KEY secret/env. No scraping.
 */
export const syncHumorFromProvider = onCall(
  {
    ...callableOptions,
    // Declaring the secret is what mounts it into the runtime. Without this
    // the key is never present, `resolveGiphyApiKey()` returns null, and the
    // callable reports "not configured" however many times an admin runs
    // `functions:secrets:set GIPHY_API_KEY` — the exact command its own error
    // message tells them to run. Every other secret in this codebase is bound
    // the same way.
    secrets: [giphyApiKey],
  },
  async (request) => {
    const uid = requireUid(request);
    await requireAdmin(uid);
    const data = (request.data ?? {}) as {language?: unknown; limit?: unknown; clips?: unknown};
    const {syncHumorFromGiphy} = await import("./ingest.js");
    const {isGiphyConfigured} = await import("./humorApiConfig.js");
    if (!isGiphyConfigured()) {
      return {
        ok: false,
        configured: false,
        message: "Set GIPHY_API_KEY (firebase functions:secrets:set GIPHY_API_KEY).",
      };
    }
    // Clips needs GIPHY approval: opt in per call or with GIPHY_CLIPS_ENABLED.
    // Without access the source falls back to GIF search on its own.
    const result = await syncHumorFromGiphy({
      db,
      language: typeof data.language === "string" ? data.language : "tr",
      limit: typeof data.limit === "number" ? data.limit : 24,
      probe: true,
      clipsEnabled: data.clips === true || process.env.GIPHY_CLIPS_ENABLED === "true",
    });
    return {ok: true, ...result};
  },
);

export {isGiphyConfigured} from "./humorApiConfig.js";
export {GiphyHumorSource} from "./giphySource.js";
export {validateHumorSourceItem} from "./contentValidation.js";
export {syncHumorFromGiphy} from "./ingest.js";

// Re-export pure helpers for tests / future V3 wiring (not used by Discover in MVP).
export {
  ADJACENT_DIMENSIONS,
  ANCHOR_INTERACTIONS,
  ANCHOR_SLOTS,
  ADAPTIVE_INTERACTIONS,
  CALIBRATION_TOTAL,
  EXPLORATION_INTERACTIONS,
  HUMOR_CALIBRATION_VERSION,
  advanceCalibration,
  coverageDimensionsOf,
  defaultCalibrationState,
  isAnchorSlotId,
  isCalibrationComplete,
  parseCalibrationState,
  rotatingIndex,
  rotatingPick,
  scoreCalibrationCandidate,
  selectAdaptiveDimensions,
  selectExplorationDimensions,
  stableHash,
  stageForCompletedCount,
  stageForPosition,
  toCalibrationView,
} from "./calibration.js";
export {selectCalibrationItems} from "./calibrationFeed.js";
export {listCalibrationPool, parseCalibrationMeta} from "./contentRepository.js";
export {humorScoreForPair} from "./compatibility.js";
export {
  applyFeedbackToProfile,
  confidenceFromInteractions,
  ratingWeight,
} from "./profile.js";
import {assertCallerAccountEligible} from "../accountGuard.js";
import {assertAppFeatureAvailable} from "../appOperations/appOperationsGate.js";
export {rankHumorFeed, scoreHumorCandidate} from "./ranking.js";
export {classifyHumorSafety} from "./moderation.js";
export {applyHumorAiTagging} from "./aiTagging.js";
export {INTERNAL_HUMOR_SEED} from "./contentRepository.js";
