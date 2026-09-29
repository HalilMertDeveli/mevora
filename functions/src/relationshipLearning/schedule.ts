import {
  DAILY_QUESTION_COUNT,
  LEARNING_CATALOG_VERSION,
  dailyEligibleQuestions,
  learningQuestion,
  type LearningCategory,
  type LearningQuestion,
} from "./catalog.js";
import {DAILY} from "./config.js";

/**
 * The global daily question set. Pure and deterministic: the date is the only
 * input. No member id, device or time of day takes part, so everyone asking
 * on the same logical day gets the same 10 questions in the same order.
 *
 * Rotation: the eligible bank is laid out once in a category-interleaved
 * order, and day N takes the next 10 in that cycle. Every question is asked
 * once before any repeats, and each day mixes areas instead of asking ten
 * lifestyle questions in a row.
 */

const DAY_MS = 86_400_000;

/** The logical day `nowMs` falls in, YYYY-MM-DD at the product offset. */
export function learningDayKey(nowMs: number): string {
  return new Date(nowMs + DAILY.utcOffsetMinutes * 60_000).toISOString().slice(0, 10);
}

/** When the logical day containing `nowMs` ends. */
export function nextLearningDayStartMs(nowMs: number): number {
  const offsetMs = DAILY.utcOffsetMinutes * 60_000;
  return Math.floor((nowMs + offsetMs) / DAY_MS) * DAY_MS + DAY_MS - offsetMs;
}

export function isDateKey(value: unknown): value is string {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00Z`));
}

/** Days from the rotation anchor to `dateKey` (negative before it). */
export function dayIndex(dateKey: string): number {
  return Math.round((Date.parse(`${dateKey}T00:00:00Z`) - Date.parse(`${DAILY.anchorDateKey}T00:00:00Z`)) / DAY_MS);
}

const CATEGORY_ORDER: LearningCategory[] = [
  "communication",
  "relationship",
  "values",
  "lifestyle",
  "humor",
  "interests",
  "music",
];

/**
 * The rotation cycle: take one question from each area in turn, in catalog
 * order within an area, until every eligible question is placed.
 */
export function rotationOrder(questions: LearningQuestion[] = dailyEligibleQuestions()): LearningQuestion[] {
  const queues = CATEGORY_ORDER.map((category) => questions.filter((q) => q.category === category));
  const out: LearningQuestion[] = [];
  while (queues.some((queue) => queue.length > 0)) {
    for (const queue of queues) {
      const next = queue.shift();
      if (next) out.push(next);
    }
  }
  return out;
}

/** The ten question ids scheduled for `dateKey`, in order. */
export function scheduledQuestionIds(dateKey: string, cycle: LearningQuestion[] = rotationOrder()): string[] {
  const n = cycle.length;
  if (n < DAILY_QUESTION_COUNT) {
    throw new Error(`question bank too small: ${n} < ${DAILY_QUESTION_COUNT}`);
  }
  const start = ((dayIndex(dateKey) * DAILY_QUESTION_COUNT) % n + n) % n;
  return Array.from({length: DAILY_QUESTION_COUNT}, (_, i) => cycle[(start + i) % n].id);
}

export interface DailyQuestionRef {
  id: string;
  version: number;
}

export interface DailySet {
  dateKey: string;
  questionSetId: string;
  scheduleVersion: number;
  contentVersion: number;
  questions: DailyQuestionRef[];
}

export function questionSetIdFor(dateKey: string): string {
  return `daily-${dateKey}-s${DAILY.scheduleVersion}`;
}

export function buildDailySet(dateKey: string): DailySet {
  return {
    dateKey,
    questionSetId: questionSetIdFor(dateKey),
    scheduleVersion: DAILY.scheduleVersion,
    contentVersion: LEARNING_CATALOG_VERSION,
    questions: scheduledQuestionIds(dateKey).map((id) => ({
      id,
      version: (learningQuestion(id) as LearningQuestion).version,
    })),
  };
}

/**
 * Reads a persisted set. A set that is malformed, belongs to another date or
 * schedule, or names a question that no longer exists or is no longer active
 * is not served (it could never be completed); the caller replaces it for
 * everyone at once.
 */
export function parseDailySet(raw: unknown, dateKey: string): DailySet | null {
  if (!raw || typeof raw !== "object") return null;
  const data = raw as Record<string, unknown>;
  if (data.dateKey !== dateKey || data.questionSetId !== questionSetIdFor(dateKey)) return null;
  if (!Array.isArray(data.questions) || data.questions.length !== DAILY_QUESTION_COUNT) return null;
  const questions: DailyQuestionRef[] = [];
  for (const item of data.questions) {
    if (!item || typeof item !== "object") return null;
    const ref = item as Record<string, unknown>;
    const question = learningQuestion(ref.id);
    if (!question || !question.active || question.version !== ref.version) return null;
    questions.push({id: question.id, version: question.version});
  }
  if (new Set(questions.map((q) => q.id)).size !== questions.length) return null;
  return {
    dateKey,
    questionSetId: questionSetIdFor(dateKey),
    scheduleVersion: Number(data.scheduleVersion) || DAILY.scheduleVersion,
    contentVersion: Number(data.contentVersion) || LEARNING_CATALOG_VERSION,
    questions,
  };
}
