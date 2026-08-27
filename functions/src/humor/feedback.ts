import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {loadHumorContent} from "./contentRepository.js";
import {loadUserHumorProfile} from "./feed.js";
import {canServeHumorContent} from "./moderation.js";
import {
  applyFeedbackToProfile,
  defaultUserHumorProfile,
  isProfileBuilding,
  ratingWeight,
} from "./profile.js";
import {
  HUMOR_BINARY_RATINGS,
  type HumorBinaryRating,
  type HumorRating,
  type UserHumorProfileDoc,
} from "./types.js";

function isPositiveBinary(rating: HumorRating): boolean {
  return rating === "funny" || rating === "very_funny";
}

function isNegativeBinary(rating: HumorRating): boolean {
  return rating === "not_funny" || rating === "not_at_all";
}

/** Live submit accepts only funny / not_funny. */
export function isValidHumorRating(value: unknown): value is HumorBinaryRating {
  return (
    typeof value === "string" &&
    (HUMOR_BINARY_RATINGS as readonly string[]).includes(value)
  );
}

function adjustBinaryCounts(
  profile: UserHumorProfileDoc,
  previous: HumorRating | undefined,
  next: HumorRating,
  alreadyCounted: boolean,
): UserHumorProfileDoc {
  let funnyCount = Math.max(0, Number(profile.funnyCount ?? 0));
  let notFunnyCount = Math.max(0, Number(profile.notFunnyCount ?? 0));

  if (alreadyCounted && previous) {
    if (isPositiveBinary(previous)) {
      funnyCount = Math.max(0, funnyCount - 1);
    } else if (isNegativeBinary(previous)) {
      notFunnyCount = Math.max(0, notFunnyCount - 1);
    }
  }

  if (isPositiveBinary(next)) {
    funnyCount += 1;
  } else if (isNegativeBinary(next)) {
    notFunnyCount += 1;
  }

  return {...profile, funnyCount, notFunnyCount};
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
  funnyCount: number;
  notFunnyCount: number;
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

  const result = await input.db.runTransaction(async (tx) => {
    const [interactionSnap, profileSnap] = await Promise.all([
      tx.get(interactionRef),
      tx.get(profileRef),
    ]);

    const existingRating = interactionSnap.exists
      ? (interactionSnap.data()?.rating as HumorRating | undefined)
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

    profile = {
      ...defaultUserHumorProfile(),
      ...profile,
      interactionCount: Number(profile.interactionCount ?? 0),
      confidence: Number(profile.confidence ?? 0),
      funnyCount: Math.max(0, Number(profile.funnyCount ?? 0)),
      notFunnyCount: Math.max(0, Number(profile.notFunnyCount ?? 0)),
      exploredCategories: Array.isArray(profile.exploredCategories)
        ? profile.exploredCategories
        : [],
    };

    const sameRating = alreadyCounted && existingRating === input.rating;
    if (!sameRating) {
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
      profile = adjustBinaryCounts(
        profile,
        existingRating,
        input.rating,
        alreadyCounted,
      );
    }

    const now = FieldValue.serverTimestamp();
    tx.set(
      interactionRef,
      {
        contentId: input.contentId,
        rating: input.rating,
        reaction: input.rating,
        provider: content.source?.provider ?? null,
        category: content.category,
        dwellMs: Math.max(0, Math.floor(input.dwellMs ?? 0)),
        replayCount: Math.max(0, Math.floor(input.replayCount ?? 0)),
        skipped: input.skipped === true,
        saved: input.saved === true,
        gestureHints: input.gestureHints ?? null,
        timestamp: now,
        updatedAt: now,
        ...(alreadyCounted ? {} : {createdAt: now}),
      },
      {merge: true},
    );
    tx.set(
      profileRef,
      {
        ...profile,
        funnyCount: profile.funnyCount ?? 0,
        notFunnyCount: profile.notFunnyCount ?? 0,
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
    return profile;
  });

  return {
    ok: true,
    profileBuilding: isProfileBuilding(result.interactionCount),
    interactionCount: result.interactionCount,
    confidence: result.confidence,
    funnyCount: Number(result.funnyCount ?? 0),
    notFunnyCount: Number(result.notFunnyCount ?? 0),
  };
}

export async function getHumorProfileView(
  db: Firestore,
  uid: string,
  detailed: boolean,
): Promise<Record<string, unknown>> {
  const profile = await loadUserHumorProfile(db, uid);
  const top = Object.entries(profile.vector)
    .sort((a, b) => Number(b[1]) - Number(a[1]))
    .slice(0, 3)
    .map(([dim, value]) => ({dim, value: Math.round(Number(value))}));
  const basic = {
    confidence: profile.confidence,
    interactionCount: profile.interactionCount,
    funnyCount: Number(profile.funnyCount ?? 0),
    notFunnyCount: Number(profile.notFunnyCount ?? 0),
    profileBuilding: isProfileBuilding(profile.interactionCount),
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
