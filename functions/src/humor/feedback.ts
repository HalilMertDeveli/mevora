import {
  FieldValue,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {
  advanceCalibration,
  calibrationWritePayload,
  isCalibrationCurated,
  parseCalibrationState,
  stageForCompletedCount,
  toCalibrationView,
  type CalibrationStateView,
  type UserHumorCalibrationDoc,
} from "./calibration.js";
import {hasUnseenCuratedCandidate} from "./calibrationFeed.js";
import {normalizeProfileVector} from "./categories.js";
import {loadHumorContent} from "./contentRepository.js";
import {
  HUMOR_CALIBRATION_DOC,
  loadUserHumorCalibration,
  loadUserHumorProfile,
} from "./feed.js";
import {canServeHumorContent} from "./moderation.js";
import {
  applyRatingToProfile,
  defaultUserHumorProfile,
  isProfileBuilding,
  parseProfileDelta,
  ratingWeight,
} from "./profile.js";
import {
  HUMOR_RATINGS,
  type HumorContentDoc,
  type HumorRating,
  type UserHumorProfileDoc,
} from "./types.js";

export function isValidHumorRating(value: unknown): value is HumorRating {
  return typeof value === "string" && (HUMOR_RATINGS as readonly string[]).includes(value);
}

/**
 * Content ids are used verbatim as Firestore path segments, so anything that
 * could add a segment (`/`) or otherwise surprise a path is rejected up front.
 * Every id the catalog produces (seed ids, sanitized provider ids) matches.
 */
export const HUMOR_CONTENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

const MAX_DWELL_MS = 24 * 60 * 60 * 1000;
const MAX_REPLAY_COUNT = 1000;

export type HumorGestureHints = {swipeUp: boolean; swipeDown: boolean};

export type SubmitHumorFeedbackInput = {
  contentId: string;
  /** `null` only for a skip. */
  rating: HumorRating | null;
  skipped: boolean;
  /** Present only when the client explicitly sent a boolean. */
  saved?: boolean;
  dwellMs: number;
  replayCount: number;
  gestureHints: HumorGestureHints | null;
};

function boundedCount(value: unknown, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return 0;
  }
  return Math.min(max, Math.max(0, Math.floor(value)));
}

/**
 * Validate and normalize a `submitHumorFeedback` payload.
 *
 * - `rating` is required unless `skipped === true`; a skip ignores any rating.
 * - `saved` is carried only when it is an explicit boolean, so a plain rating
 *   can never silently clear an earlier bookmark.
 * - `gestureHints` is reduced to two booleans: the document must not store an
 *   arbitrary client object.
 */
export function parseSubmitHumorFeedbackInput(
  data: unknown,
):
  | {ok: true; value: SubmitHumorFeedbackInput}
  | {ok: false; field: "contentId" | "rating"} {
  const raw =
    data && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {};
  const contentId = String(raw.contentId ?? "").trim();
  if (!HUMOR_CONTENT_ID_PATTERN.test(contentId)) {
    return {ok: false, field: "contentId"};
  }
  const skipped = raw.skipped === true;
  if (!isValidHumorRating(raw.rating) && !(skipped && raw.rating == null)) {
    return {ok: false, field: "rating"};
  }
  const hints = raw.gestureHints;
  const gestureHints =
    hints && typeof hints === "object" && !Array.isArray(hints)
      ? {
          swipeUp: (hints as Record<string, unknown>).swipeUp === true,
          swipeDown: (hints as Record<string, unknown>).swipeDown === true,
        }
      : null;
  return {
    ok: true,
    value: {
      contentId,
      rating: skipped ? null : (raw.rating as HumorRating),
      skipped,
      ...(typeof raw.saved === "boolean" ? {saved: raw.saved} : {}),
      dwellMs: boundedCount(raw.dwellMs, MAX_DWELL_MS),
      replayCount: boundedCount(raw.replayCount, MAX_REPLAY_COUNT),
      gestureHints,
    },
  };
}

type HumorFeedbackResult = {
  ok: true;
  profileBuilding: boolean;
  interactionCount: number;
  confidence: number;
  calibration: CalibrationStateView;
};

/** Change to a content item's aggregate rating stats. */
type StatsChange = {countDelta: number; sumDelta: number};

