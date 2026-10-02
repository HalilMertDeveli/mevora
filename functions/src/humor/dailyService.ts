/**
 * Bugünün Mizah Turu — the daily callables' Firestore side.
 *
 * The day's items are the member's next Core entries (`coreService.ts`): at
 * most `HUMOR_CORE.dailyCount`, frozen once the day is touched. There is no
 * global daily manifest any more — `humorDailySets/{dayId}` is no longer read
 * or written, and nothing is selected algorithmically.
 *
 * `users/{uid}/humorDaily/{dayId}` documents written by the old daily set stay
 * where they are as history; the Core sequence writes one compact record per
 * completed day to the same path.
 */
import type {Firestore} from "firebase-admin/firestore";
import {
  HumorCoreRejected,
  getHumorCoreDailyView,
  submitHumorCoreResponse,
  type HumorCoreDailyView,
} from "./coreService.js";
import {isDayId} from "./daily.js";
import {HUMOR_CONTENT_ID_PATTERN, isValidHumorRating} from "./feedback.js";
import type {HumorRating} from "./types.js";

export {DAILY_DEV_CLOCK_DOC, isEmulatorProcess, resolveDailyToday} from "./clock.js";
export {userHumorDailyPath} from "./coreService.js";

export type DailyHumorSetView = HumorCoreDailyView;

/** `getDailyHumorSet`: today's Core entries for [uid], feed-safe, with resumable progress. */
export async function getDailyHumorSetView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
}): Promise<DailyHumorSetView> {
  return getHumorCoreDailyView(input);
}

// ---------------------------------------------------------------------------
// Answers
// ---------------------------------------------------------------------------

export type DailyResponseInput = {
  dayId: string;
  contentId: string;
  rating: HumorRating | null;
  /** Only `media_failed` skips exist in the daily set. */
  skipped: boolean;
  dwellMs: number;
  replayCount: number;
};

/** Error messages the callable maps to `failed-precondition`. */
export type DailyRejection = "day-closed" | "slot-replaced" | "not-eligible";

export class DailyResponseRejected extends Error {
  constructor(readonly reason: DailyRejection) {
    super(reason);
  }
}

export function parseDailyResponseInput(
  data: unknown,
): {ok: true; value: DailyResponseInput} | {ok: false; field: string} {
  const raw =
    data && typeof data === "object" && !Array.isArray(data)
      ? (data as Record<string, unknown>)
      : {};
  if (!isDayId(raw.dayId)) {
    return {ok: false, field: "dayId"};
  }
  const contentId = typeof raw.contentId === "string" ? raw.contentId.trim() : "";
  if (!HUMOR_CONTENT_ID_PATTERN.test(contentId)) {
    return {ok: false, field: "contentId"};
  }
  const skipped = raw.skipped === true;
  if (skipped) {
    // The daily set has no "not interested" skip: only media that would not play.
    if (raw.skipReason !== "media_failed") {
      return {ok: false, field: "skipReason"};
    }
  } else if (!isValidHumorRating(raw.rating)) {
    return {ok: false, field: "rating"};
  }
  const count = (value: unknown, max: number): number =>
    typeof value === "number" && Number.isFinite(value)
      ? Math.min(max, Math.max(0, Math.floor(value)))
      : 0;
  return {
    ok: true,
    value: {
      dayId: raw.dayId,
      contentId,
      rating: skipped ? null : (raw.rating as HumorRating),
      skipped,
      dwellMs: count(raw.dwellMs, 24 * 60 * 60 * 1000),
      replayCount: count(raw.replayCount, 1000),
    },
  };
}

export type DailyResponseResult = {
  ok: true;
  dayId: string;
  setVersion: number;
  total: number;
  answeredCount: number;
  completed: boolean;
  nextIndex: number;
  alreadyAnswered: boolean;
};

/**
 * `submitDailyHumorResponse`.
 *
 * The day and the content id the client names are only ever *checked* against
 * what the server computed: a day that is not the server's today is
 * `day-closed`, and an id that is not one of the member's entries for today —
 * tomorrow's, an earlier one, or anything else — is `slot-replaced`. Both are
 * the reasons a client already answers by reloading the set.
 *
 * Idempotent per entry: the same answer again changes nothing; a different
 * rating follows the Humor Lab re-rating semantics (replaces the earlier
 * contribution, never adds a second one); a media skip never overrides a
 * rating and never teaches the profile.
 */
export async function submitDailyHumorResponse(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  response: DailyResponseInput;
}): Promise<DailyResponseResult> {
  const {response} = input;
  try {
    const result = await submitHumorCoreResponse({
      db: input.db,
      uid: input.uid,
      nowMs: input.nowMs,
      contentId: response.contentId,
      rating: response.rating,
      mediaFailed: response.skipped,
      expectedDayId: response.dayId,
      dwellMs: response.dwellMs,
      replayCount: response.replayCount,
    });
    return {
      ok: true,
      dayId: result.dayId,
      setVersion: 1,
      total: result.progress.total,
      answeredCount: result.progress.answeredCount,
      completed: result.progress.completed,
      nextIndex: result.progress.nextIndex,
      alreadyAnswered: result.alreadyAnswered,
    };
  } catch (error) {
    if (error instanceof HumorCoreRejected) {
      throw new DailyResponseRejected(
        error.reason === "day-closed" ? "day-closed" : "slot-replaced",
      );
    }
    throw error;
  }
}
