import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {
  advanceCalibration,
  calibrationWritePayload,
  parseCalibrationState,
  toCalibrationView,
  type CalibrationStateView,
} from "./calibration.js";
import {loadHumorContent} from "./contentRepository.js";
import {
  HUMOR_CALIBRATION_DOC,
  loadUserHumorCalibration,
  loadUserHumorProfile,
} from "./feed.js";
import {canServeHumorContent} from "./moderation.js";
import {
  applyFeedbackToProfile,
  defaultUserHumorProfile,
  isProfileBuilding,
  ratingWeight,
} from "./profile.js";
import {HUMOR_RATINGS, type HumorRating, type UserHumorProfileDoc} from "./types.js";

export function isValidHumorRating(value: unknown): value is HumorRating {
  return typeof value === "string" && (HUMOR_RATINGS as readonly string[]).includes(value);
}

/**
 * Persist feedback + update UserHumorProfile.
 * Idempotent on same contentId+rating: re-applying same rating does not double-count.
 * Changing rating updates the interaction doc and applies a single incremental update
 * (MVP: count once per content; subsequent ratings overwrite without extra count).
 */
export async function submitHumorFeedbackTx(input: {
  db: Firestore;
  uid: string;
  contentId: string;
  rating: HumorRating;
  dwellMs?: number;
  replayCount?: number;
  skipped?: boolean;
  saved?: boolean;
  gestureHints?: {swipeUp?: boolean; swipeDown?: boolean} | null;
}): Promise<{
  ok: true;
  profileBuilding: boolean;
  interactionCount: number;
  confidence: number;
  calibration: CalibrationStateView;
}> {
  const content = await loadHumorContent(input.db, input.contentId);
  if (
    !content ||
    !canServeHumorContent({
      active: content.active,
      safetyStatus: content.safetyStatus,
    })
  ) {
    throw new Error("content-unavailable");
  }

  const interactionRef = input.db.doc(
    `users/${input.uid}/humorInteractions/${input.contentId}`,
  );
  const profileRef = input.db.doc(`users/${input.uid}/humor/summary`);
  const calibrationRef = input.db.doc(HUMOR_CALIBRATION_DOC(input.uid));

  const result = await input.db.runTransaction(async (tx) => {
    const [interactionSnap, profileSnap, calibrationSnap] = await Promise.all([
      tx.get(interactionRef),
      tx.get(profileRef),
      tx.get(calibrationRef),
    ]);

    const existingRating = interactionSnap.exists
      ? interactionSnap.data()?.rating
      : undefined;
    const alreadyCounted = interactionSnap.exists === true;

    let profile: UserHumorProfileDoc = profileSnap.exists
      ? {
          ...defaultUserHumorProfile(),
          ...profileSnap.data(),
          vector: {
            ...defaultUserHumorProfile().vector,
            ...(profileSnap.data()?.vector ?? {}),
          },
        }
      : defaultUserHumorProfile();

    // Load via helper shape
    profile = {
      ...defaultUserHumorProfile(),
      ...profile,
      interactionCount: Number(profile.interactionCount ?? 0),
      confidence: Number(profile.confidence ?? 0),
      exploredCategories: Array.isArray(profile.exploredCategories)
        ? profile.exploredCategories
        : [],
    };

    const sameRating = alreadyCounted && existingRating === input.rating;
    if (!sameRating) {
      // For first rating: apply EMA and increment.
      // For changed rating: apply EMA once more without inventing a second content exposure
      // by temporarily decrementing count before apply when already counted.
      if (alreadyCounted) {
        profile = {
          ...profile,
          interactionCount: Math.max(0, profile.interactionCount - 1),
        };
      }
      profile = applyFeedbackToProfile({
        profile,
        contentVector: content.humorVector,
        category: content.category,
        rating: input.rating,
      });
    }

    // Calibration advances only on a *first* rating of a content item, inside
    // the same transaction as the profile update, so progression can never
    // drift from the interactions that actually happened — and a retried or
    // re-rated submission cannot inflate it.
    const previousCalibration = parseCalibrationState(
      calibrationSnap.data() as Record<string, unknown> | undefined,
    );
    const calibration = alreadyCounted
      ? previousCalibration
      : advanceCalibration({state: previousCalibration, content});

    const now = FieldValue.serverTimestamp();
    if (calibration !== previousCalibration) {
      tx.set(
        calibrationRef,
        {
          ...calibrationWritePayload(calibration),
          ...(previousCalibration.completedCount === 0 ? {startedAt: now} : {}),
          ...(calibration.complete && !previousCalibration.complete
            ? {completedAt: now}
            : {}),
          updatedAt: now,
        },
        {merge: true},
      );
    }
    tx.set(
      interactionRef,
      {
        contentId: input.contentId,
        rating: input.rating,
        dwellMs: Math.max(0, Math.floor(input.dwellMs ?? 0)),
        replayCount: Math.max(0, Math.floor(input.replayCount ?? 0)),
        skipped: input.skipped === true,
        saved: input.saved === true,
        gestureHints: input.gestureHints ?? null,
        updatedAt: now,
        ...(alreadyCounted ? {} : {createdAt: now}),
      },
      {merge: true},
    );
    tx.set(
      profileRef,
      {
        ...profile,
        lastUpdatedAt: now,
      },
      {merge: true},
    );
    if (!alreadyCounted) {
      const contentRef = input.db.doc(`humorContent/${input.contentId}`);
      const prevCount = Number(content.stats?.ratingCount ?? 0);
      const prevAvg = Number(content.stats?.avgRating ?? 0);
      const weight = ratingWeight(input.rating);
      const nextCount = prevCount + 1;
      const nextAvg =
        prevCount <= 0 ? weight : (prevAvg * prevCount + weight) / nextCount;
      tx.set(
        contentRef,
        {
          stats: {
            ratingCount: FieldValue.increment(1),
            viewCount: FieldValue.increment(1),
            avgRating: nextAvg,
          },
          updatedAt: now,
        },
        {merge: true},
      );
    }
    return {profile, calibration};
  });

  return {
    ok: true,
    // Calibration is the authoritative "still building" signal once it has
    // started; the interaction-count heuristic remains for pre-calibration
    // profiles so existing clients keep behaving as before.
    profileBuilding: result.calibration.complete
      ? false
      : result.calibration.completedCount > 0 ||
        isProfileBuilding(result.profile.interactionCount),
    interactionCount: result.profile.interactionCount,
    confidence: result.profile.confidence,
    calibration: toCalibrationView(result.calibration),
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
    vector: profile.vector,
    exploredCategories: profile.exploredCategories,
  };
}
