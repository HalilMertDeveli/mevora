import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {HUMOR_CALIBRATION_VERSION, isAnchorSlotId} from "./calibration.js";
import {isHumorCategory} from "./categories.js";
import {giphyApiKey, klipyApiKey} from "./humorApiConfig.js";
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
import {
  HumorCoreRejected,
  buildHumorCoreSequenceReport,
  currentHumorFeedbackResult,
  getHumorCoreFeedView,
  getHumorCoreProfileView,
  submitHumorCoreResponse,
  toHumorFeedbackResult,
  waiveReportedHumorCoreItem,
} from "./coreService.js";
import {loadUserHumorProfile} from "./feed.js";
import {parseSubmitHumorFeedbackInput} from "./feedback.js";
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

/**
 * The initial calibration: what is left of V1–V15 for the caller today, in the
 * canonical order every member gets. Nothing in the request selects content —
 * `languages`, `limit` and `cursor` are accepted from older clients and
 * ignored. Once the calibration is finished the feed is closed and answers
 * "caught up": the daily five are the only Core content.
 */
export const getHumorFeed = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, "humorLab");
  try {
    return await getHumorCoreFeedView({db, uid, nowMs: Date.now()});
  } catch (error) {
    logger.error("getHumorFeed failed", safeLogMeta({uid, error: String(error)}));
    throw new HttpsError("internal", "feed-unavailable");
  }
});

/**
 * A rating for one of the caller's Core entries of today, or a `media_failed`
 * skip. The content id is only checked against the set the server computed:
 * an entry that is not in it — tomorrow's, an earlier one, anything that is
 * not Core — is refused with `not-in-set` before anything is learned.
 *
 * A plain "not interested" skip records nothing: a Core entry is a
 * measurement, so it stays open and is asked again.
 */
export const submitHumorFeedback = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await assertAppFeatureAvailable(db, "humorLab");
  // `rating` may be omitted only for a skip; `saved` is forwarded only when it
  // is an explicit boolean; `gestureHints` is reduced to two booleans.
  const parsed = parseSubmitHumorFeedbackInput(request.data);
  if (!parsed.ok) {
    throw new HttpsError("invalid-argument", parsed.field);
  }
  const value = parsed.value;
  const nowMs = Date.now();
  try {
    if (value.skipped && value.skipReason !== "media_failed") {
      return await currentHumorFeedbackResult({db, uid, nowMs});
    }
    const result = await submitHumorCoreResponse({
      db,
      uid,
      nowMs,
      contentId: value.contentId,
      rating: value.rating,
      mediaFailed: value.skipped,
      dwellMs: value.dwellMs,
      replayCount: value.replayCount,
      saved: value.saved,
      gestureHints: value.gestureHints,
    });
    return toHumorFeedbackResult(result);
  } catch (error) {
    if (error instanceof HumorCoreRejected) {
      throw new HttpsError("failed-precondition", error.reason);
    }
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
  return getHumorCoreProfileView({db, uid, nowMs: Date.now(), detailed});
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
 * Bugünün Mizah Turu: the caller's next Core entries — at most five a day,
 * frozen for the day once touched. Feed-safe cards, resumable progress. The
 * server clock picks the day and the server picks the entries — the client
 * sends nothing that could choose either.
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
 * One answer in today's Core set: a rating, or a `media_failed` skip.
 * Same rating semantics as `submitHumorFeedback`; idempotent per entry.
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

export const reportHumorContent = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const data = (request.data ?? {}) as Record<string, unknown>;
  const result = await submitHumorReport(db, uid, data);
  try {
    // A reported Core entry is waived for the reporter, so it cannot hold
    // their day open. The report itself is already recorded.
    await waiveReportedHumorCoreItem({
      db,
      uid,
      nowMs: Date.now(),
      contentId: parseHumorContentId(data.contentId),
    });
  } catch (error) {
    logger.warn("humor core waiver after report failed", safeLogMeta({uid, error: String(error)}));
  }
  return result;
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

/**
 * Admin-only: is the Core sequence healthy enough to ship? Every position
 * with the state of its content document. (The callable keeps its name from
 * when it reported the calibration pools.)
 */
export const getHumorCalibrationPoolReport = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  await requireAdmin(uid);
  return buildHumorCoreSequenceReport(db);
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
 * `provider: "klipy"` searches KLIPY clips (short videos) instead; without it
 * the search is GIPHY, as before.
 *
 * Inert when deployed: it refuses before reading auth or input unless it runs
 * inside the Functions emulator. The emulator is also where the provider keys
 * live for development (functions/.secret.local); a key never leaves this
 * process — results carry media URLs only, errors a status code only. The
 * KLIPY secret exists in the emulator alone (see humorApiConfig.ts).
 */
export const searchHumorProviderCandidates = onCall(
  {...callableOptions, secrets: [giphyApiKey].concat(klipyApiKey ?? [])},
  async (request) => {
    if (process.env.FUNCTIONS_EMULATOR !== "true") {
      throw new HttpsError("failed-precondition", "emulator-only");
    }
    const uid = requireUid(request);
    await requireAdmin(uid);
    const {
      parseCandidateProvider,
      parseProviderCandidateSearchInput,
      searchKlipyClipCandidates,
      searchProviderCandidates,
    } = await import("./providerCandidates.js");
    const provider = parseCandidateProvider(request.data);
    if (!provider.ok) {
      throw new HttpsError("invalid-argument", provider.field);
    }
    const parsed = parseProviderCandidateSearchInput(request.data);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", parsed.field);
    }
    if (provider.value === "klipy") {
      const {KlipyHumorSource} = await import("./klipySource.js");
      const klipy = KlipyHumorSource.tryCreate();
      if (!klipy) {
        return {ok: false, configured: false};
      }
      return {ok: true, configured: true, ...(await searchKlipyClipCandidates(klipy, parsed.value))};
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
  stageForCompletedCount,
  toCalibrationView,
} from "./calibration.js";
export {
  HUMOR_CORE,
  HUMOR_CORE_RELEASE,
  HUMOR_CORE_SEQUENCE,
  humorCorePosition,
  humorCoreSequenceProblems,
} from "./coreSequence.js";
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
