/**
 * Daily Humor Evolution — Firestore side.
 *
 * Documents:
 * - `humorDailySets/{dayId}` — the global manifest for one canonical day:
 *   ten content ids in a fixed order, published once (transaction), never
 *   reshuffled. Clients cannot read or write it; members get the set only
 *   through `getDailyHumorSet`, feed-safe. A day the catalogue cannot fill is
 *   recorded as `status: "not_ready"` and re-checked at most every
 *   `notReadyRecheckMs` — never padded with filler.
 * - `users/{uid}/humorDaily/{dayId}` — one member's progress on that day:
 *   answers keyed by manifest slot, counters, start/completion stamps.
 *   Owner-read, server-write only.
 *
 * Answers go through the same feedback transaction as the Humor Lab
 * (`applyHumorFeedbackInTx`), in the same transaction as the progress write,
 * so a response updates the lifetime profile at most once and progress can
 * never drift from what was learned.
 */
import {
  FieldValue,
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";
import {isHumorCalibrationReady} from "./compatibility.js";
import {parseCalibrationState} from "./calibration.js";
import {
  HUMOR_CONTENT_COLLECTION,
  parseHumorContent,
  toFeedSafeContent,
} from "./contentRepository.js";
import {
  DAILY_HUMOR_CONFIG,
  dailyEligibility,
  dailyIneligibility,
  dailyProgress,
  canonicalDayId,
  isDayId,
  parseDailyAnswers,
  selectDailySet,
  selectRepairItem,
  shiftDayId,
  timestampMs,
  validateDailySet,
  type DailyAnswer,
  type DailyLockedReason,
} from "./daily.js";
import {
  applyHumorFeedbackInTx,
  finishHumorFeedback,
  prepareHumorFeedback,
  readHumorFeedbackState,
  HUMOR_CONTENT_ID_PATTERN,
  isValidHumorRating,
} from "./feedback.js";
import type {HumorContentDoc, HumorFeedItem, HumorRating, UserHumorProfileDoc} from "./types.js";

export const HUMOR_DAILY_SETS = "humorDailySets";
export const humorDailySetPath = (dayId: string): string => `${HUMOR_DAILY_SETS}/${dayId}`;
export const userHumorDailyPath = (uid: string, dayId: string): string =>
  `users/${uid}/humorDaily/${dayId}`;

/**
 * Emulator-only clock override: `devClock/humorDaily {dayId}`. Read only when
 * the process runs inside the Functions emulator, so a deployed function can
 * never be steered to another day. Clients cannot write it (rules deny).
 */
export const DAILY_DEV_CLOCK_DOC = "devClock/humorDaily";

export function isEmulatorProcess(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

/** Today's canonical day id. Server clock; emulator override only in the emulator. */
export async function resolveDailyToday(db: Firestore, nowMs: number): Promise<string> {
  if (isEmulatorProcess()) {
    const clock = await db.doc(DAILY_DEV_CLOCK_DOC).get();
    const override = clock.data()?.dayId;
    if (isDayId(override)) {
      return override;
    }
  }
  return canonicalDayId(nowMs);
}

// ---------------------------------------------------------------------------
// Manifest
// ---------------------------------------------------------------------------

export type DailyManifest = {
  dayId: string;
  status: "published";
  version: number;
  contentIds: string[];
};

type ManifestState =
  | {kind: "published"; manifest: DailyManifest}
  | {kind: "not_ready"; checkedAtMs: number}
  | {kind: "missing"};

export function parseManifest(data: DocumentData | undefined): ManifestState {
  if (!data) {
    return {kind: "missing"};
  }
  if (data.status === "published" && Array.isArray(data.contentIds)) {
    const contentIds = data.contentIds.filter(
      (id: unknown): id is string => typeof id === "string" && HUMOR_CONTENT_ID_PATTERN.test(id),
    );
    if (contentIds.length === data.contentIds.length && contentIds.length > 0) {
      return {
        kind: "published",
        manifest: {
          dayId: String(data.dayId ?? ""),
          status: "published",
          version: Math.max(1, Math.floor(Number(data.version ?? 1)) || 1),
          contentIds,
        },
      };
    }
  }
  if (data.status === "not_ready") {
    return {kind: "not_ready", checkedAtMs: Number(data.checkedAtMs ?? 0) || 0};
  }
  return {kind: "missing"};
}

/**
 * Every catalogue item that could go into a daily set, sorted by id so the
 * selection never depends on query plan. Bounded by `poolScanLimit`.
 */
export async function loadDailyPool(db: Firestore): Promise<HumorContentDoc[]> {
  const limit = DAILY_HUMOR_CONFIG.poolScanLimit;
  const run = async (query: FirebaseFirestore.Query): Promise<HumorContentDoc[]> => {
    const snap = await query.get();
    return snap.docs
      .map((doc) => parseHumorContent(doc.id, doc.data()))
      .filter((c): c is HumorContentDoc => c !== null && dailyIneligibility(c) === null)
      .sort((a, b) => (a.contentId < b.contentId ? -1 : a.contentId > b.contentId ? 1 : 0));
  };
  const collection = db.collection(HUMOR_CONTENT_COLLECTION);
  try {
    return await run(
      collection.where("active", "==", true).where("safetyStatus", "==", "approved").limit(limit),
    );
  } catch {
    return run(collection.where("active", "==", true).limit(limit));
  }
}

async function recentDayContentIds(db: Firestore, dayId: string): Promise<string[][]> {
  const days = Array.from({length: DAILY_HUMOR_CONFIG.recentRepeatDays}, (_, i) =>
    shiftDayId(dayId, -(i + 1)),
  );
  const snaps = await db.getAll(...days.map((d) => db.doc(humorDailySetPath(d))));
  return snaps.map((snap) => {
    const state = parseManifest(snap.data());
    return state.kind === "published" ? state.manifest.contentIds : [];
  });
}

export type EnsureDailySetResult =
  | {status: "published"; manifest: DailyManifest; created: boolean}
  | {status: "not_ready"; eligiblePoolSize: number | null};

/**
 * The published set for [dayId], publishing it first if nobody has yet.
 *
 * Selection runs outside the transaction (it scans the catalogue); the
 * publish itself is a transaction on the manifest document, so concurrent
 * first requests all end up with the one set that won. A published manifest
 * is never overwritten here — only `repairDailySlot` changes one, explicitly.
 */
export async function ensureDailySet(input: {
  db: Firestore;
  dayId: string;
  nowMs: number;
  publishedBy: string;
  /** Skip the not-ready back-off (admin publish). */
  force?: boolean;
}): Promise<EnsureDailySetResult> {
  const {db, dayId} = input;
  const ref = db.doc(humorDailySetPath(dayId));
  const current = parseManifest((await ref.get()).data());
  if (current.kind === "published") {
    return {status: "published", manifest: current.manifest, created: false};
  }
  if (
    current.kind === "not_ready" &&
    !input.force &&
    input.nowMs - current.checkedAtMs < DAILY_HUMOR_CONFIG.notReadyRecheckMs
  ) {
    return {status: "not_ready", eligiblePoolSize: null};
  }

  const [pool, recentByDay] = await Promise.all([
    loadDailyPool(db),
    recentDayContentIds(db, dayId),
  ]);
  const selection = selectDailySet({dayId, pool, recentByDay});

  try {
    return await publishInTransaction(db, ref, dayId, selection, input);
  } catch (error) {
    // Lost a publish race: the manifest another request created is the day's
    // set. Anything else is a real failure.
    const winner = parseManifest((await ref.get()).data());
    if (winner.kind === "published") {
      return {status: "published", manifest: winner.manifest, created: false};
    }
    if (winner.kind === "not_ready" && !selection.ok) {
      return {status: "not_ready", eligiblePoolSize: selection.eligiblePoolSize};
    }
    throw error;
  }
}

/**
 * The publish itself. A missing manifest is written with `create`, which
 * fails if any other request created it first — atomic on its own, and the
 * transaction additionally re-reads so a stale "not ready" marker is only
 * replaced while it is still the current state.
 */
async function publishInTransaction(
  db: Firestore,
  ref: FirebaseFirestore.DocumentReference,
  dayId: string,
  selection: ReturnType<typeof selectDailySet>,
  input: {nowMs: number; publishedBy: string},
): Promise<EnsureDailySetResult> {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const again = parseManifest(snap.data());
    if (again.kind === "published") {
      return {status: "published" as const, manifest: again.manifest, created: false};
    }
    const write = (data: Record<string, unknown>): void => {
      if (snap.exists) {
        tx.set(ref, data);
      } else {
        tx.create(ref, data);
      }
    };
    if (!selection.ok) {
      write({
        dayId,
        status: "not_ready",
        reason: selection.reason,
        eligiblePoolSize: selection.eligiblePoolSize,
        checkedAtMs: input.nowMs,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {status: "not_ready" as const, eligiblePoolSize: selection.eligiblePoolSize};
    }
    const manifest: DailyManifest = {
      dayId,
      status: "published",
      version: 1,
      contentIds: selection.items.map((c) => c.contentId),
    };
    write({
      ...manifest,
      schema: DAILY_HUMOR_CONFIG.schema,
      selector: DAILY_HUMOR_CONFIG.selector,
      total: manifest.contentIds.length,
      // Server-only: the primary dimension per slot, for pool-health review.
      categories: selection.items.map((c) => c.category),
      eligiblePoolSize: selection.eligiblePoolSize,
      recentDaysExcluded: selection.recentDaysExcluded,
      publishedBy: input.publishedBy,
      publishedAtMs: input.nowMs,
      publishedAt: FieldValue.serverTimestamp(),
      repairs: [],
    });
    return {status: "published" as const, manifest, created: true};
  });
}

async function loadManifestContents(
  db: Firestore,
  manifest: DailyManifest,
): Promise<(HumorContentDoc | null)[]> {
  const snaps = await db.getAll(
    ...manifest.contentIds.map((id) => db.collection(HUMOR_CONTENT_COLLECTION).doc(id)),
  );
  return snaps.map((snap) => (snap.exists ? parseHumorContent(snap.id, snap.data()) : null));
}

/**
 * Slots still shown to members. A published item that was taken down since
 * (moderation, deactivation) is never served again; its slot drops out of
 * everyone's day instead of being silently swapped — replacing it is an
 * explicit, versioned admin repair.
 */
export function availableSlots(contents: readonly (HumorContentDoc | null)[]): number[] {
  const out: number[] = [];
  contents.forEach((content, index) => {
    if (content && dailyIneligibility(content) === null) {
      out.push(index);
    }
  });
  return out;
}

// ---------------------------------------------------------------------------
// Member view
// ---------------------------------------------------------------------------

export type DailyAnswerView = {
  index: number;
  contentId: string;
  rating: HumorRating | null;
  skipped: boolean;
};

export type DailyHumorSetView = {
  status: "ready" | "locked" | "not_ready";
  lockedReason: DailyLockedReason | null;
  dayId: string;
  setVersion: number;
  total: number;
  answeredCount: number;
  completed: boolean;
  nextIndex: number;
  items: HumorFeedItem[];
  answers: DailyAnswerView[];
};

function emptyView(
  dayId: string,
  status: "locked" | "not_ready",
  lockedReason: DailyLockedReason | null,
): DailyHumorSetView {
  return {
    status,
    lockedReason,
    dayId,
    setVersion: 0,
    total: DAILY_HUMOR_CONFIG.setSize,
    answeredCount: 0,
    completed: false,
    nextIndex: 0,
    items: [],
    answers: [],
  };
}

/** Progress over the available slots only, in view positions. */
export function viewProgress(
  available: readonly number[],
  answers: Map<number, DailyAnswer>,
): {total: number; answeredCount: number; completed: boolean; nextIndex: number} {
  const byPosition = new Map<number, DailyAnswer>();
  available.forEach((slot, position) => {
    const answer = answers.get(slot);
    if (answer) byPosition.set(position, answer);
  });
  return {total: available.length, ...dailyProgress(byPosition, available.length)};
}

function memberEligibility(
  calibrationData: DocumentData | undefined,
  profileData: DocumentData | undefined,
  todayId: string,
): ReturnType<typeof dailyEligibility> {
  const profile = {
    interactionCount: Math.max(0, Math.floor(Number(profileData?.interactionCount ?? 0)) || 0),
  } as UserHumorProfileDoc;
  const state = parseCalibrationState(calibrationData);
  return dailyEligibility({
    ready: isHumorCalibrationReady(calibrationData, profile),
    completedAtMs: state.complete ? timestampMs(state.completedAt) : null,
    todayId,
  });
}

/** `getDailyHumorSet`: today's set for [uid], feed-safe, with resumable progress. */
export async function getDailyHumorSetView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
}): Promise<DailyHumorSetView> {
  const {db, uid} = input;
  const dayId = await resolveDailyToday(db, input.nowMs);
  const [calibrationSnap, profileSnap] = await Promise.all([
    db.doc(`users/${uid}/humor/calibration`).get(),
    db.doc(`users/${uid}/humor/summary`).get(),
  ]);
  const eligibility = memberEligibility(calibrationSnap.data(), profileSnap.data(), dayId);
  if (!eligibility.eligible) {
    return emptyView(dayId, "locked", eligibility.reason);
  }

  const ensured = await ensureDailySet({
    db,
    dayId,
    nowMs: input.nowMs,
    publishedBy: "auto",
  });
  if (ensured.status !== "published") {
    return emptyView(dayId, "not_ready", null);
  }
  const manifest = ensured.manifest;
  const [contents, userSnap] = await Promise.all([
    loadManifestContents(db, manifest),
    db.doc(userHumorDailyPath(uid, dayId)).get(),
  ]);
  const available = availableSlots(contents);
  if (available.length === 0) {
    return emptyView(dayId, "not_ready", null);
  }
  const answers = parseDailyAnswers(userSnap.data()?.answers, manifest.contentIds.length);
  const progress = viewProgress(available, answers);
  return {
    status: "ready",
    lockedReason: null,
    dayId,
    setVersion: manifest.version,
    ...progress,
    items: available.map((slot) => toFeedSafeContent(contents[slot] as HumorContentDoc, null)),
    answers: available.flatMap((slot, position) => {
      const answer = answers.get(slot);
      return answer
        ? [{index: position, contentId: answer.contentId, rating: answer.rating, skipped: answer.skipped}]
        : [];
    }),
  };
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
 * Idempotent per slot: the same answer again changes nothing; a different
 * rating for an answered slot follows the Humor Lab re-rating semantics
 * (replaces the earlier contribution, never adds a second one); a media skip
 * never overrides a rating. The last available slot completes the day.
 */
export async function submitDailyHumorResponse(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  response: DailyResponseInput;
}): Promise<DailyResponseResult> {
  const {db, uid, response} = input;
  const todayId = await resolveDailyToday(db, input.nowMs);
  if (response.dayId !== todayId) {
    throw new DailyResponseRejected("day-closed");
  }
  const manifestRef = db.doc(humorDailySetPath(todayId));
  const manifestState = parseManifest((await manifestRef.get()).data());
  if (manifestState.kind !== "published") {
    throw new DailyResponseRejected("day-closed");
  }
  const slot = manifestState.manifest.contentIds.indexOf(response.contentId);
  if (slot < 0) {
    throw new DailyResponseRejected("slot-replaced");
  }
  const contents = await loadManifestContents(db, manifestState.manifest);
  const available = availableSlots(contents);
  if (!available.includes(slot)) {
    throw new DailyResponseRejected("slot-replaced");
  }

  // Throws `content-unavailable` exactly as the Humor Lab path would.
  const prepared = await prepareHumorFeedback({
    db,
    uid,
    contentId: response.contentId,
    rating: response.rating,
    skipped: response.skipped,
    skipReason: response.skipped ? "media_failed" : undefined,
    dwellMs: response.dwellMs,
    replayCount: response.replayCount,
  });
  const userRef = db.doc(userHumorDailyPath(uid, todayId));

  const outcome = await db.runTransaction(async (tx) => {
    const [manifestSnap, userSnap] = await Promise.all([tx.get(manifestRef), tx.get(userRef)]);
    const reads = await readHumorFeedbackState(tx, prepared);

    const manifest = parseManifest(manifestSnap.data());
    if (manifest.kind !== "published" || manifest.manifest.contentIds[slot] !== response.contentId) {
      throw new DailyResponseRejected("slot-replaced");
    }
    const eligibility = memberEligibility(
      reads.calibrationSnap.data(),
      reads.profileSnap.data(),
      todayId,
    );
    if (!eligibility.eligible) {
      throw new DailyResponseRejected("not-eligible");
    }

    const total = manifest.manifest.contentIds.length;
    const answers = parseDailyAnswers(userSnap.data()?.answers, total);
    const existing = answers.get(slot);
    const sameAnswer =
      existing !== undefined &&
      existing.contentId === response.contentId &&
      (response.skipped
        ? true // a media skip never overrides whatever is recorded
        : !existing.skipped && existing.rating === response.rating);
    const before = viewProgress(available, answers);
    if (sameAnswer) {
      return {
        feedback: null,
        progress: before,
        version: manifest.manifest.version,
        alreadyAnswered: true,
      };
    }

    const feedback = applyHumorFeedbackInTx(tx, prepared, reads);
    const answer: DailyAnswer = {
      contentId: response.contentId,
      rating: response.rating,
      skipped: response.skipped,
    };
    answers.set(slot, answer);
    const after = viewProgress(available, answers);
    const now = FieldValue.serverTimestamp();
    const wasCompleted = userSnap.data()?.completed === true;
    tx.set(
      userRef,
      {
        dayId: todayId,
        setVersion: manifest.manifest.version,
        total: after.total,
        answers: {
          [String(slot)]: {
            ...answer,
            ...(response.skipped ? {skipReason: "media_failed"} : {}),
            answeredAtMs: input.nowMs,
          },
        },
        answeredCount: after.answeredCount,
        completed: after.completed,
        ...(userSnap.exists ? {} : {startedAt: now}),
        ...(after.completed && !wasCompleted ? {completedAt: now} : {}),
        updatedAt: now,
      },
      {merge: true},
    );
    return {
      feedback,
      progress: after,
      version: manifest.manifest.version,
      alreadyAnswered: existing !== undefined,
    };
  });

  if (outcome.feedback) {
    await finishHumorFeedback(db, prepared, outcome.feedback);
  }
  return {
    ok: true,
    dayId: todayId,
    setVersion: outcome.version,
    ...outcome.progress,
    alreadyAnswered: outcome.alreadyAnswered,
  };
}

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

