import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  MATCHING_STREAK_REMINDER_HOUR_ISTANBUL,
  MATCHING_STREAK_REWARDS,
} from "./matchingStreakConfig.js";
import {
  applyParticipation,
  dailyParticipation,
  effectiveStreak,
  emptyMatchingStreakState,
  istanbulDateParts,
  istanbulDayKey,
  type MatchingStreakState,
} from "./matchingStreakEngine.js";
import {FcmTypes, sendUserPush} from "./notifications.js";

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
  if (!uid) throw new HttpsError("unauthenticated", "unauthenticated");
  return uid;
}

function streakRef(uid: string) {
  return db.doc(`users/${uid}/matchingStreak/current`);
}

function dayRef(uid: string, dayKey: string) {
  return db.doc(`users/${uid}/matchingStreakDays/${dayKey}`);
}

function rewardRef(uid: string, rewardId: string) {
  return db.doc(`users/${uid}/matchingStreakRewards/${rewardId}`);
}

function parseState(data: Record<string, unknown> | undefined): MatchingStreakState {
  if (!data) return emptyMatchingStreakState();
  const unlocked = Array.isArray(data.unlockedRewardIds)
    ? data.unlockedRewardIds.map((v) => String(v))
    : [];
  return {
    currentStreak: Number(data.currentStreak ?? 0) || 0,
    longestStreak: Number(data.longestStreak ?? 0) || 0,
    lastParticipatedDay:
      typeof data.lastParticipatedDay === "string" ? data.lastParticipatedDay : null,
    lastRoundId: typeof data.lastRoundId === "string" ? data.lastRoundId : null,
    unlockedRewardIds: unlocked,
  };
}

function publicPayload(state: MatchingStreakState, now: Date = new Date()) {
  const todayKey = istanbulDayKey(now);
  return {
    currentStreak: effectiveStreak(state, todayKey),
    longestStreak: state.longestStreak,
    lastParticipatedDay: state.lastParticipatedDay,
    lastRoundId: state.lastRoundId,
    dailyParticipation: dailyParticipation(state, todayKey),
    unlockedRewardIds: state.unlockedRewardIds,
    timezone: "Europe/Istanbul",
    todayKey,
  };
}

/**
 * Server-only: record Match Game participation for streak.
 * Safe to call on join and rejoin — same Istanbul day never increments twice.
 */
export async function recordMatchingGameParticipation(
  uid: string,
  roundId: string,
  now: Date = new Date(),
): Promise<ReturnType<typeof publicPayload> & {alreadyParticipatedToday: boolean}> {
  const dayKey = istanbulDayKey(now);
  const ref = streakRef(uid);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const before = parseState(snap.data() as Record<string, unknown> | undefined);
    const applied = applyParticipation({
      state: before,
      dayKey,
      roundId,
      rewards: MATCHING_STREAK_REWARDS,
    });

    tx.set(
      ref,
      {
        ...applied.state,
        timezone: "Europe/Istanbul",
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    if (!applied.alreadyParticipatedToday) {
      tx.set(
        dayRef(uid, dayKey),
        {
          dayKey,
          participated: true,
          roundId,
          streakAfter: applied.state.currentStreak,
          createdAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }

    for (const reward of applied.newlyUnlocked) {
      tx.set(
        rewardRef(uid, reward.id),
        {
          rewardId: reward.id,
          type: reward.type,
          minDays: reward.minDays,
          payload: reward.payload ?? {},
          unlockedAtStreak: applied.state.currentStreak,
          unlockedAtDay: dayKey,
          unlockedAt: FieldValue.serverTimestamp(),
          status: "unlocked",
        },
        {merge: true},
      );
    }

    return applied;
  });

  return {
    ...publicPayload(result.state, now),
    alreadyParticipatedToday: result.alreadyParticipatedToday,
  };
}

export const getMatchingStreak = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const snap = await streakRef(uid).get();
  const state = parseState(snap.data() as Record<string, unknown> | undefined);
  return publicPayload(state);
});

/**
 * Evening reminder for users with an active streak who have not played today.
 * Honors streakNotifications preference via sendUserPush.
 */
export const matchingStreakReminderTick = onSchedule(
  {
    schedule: `0 ${MATCHING_STREAK_REMINDER_HOUR_ISTANBUL} * * *`,
    timeZone: "Europe/Istanbul",
    region: "europe-west1",
  },
  async () => {
    const now = new Date();
    const parts = istanbulDateParts(now);
    if (Number(parts.hour) !== MATCHING_STREAK_REMINDER_HOUR_ISTANBUL) {
      return;
    }
    const todayKey = istanbulDayKey(now);
    const snap = await db
      .collectionGroup("matchingStreak")
      .where("currentStreak", ">", 0)
      .limit(500)
      .get();

    for (const doc of snap.docs) {
      if (doc.id !== "current") continue;
      const uid = doc.ref.parent.parent?.id;
      if (!uid) continue;
      const state = parseState(doc.data() as Record<string, unknown>);
      if (dailyParticipation(state, todayKey)) continue;
      if (effectiveStreak(state, todayKey) <= 0) continue;
      await sendUserPush({
        uid,
        type: FcmTypes.streakReminder,
        prefKey: "streakNotifications",
        data: {todayKey},
      });
    }
  },
);