function profileFromSnapshot(data: Record<string, unknown> | undefined): UserHumorProfileDoc {
  const base = defaultUserHumorProfile();
  if (!data) {
    return base;
  }
  return {
    vector: {...base.vector, ...((data.vector as Record<string, number>) ?? {})},
    confidence: Number(data.confidence ?? 0) || 0,
    interactionCount: Math.max(0, Math.floor(Number(data.interactionCount ?? 0)) || 0),
    exploredCategories: Array.isArray(data.exploredCategories)
      ? data.exploredCategories.map((c) => String(c))
      : [],
    version: Number(data.version ?? base.version) || base.version,
  };
}

/** Persist a calibration transition, stamping start/completion exactly once. */
function writeCalibration(
  tx: Transaction,
  ref: DocumentReference,
  previous: UserHumorCalibrationDoc,
  next: UserHumorCalibrationDoc,
): void {
  if (next === previous) {
    return;
  }
  const now = FieldValue.serverTimestamp();
  tx.set(
    ref,
    {
      ...calibrationWritePayload(next),
      ...(previous.completedCount === 0 ? {startedAt: now} : {}),
      ...(next.complete && !previous.complete ? {completedAt: now} : {}),
      updatedAt: now,
    },
    {merge: true},
  );
}

/**
 * Rating aggregates on the content document, written *after* the feedback
 * transaction commits.
 *
 * They used to be computed from a content snapshot read outside the
 * transaction and written inside it, so concurrent ratings overwrote each
 * other's average — and every calibration-critical transaction contended on
 * the same hot curated documents. Now a small transaction of its own keeps
 * `ratingSum` exact and derives `avgRating` from it (the field ranking reads).
 * Best effort: a stats failure never fails the user's rating.
 */
async function recordContentStats(
  db: Firestore,
  contentId: string,
  change: StatsChange,
): Promise<void> {
  if (change.countDelta === 0 && change.sumDelta === 0) {
    return;
  }
  const ref = db.doc(`humorContent/${contentId}`);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        return;
      }
      const stats = (snap.data()?.stats ?? {}) as Record<string, unknown>;
      const count = Math.max(0, Number(stats.ratingCount ?? 0) || 0);
      const views = Math.max(0, Number(stats.viewCount ?? 0) || 0);
      const storedSum = Number(stats.ratingSum);
      // Documents written before `ratingSum` existed carry only the average.
      const sum = Number.isFinite(storedSum)
        ? storedSum
        : (Number(stats.avgRating ?? 0) || 0) * count;
      const nextCount = Math.max(0, count + change.countDelta);
      const nextSum = sum + change.sumDelta;
      tx.set(
        ref,
        {
          stats: {
            ratingCount: nextCount,
            viewCount: views + Math.max(0, change.countDelta),
            ratingSum: nextSum,
            avgRating: nextCount > 0 ? nextSum / nextCount : 0,
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });
  } catch (error) {
    logger.warn(
      "humor content stats update failed",
      safeLogMeta({contentId, error: String(error)}),
    );
  }
}

/**
 * An uncurated item was rated while the anchor stage is open and did not
 * count. If the user has no curated candidate left at all, count it after all
 * — as a degraded anchor position — so an exhausted pool cannot freeze
 * calibration. Rare path; re-validated inside its own transaction.
 */
async function countUncuratedAnchorIfPoolExhausted(input: {
  db: Firestore;
  uid: string;
  content: HumorContentDoc;
  state: UserHumorCalibrationDoc;
}): Promise<UserHumorCalibrationDoc> {
  const unseen = await hasUnseenCuratedCandidate({
    db: input.db,
    uid: input.uid,
    state: input.state,
  });
  if (unseen) {
    return input.state;
  }
  const calibrationRef = input.db.doc(HUMOR_CALIBRATION_DOC(input.uid));
  const interactionRef = input.db.doc(
    `users/${input.uid}/humorInteractions/${input.content.contentId}`,
  );
  return input.db.runTransaction(async (tx) => {
    const [calibrationSnap, interactionSnap] = await Promise.all([
      tx.get(calibrationRef),
      tx.get(interactionRef),
    ]);
    const previous = parseCalibrationState(
      calibrationSnap.data() as Record<string, unknown> | undefined,
    );
    if (!isValidHumorRating(interactionSnap.data()?.rating)) {
      return previous;
    }
    const next = advanceCalibration({
      state: previous,
      content: input.content,
      allowUncuratedAnchor: true,
    });
    writeCalibration(tx, calibrationRef, previous, next);
    return next;
  });
}