/**
 * Which days an admin may publish or repair. In production: today and
 * tomorrow only (pre-publishing tomorrow is the one legitimate reason to name
 * a day). In the emulator: any valid day, for tests.
 */
export function adminDayAllowed(dayId: string, todayId: string, emulator: boolean): boolean {
  if (!isDayId(dayId)) return false;
  if (emulator) return true;
  return dayId === todayId || dayId === shiftDayId(todayId, 1);
}

/**
 * Replace slot [index] of a published set — explicit, versioned, recorded.
 * Members who already answered the old item keep that answer; the others
 * meet the replacement. Validated like a fresh set.
 */
export async function repairDailySlot(input: {
  db: Firestore;
  dayId: string;
  index: number;
  reason: string;
  adminUid: string;
  nowMs: number;
}): Promise<{ok: true; version: number; from: string; to: string}> {
  const {db, dayId, index} = input;
  const ref = db.doc(humorDailySetPath(dayId));
  const state = parseManifest((await ref.get()).data());
  if (state.kind !== "published") {
    throw new Error("not-published");
  }
  if (!Number.isInteger(index) || index < 0 || index >= state.manifest.contentIds.length) {
    throw new Error("bad-index");
  }
  const [contents, pool] = await Promise.all([
    loadManifestContents(db, state.manifest),
    loadDailyPool(db),
  ]);
  // The slot being replaced may be broken; the others must stay as published.
  const current = contents.map((c, i) => (i === index ? null : c));
  if (current.some((c, i) => i !== index && c === null)) {
    throw new Error("other-slot-missing");
  }
  const replacement = selectRepairItem({
    dayId,
    current,
    index,
    pool,
    version: state.manifest.version,
    excludeIds: [state.manifest.contentIds[index]],
  });
  if (!replacement) {
    throw new Error("no-replacement");
  }
  const next = current.map((c, i) => (i === index ? replacement : c)) as HumorContentDoc[];
  const problem = validateDailySet(next);
  if (problem) {
    throw new Error(`invalid-set:${problem}`);
  }
  return db.runTransaction(async (tx) => {
    const again = parseManifest((await tx.get(ref)).data());
    if (again.kind !== "published" || again.manifest.version !== state.manifest.version) {
      throw new Error("concurrent-change");
    }
    const from = again.manifest.contentIds[index];
    const contentIds = again.manifest.contentIds.slice();
    contentIds[index] = replacement.contentId;
    const version = again.manifest.version + 1;
    tx.update(ref, {
      contentIds,
      version,
      categories: next.map((c) => c.category),
      repairs: FieldValue.arrayUnion({
        index,
        from,
        to: replacement.contentId,
        reason: input.reason.slice(0, 200),
        version,
        by: input.adminUid,
        atMs: input.nowMs,
      }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true as const, version, from, to: replacement.contentId};
  });
}