/**
 * Persist feedback and update the lifetime humor profile.
 *
 * Semantics per content item, decided inside one transaction from the
 * interaction document:
 *
 * - **Skip** (`skipped: true`): writes a skip marker only when the user has no
 *   interaction with the item yet, so it is never served again. The profile,
 *   counters, calibration and content stats are untouched.
 * - **First rating** — no interaction document, or only a skip/report marker
 *   (no valid rating): the profile learns from it, the interaction counts once
 *   and calibration may advance.
 * - **Same rating again**: a no-op (an explicit `saved` flag is still stored).
 * - **Changed rating**: *replaces* the earlier rating's contribution — the
 *   per-dimension delta it applied is stored on the interaction document
 *   (`appliedDelta`) and subtracted before the new rating is applied. Nothing
 *   is counted a second time.
 */
export async function submitHumorFeedbackTx(input: {
  db: Firestore;
  uid: string;
  contentId: string;
  rating?: HumorRating | null;
  dwellMs?: number;
  replayCount?: number;
  skipped?: boolean;
  saved?: boolean;
  gestureHints?: HumorGestureHints | null;
}): Promise<HumorFeedbackResult> {
  const skipped = input.skipped === true;
  const rating = skipped ? null : input.rating ?? null;
  if (!skipped && !isValidHumorRating(rating)) {
    throw new Error("invalid-rating");
  }

  const content = await loadHumorContent(input.db, input.contentId);
  // A skip only needs the item to exist — skipping something that was taken
  // down meanwhile is legitimate. A rating needs it to be servable.
  if (
    !content ||
    (!skipped &&
      !canServeHumorContent({
        active: content.active,
        safetyStatus: content.safetyStatus,
      }))
  ) {
    throw new Error("content-unavailable");
  }

  const interactionRef = input.db.doc(
    `users/${input.uid}/humorInteractions/${input.contentId}`,
  );
  const profileRef = input.db.doc(`users/${input.uid}/humor/summary`);
  const calibrationRef = input.db.doc(HUMOR_CALIBRATION_DOC(input.uid));
  const explicitSaved = typeof input.saved === "boolean" ? {saved: input.saved} : {};
  const details = {
    dwellMs: boundedCount(input.dwellMs, MAX_DWELL_MS),
    replayCount: boundedCount(input.replayCount, MAX_REPLAY_COUNT),
    gestureHints: input.gestureHints
      ? {
          swipeUp: input.gestureHints.swipeUp === true,
          swipeDown: input.gestureHints.swipeDown === true,
        }
      : null,
  };

  const result = await input.db.runTransaction(async (tx) => {
    const [interactionSnap, profileSnap, calibrationSnap] = await Promise.all([
      tx.get(interactionRef),
      tx.get(profileRef),
      tx.get(calibrationRef),
    ]);
    const profile = profileFromSnapshot(
      profileSnap.data() as Record<string, unknown> | undefined,
    );
    const previousCalibration = parseCalibrationState(
      calibrationSnap.data() as Record<string, unknown> | undefined,
    );
    const existing = interactionSnap.exists ? interactionSnap.data() ?? {} : null;
    // A skip or report marker has no valid rating: it does not count as rated.
    const existingRating = isValidHumorRating(existing?.rating)
      ? existing?.rating as HumorRating
      : null;
    const unchanged = {
      profile,
      calibration: previousCalibration,
      anchorDeferred: false,
      stats: null as StatsChange | null,
    };
    const now = FieldValue.serverTimestamp();

    if (skipped || rating === null) {
      if (!interactionSnap.exists) {
        tx.set(interactionRef, {
          contentId: input.contentId,
          skipped: true,
          rating: null,
          createdAt: now,
          updatedAt: now,
        });
      }
      return unchanged;
    }

    if (existingRating === rating) {
      if (typeof input.saved === "boolean" && existing?.saved !== input.saved) {
        tx.set(interactionRef, {saved: input.saved, updatedAt: now}, {merge: true});
      }
      return unchanged;
    }

    if (existingRating) {
      const replaced = applyRatingToProfile({
        profile,
        contentVector: content.humorVector,
        category: content.category,
        rating,
        mode: "replace",
        previousDelta: parseProfileDelta(existing?.appliedDelta),
      });
      tx.set(
        interactionRef,
        {
          rating,
          appliedDelta: replaced.appliedDelta,
          skipped: false,
          ...details,
          ...explicitSaved,
          updatedAt: now,
        },
        {merge: true},
      );
      tx.set(profileRef, {...replaced.profile, lastUpdatedAt: now}, {merge: true});
      return {
        ...unchanged,
        profile: replaced.profile,
        stats: {countDelta: 0, sumDelta: ratingWeight(rating) - ratingWeight(existingRating)},
      };
    }

    // First real rating of this item.
    const learned = applyRatingToProfile({
      profile,
      contentVector: content.humorVector,
      category: content.category,
      rating,
      mode: "first",
    });
    // Calibration advances only on a *first* rating, inside the same
    // transaction as the profile update, so progression can never drift from
    // the interactions that actually happened.
    const calibration = advanceCalibration({state: previousCalibration, content});
    writeCalibration(tx, calibrationRef, previousCalibration, calibration);
    tx.set(
      interactionRef,
      {
        contentId: input.contentId,
        rating,
        appliedDelta: learned.appliedDelta,
        skipped: false,
        ...details,
        ...explicitSaved,
        updatedAt: now,
        ...(interactionSnap.exists ? {} : {createdAt: now}),
      },
      {merge: true},
    );
    tx.set(profileRef, {...learned.profile, lastUpdatedAt: now}, {merge: true});
    return {
      profile: learned.profile,
      calibration,
      anchorDeferred:
        calibration === previousCalibration &&
        !previousCalibration.complete &&
        !isCalibrationCurated(content) &&
        stageForCompletedCount(previousCalibration.completedCount) === "anchor" &&
        !previousCalibration.ratedContentIds.includes(input.contentId),
      stats: {countDelta: 1, sumDelta: ratingWeight(rating)},
    };
  });

  const calibration = result.anchorDeferred
    ? await countUncuratedAnchorIfPoolExhausted({
        db: input.db,
        uid: input.uid,
        content,
        state: result.calibration,
      })
    : result.calibration;
  if (result.stats) {
    await recordContentStats(input.db, input.contentId, result.stats);
  }

  return {
    ok: true,
    // Calibration is the authoritative "still building" signal once it has
    // started; the interaction-count heuristic remains for pre-calibration
    // profiles so existing clients keep behaving as before.
    profileBuilding: calibration.complete
      ? false
      : calibration.completedCount > 0 ||
        isProfileBuilding(result.profile.interactionCount),
    interactionCount: result.profile.interactionCount,
    confidence: result.profile.confidence,
    calibration: toCalibrationView(calibration),
  };
}

export async function getHumorProfileView(
  db: Firestore,
  uid: string,
  detailed: boolean,
): Promise<Record<string, unknown>> {
  const [profile, calibrationState] = await Promise.all([
    loadUserHumorProfile(db, uid),
    loadUserHumorCalibration(db, uid),
  ]);
  const top = Object.entries(profile.vector)
    .sort((a, b) => Number(b[1]) - Number(a[1]))
    .slice(0, 3)
    .map(([dim, value]) => ({dim, value: Math.round(Number(value))}));
  const calibration = toCalibrationView(calibrationState);
  const basic = {
    confidence: profile.confidence,
    interactionCount: profile.interactionCount,
    // `profileBuilding` now means "initial calibration still running", not
    // "the profile has stopped learning" — learning never stops.
    profileBuilding: calibration.complete
      ? false
      : calibration.completedCount > 0 ||
        isProfileBuilding(profile.interactionCount),
    calibration,
    topVibes: top,
    version: profile.version,
  };
  if (!detailed) {
    return basic;
  }
  return {
    ...basic,
    // The stored vector keeps full precision; the client gets whole numbers.
    vector: normalizeProfileVector(profile.vector, 50),
    exploredCategories: profile.exploredCategories,
  };
}
