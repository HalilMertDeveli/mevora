/**
 * Humor Core progression — Firestore side.
 *
 * Documents:
 * - `users/{uid}/humor/core` — where one member stands in the canonical
 *   sequence: what they rated, what was waived for them, and the ids frozen as
 *   today's set. Owner-read, server-write only (the existing
 *   `match /humor/{docId}` rule), and swept with the rest of
 *   `users/{uid}/humor` on account deletion.
 * - `users/{uid}/humorDaily/{dayId}` — one compact record per completed day.
 *
 * The server decides everything: the logical day, today's ids, whether a
 * response belongs to them. A response is only ever accepted for an entry in
 * the set computed here, so a client cannot choose content, a position or a
 * day. Learning is untouched — a rating goes through the same feedback
 * transaction as before (`applyHumorFeedbackInTx`), in the same transaction as
 * the progress write, so it reaches the lifetime profile at most once and
 * progress can never drift from what was learned.
 */
import {
  FieldValue,
  type DocumentReference,
  type Firestore,
  type Transaction,
} from "firebase-admin/firestore";
import {
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
  parseCalibrationState,
  stageForCompletedCount,
  type CalibrationStateView,
} from "./calibration.js";
import {normalizeHumorVector} from "./categories.js";
import {isEmulatorProcess, resolveDailyToday} from "./clock.js";
import {isHumorCalibrationReady} from "./compatibility.js";
import {
  HUMOR_CONTENT_COLLECTION,
  parseHumorContent,
  toFeedSafeContent,
} from "./contentRepository.js";
import {
  HUMOR_CORE,
  HUMOR_CORE_RELEASE,
  HUMOR_CORE_SEQUENCE,
  humorCorePosition,
  humorCoreSequenceProblems,
  type HumorCoreEntry,
} from "./coreSequence.js";
import {
  applyCoreMediaFailure,
  applyCoreRating,
  applyCoreReport,
  coreOnboardingProgress,
  coreSetProgress,
  hasFinishedCoreOnboarding,
  isCoreSequenceExhausted,
  memberCoreSet,
  migrateLegacyHumorCoreState,
  parseHumorCoreState,
  type HumorCoreApplyResult,
  type HumorCoreSet,
  type HumorCoreSetProgress,
  type HumorCoreState,
} from "./coreSchedule.js";
import {canonicalDayId, timestampMs, type DailyLockedReason} from "./daily.js";
import {HUMOR_CALIBRATION_DOC, loadUserHumorProfile} from "./feed.js";
import {
  applyHumorFeedbackInTx,
  finishHumorFeedback,
  getHumorProfileView,
  isValidHumorRating,
  prepareHumorFeedback,
  readHumorFeedbackState,
  type HumorFeedbackResult,
  type HumorGestureHints,
} from "./feedback.js";
import {canServeHumorContent} from "./moderation.js";
import {isProfileBuilding} from "./profile.js";
import type {
  HumorContentDoc,
  HumorFeedItem,
  HumorRating,
  UserHumorProfileDoc,
} from "./types.js";

export const userHumorCorePath = (uid: string): string => `users/${uid}/humor/core`;
export const userHumorDailyPath = (uid: string, dayId: string): string =>
  `users/${uid}/humorDaily/${dayId}`;

/** Marks a `humorDaily` record written by the Core sequence (not the old daily set). */
export const HUMOR_CORE_DAY_SCHEMA = "core-1";

/**
 * A Core entry is handed out only while its content document is live and
 * curated. Anything else — taken down, deactivated, missing, or somehow not a
 * curated item — is skipped like a retired entry.
 */
function coreServable(content: HumorContentDoc | null | undefined): content is HumorContentDoc {
  return (
    !!content &&
    content.sourceTrust === "curated" &&
    canServeHumorContent({active: content.active, safetyStatus: content.safetyStatus})
  );
}

/**
 * Whether this process hands out Core content at all.
 *
 * Until the owner releases the sequence (`HUMOR_CORE_RELEASE`) its order is a
 * draft that may still be rewritten, and a rating taken against a draft
 * position would not mean what the released position means. So a deployed
 * backend serves nothing from a draft. The emulator keeps serving it: that is
 * where the draft is reviewed and where QA and the humor suites run.
 */
export function isHumorCoreServed(
  release: {readonly released: boolean} = HUMOR_CORE_RELEASE,
): boolean {
  return release.released || isEmulatorProcess();
}

async function loadContents(
  db: Firestore,
  ids: readonly string[],
): Promise<Map<string, HumorContentDoc | null>> {
  const out = new Map<string, HumorContentDoc | null>();
  if (ids.length === 0) {
    return out;
  }
  const snaps = await db.getAll(
    ...ids.map((id) => db.collection(HUMOR_CONTENT_COLLECTION).doc(id)),
  );
  snaps.forEach((snap, index) => {
    out.set(ids[index], snap.exists ? parseHumorContent(snap.id, snap.data() ?? {}) : null);
  });
  return out;
}

type ResolvedSet = {
  set: HumorCoreSet;
  contents: Map<string, HumorContentDoc | null>;
  unavailable: Set<string>;
};

/**
 * Today's set with the entries whose content cannot be served taken out.
 *
 * Only the documents of the candidate set are read. An unservable candidate is
 * added to `unavailable` and the set recomputed, so the next entry in canonical
 * order takes its place — until the day is frozen, after which a set only ever
 * shrinks.
 */
async function resolveMemberSet(
  db: Firestore,
  state: HumorCoreState,
  dayId: string,
  sequence: readonly HumorCoreEntry[],
): Promise<ResolvedSet> {
  const contents = new Map<string, HumorContentDoc | null>();
  // Not served here (a draft sequence in a deployed backend): every entry is
  // unavailable, exactly as if its content had been taken down. The callers
  // need no case of their own — the feed reports an empty catalogue, the daily
  // set stays locked and a response is `not-in-set` before anything is
  // learned — and no content document is read.
  if (!isHumorCoreServed()) {
    const withheld = new Set(sequence.map((entry) => entry.id));
    return {set: memberCoreSet(state, dayId, sequence, withheld), contents, unavailable: withheld};
  }
  const unavailable = new Set<string>();
  for (let round = 0; round <= sequence.length; round += 1) {
    const set = memberCoreSet(state, dayId, sequence, unavailable);
    const unread = set.contentIds.filter((id) => !contents.has(id));
    for (const [id, content] of await loadContents(db, unread)) {
      contents.set(id, content);
    }
    const unservable = set.contentIds.filter((id) => !coreServable(contents.get(id)));
    if (unservable.length === 0) {
      return {set, contents, unavailable};
    }
    unservable.forEach((id) => unavailable.add(id));
  }
  return {set: memberCoreSet(state, dayId, sequence, unavailable), contents, unavailable};
}

function coreStatePayload(
  state: HumorCoreState,
  sequence: readonly HumorCoreEntry[],
): Record<string, unknown> {
  return {
    schemaVersion: state.schemaVersion,
    answers: state.answers,
    waived: state.waived,
    mediaFailures: state.mediaFailures,
    initialCompletedAtMs: state.initialCompletedAtMs,
    today: state.today,
    completedDays: state.completedDays,
    migration: state.migration,
    sequenceLength: sequence.length,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * The member's Core state, created on first use.
 *
 * Creation is the migration: a member with humor history gets their ratings of
 * Core entries carried over and their old calibration honoured (see
 * `migrateLegacyHumorCoreState`). It writes this one document and nothing
 * else — no profile, interaction or old daily document is touched. `create`
 * makes concurrent first requests agree on one state.
 */
export async function ensureHumorCoreState(input: {
  db: Firestore;
  uid: string;
  todayId: string;
  nowMs: number;
  sequence?: readonly HumorCoreEntry[];
}): Promise<HumorCoreState> {
  const {db, uid, todayId, nowMs} = input;
  const sequence = input.sequence ?? HUMOR_CORE_SEQUENCE;
  const ref = db.doc(userHumorCorePath(uid));
  const existing = await ref.get();
  if (existing.exists) {
    return parseHumorCoreState(existing.data(), sequence);
  }

  const [calibrationSnap, summarySnap, dailySnap] = await Promise.all([
    db.doc(HUMOR_CALIBRATION_DOC(uid)).get(),
    db.doc(`users/${uid}/humor/summary`).get(),
    db.doc(userHumorDailyPath(uid, todayId)).get(),
  ]);
  const interactions = new Map<string, {rating?: unknown; reported?: unknown}>();
  // A member with no humor documents has nothing to carry over.
  if (calibrationSnap.exists || summarySnap.exists) {
    const snaps = await db.getAll(
      ...sequence.map((entry) => db.doc(`users/${uid}/humorInteractions/${entry.id}`)),
    );
    snaps.forEach((snap, index) => {
      if (snap.exists) {
        interactions.set(sequence[index].id, snap.data() ?? {});
      }
    });
  }
  const calibration = parseCalibrationState(calibrationSnap.data());
  const profile = {
    interactionCount: Math.max(
      0,
      Math.floor(Number(summarySnap.data()?.interactionCount ?? 0)) || 0,
    ),
  } as UserHumorProfileDoc;
  const daily = dailySnap.data();
  const state = migrateLegacyHumorCoreState({
    sequence,
    interactions,
    legacyReady: isHumorCalibrationReady(calibrationSnap.data(), profile),
    legacyCompletedCount: calibration.completedCount,
    legacyCompletedAtMs: calibration.complete ? timestampMs(calibration.completedAt) : null,
    legacyDailyTouchedToday:
      dailySnap.exists &&
      daily?.schema !== HUMOR_CORE_DAY_SCHEMA &&
      Number(daily?.answeredCount ?? 0) > 0,
    todayId,
    dayIdOf: canonicalDayId,
    nowMs,
  });
  try {
    await ref.create(coreStatePayload(state, sequence));
    return state;
  } catch (error) {
    // Lost a create race: the state another request wrote is the member's.
    const winner = await ref.get();
    if (winner.exists) {
      return parseHumorCoreState(winner.data(), sequence);
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Views
// ---------------------------------------------------------------------------

export type HumorCoreSnapshot = {
  dayId: string;
  state: HumorCoreState;
  set: HumorCoreSet;
  progress: HumorCoreSetProgress;
  contents: Map<string, HumorContentDoc | null>;
  unavailable: Set<string>;
  onboarding: {completedCount: number; totalCount: number; complete: boolean};
  /** Every live entry is resolved: there is nothing left to hand out. */
  exhausted: boolean;
};

export async function loadHumorCoreSnapshot(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  sequence?: readonly HumorCoreEntry[];
}): Promise<HumorCoreSnapshot> {
  const sequence = input.sequence ?? HUMOR_CORE_SEQUENCE;
  const dayId = await resolveDailyToday(input.db, input.nowMs);
  const state = await ensureHumorCoreState({...input, todayId: dayId, sequence});
  const resolved = await resolveMemberSet(input.db, state, dayId, sequence);
  return {
    dayId,
    state,
    ...resolved,
    progress: coreSetProgress(state, resolved.set),
    onboarding: coreOnboardingProgress(state, sequence, resolved.unavailable),
    exhausted: isCoreSequenceExhausted(state, sequence, resolved.unavailable),
  };
}

/**
 * The calibration block every humor response carries, derived from the Core
 * state. `stage` is kept only for clients that still read it; nothing selects
 * content by stage any more.
 */
export function coreCalibrationView(onboarding: {
  completedCount: number;
  totalCount: number;
  complete: boolean;
}): CalibrationStateView {
  return {
    version: HUMOR_CALIBRATION_VERSION,
    stage: onboarding.complete
      ? "complete"
      : stageForCompletedCount(Math.min(onboarding.completedCount, CALIBRATION_TOTAL - 1)),
    completedCount: onboarding.completedCount,
    totalCount: onboarding.totalCount,
    complete: onboarding.complete,
    degraded: false,
  };
}

/**
 * The calibration block for [uid] without resolving today's set — for views
 * that only show progress (profile, entry cards).
 */
export async function loadCoreCalibrationView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  sequence?: readonly HumorCoreEntry[];
}): Promise<CalibrationStateView> {
  const sequence = input.sequence ?? HUMOR_CORE_SEQUENCE;
  const todayId = await resolveDailyToday(input.db, input.nowMs);
  const state = await ensureHumorCoreState({...input, todayId, sequence});
  return coreCalibrationView(coreOnboardingProgress(state, sequence));
}

/** `getHumorProfile`: the profile view with Core calibration progress. */
export async function getHumorCoreProfileView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  detailed: boolean;
}): Promise<Record<string, unknown>> {
  const [view, calibration] = await Promise.all([
    getHumorProfileView(input.db, input.uid, input.detailed),
    loadCoreCalibrationView(input),
  ]);
  return {
    ...view,
    profileBuilding: calibration.complete
      ? false
      : calibration.completedCount > 0 || isProfileBuilding(Number(view.interactionCount ?? 0)),
    calibration,
  };
}

/** The `submitHumorFeedback` response for a request that recorded nothing. */
export async function currentHumorFeedbackResult(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
}): Promise<HumorFeedbackResult> {
  const [profile, calibration] = await Promise.all([
    loadUserHumorProfile(input.db, input.uid),
    loadCoreCalibrationView(input),
  ]);
  return toHumorFeedbackResult({
    calibration,
    profile: {interactionCount: profile.interactionCount, confidence: profile.confidence},
  });
}

function feedItems(snapshot: HumorCoreSnapshot, ids: readonly string[]): HumorFeedItem[] {
  return ids.flatMap((id) => {
    const content = snapshot.contents.get(id);
    return content ? [toFeedSafeContent(content, null)] : [];
  });
}

export type HumorCoreFeedView = {
  items: HumorFeedItem[];
  nextCursor: null;
  catalogExhausted: boolean;
  catalogEmpty: boolean;
  profileBuilding: boolean;
  interactionCount: number;
  calibration: CalibrationStateView & {
    insufficientPool: boolean;
    /** The initial calibration is paused for today and resumes tomorrow. */
    continuesTomorrow: boolean;
  };
};

/**
 * `getHumorFeed`: what is left of the initial calibration today, in canonical
 * order. Once the calibration is finished the feed is closed — the daily five
 * are the only Core content — so it answers "caught up".
 */
export async function getHumorCoreFeedView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  sequence?: readonly HumorCoreEntry[];
}): Promise<HumorCoreFeedView> {
  const [snapshot, profile] = await Promise.all([
    loadHumorCoreSnapshot(input),
    loadUserHumorProfile(input.db, input.uid),
  ]);
  const calibrating = !snapshot.onboarding.complete;
  const open =
    calibrating && snapshot.set.kind === "onboarding"
      ? snapshot.set.contentIds.filter((_, index) => snapshot.progress.statuses[index] === "open")
      : [];
  const catalogEmpty = calibrating && snapshot.onboarding.totalCount === 0;
  const continuesTomorrow = calibrating && !catalogEmpty && open.length === 0;
  return {
    items: feedItems(snapshot, open),
    nextCursor: null,
    // Also set while paused, so a client that does not know `continuesTomorrow`
    // shows its caught-up state instead of asking for another page.
    catalogExhausted: !calibrating || continuesTomorrow,
    catalogEmpty,
    profileBuilding: calibrating,
    interactionCount: profile.interactionCount,
    calibration: {
      ...coreCalibrationView(snapshot.onboarding),
      insufficientPool: catalogEmpty,
      continuesTomorrow,
    },
  };
}

export type HumorCoreDailyAnswerView = {
  index: number;
  contentId: string;
  rating: HumorRating | null;
  skipped: boolean;
};

export type HumorCoreDailyView = {
  status: "ready" | "locked" | "not_ready";
  lockedReason: DailyLockedReason | null;
  dayId: string;
  setVersion: number;
  total: number;
  answeredCount: number;
  completed: boolean;
  nextIndex: number;
  items: HumorFeedItem[];
  answers: HumorCoreDailyAnswerView[];
};

function lockedDailyView(dayId: string, reason: DailyLockedReason): HumorCoreDailyView {
  return {
    status: "locked",
    lockedReason: reason,
    dayId,
    setVersion: 0,
    total: HUMOR_CORE.dailyCount,
    answeredCount: 0,
    completed: false,
    nextIndex: 0,
    items: [],
    answers: [],
  };
}

function dailyAnswers(snapshot: HumorCoreSnapshot): HumorCoreDailyAnswerView[] {
  return snapshot.set.contentIds.flatMap((contentId, index) => {
    const status = snapshot.progress.statuses[index];
    if (status === "open") return [];
    const rating = snapshot.state.answers[contentId]?.rating ?? null;
    return [{index, contentId, rating, skipped: rating === null}];
  });
}

/**
 * `getDailyHumorSet`: today's Core entries after the initial calibration.
 *
 * - Calibration open: locked, `calibration_incomplete`.
 * - Calibration finished today (or today already spent): locked,
 *   `starts_tomorrow` — nobody rates fifteen and five in one sitting.
 * - Every live entry resolved: locked, `sequence_complete`.
 * - Otherwise the day's frozen set, at most `HUMOR_CORE.dailyCount` items.
 */
export async function getHumorCoreDailyView(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  sequence?: readonly HumorCoreEntry[];
}): Promise<HumorCoreDailyView> {
  const snapshot = await loadHumorCoreSnapshot(input);
  const {dayId, set, progress} = snapshot;
  if (!snapshot.onboarding.complete) {
    return lockedDailyView(dayId, "calibration_incomplete");
  }
  if (set.kind === "onboarding") {
    return lockedDailyView(dayId, "starts_tomorrow");
  }
  if (set.contentIds.length === 0) {
    return lockedDailyView(dayId, progress.completed ? "starts_tomorrow" : "sequence_complete");
  }
  return {
    status: "ready",
    lockedReason: null,
    dayId,
    setVersion: 1,
    total: progress.total,
    answeredCount: progress.answeredCount,
    completed: progress.completed,
    nextIndex: progress.nextIndex,
    items: feedItems(snapshot, set.contentIds),
    answers: dailyAnswers(snapshot),
  };
}

// ---------------------------------------------------------------------------
// Responses
// ---------------------------------------------------------------------------

export type HumorCoreRejection = "day-closed" | "not-in-set";

export class HumorCoreRejected extends Error {
  constructor(readonly reason: HumorCoreRejection) {
    super(reason);
  }
}

/**
 * Downstream readers (`isHumorCalibrationReady`: match compatibility, Picks,
 * personalization, the learning journey) decide readiness from the
 * calibration document. It normally reaches fifteen on its own, one counted
 * rating at a time; when the Core calibration finishes on fewer ratings (a
 * retired or waived entry) or was finished before Core existed, it is
 * completed here so those readers never see a finished member as unready.
 */
function completeCalibrationDoc(tx: Transaction, ref: DocumentReference): void {
  const now = FieldValue.serverTimestamp();
  tx.set(
    ref,
    {
      version: HUMOR_CALIBRATION_VERSION,
      completedCount: CALIBRATION_TOTAL,
      stage: "complete",
      complete: true,
      completedAt: now,
      completedBy: "core",
      updatedAt: now,
    },
    {merge: true},
  );
}

function writeCoreOutcome(input: {
  tx: Transaction;
  db: Firestore;
  uid: string;
  applied: Extract<HumorCoreApplyResult, {ok: true}>;
  set: HumorCoreSet;
  sequence: readonly HumorCoreEntry[];
  unavailable: ReadonlySet<string>;
  calibrationComplete: boolean;
}): void {
  const {tx, db, uid, applied, set, sequence} = input;
  tx.set(db.doc(userHumorCorePath(uid)), coreStatePayload(applied.state, sequence));
  if (
    !input.calibrationComplete &&
    hasFinishedCoreOnboarding(applied.state, sequence, input.unavailable)
  ) {
    completeCalibrationDoc(tx, db.doc(HUMOR_CALIBRATION_DOC(uid)));
  }
  if (applied.completedTodayNow) {
    const progress = coreSetProgress(applied.state, set);
    const now = FieldValue.serverTimestamp();
    tx.set(
      db.doc(userHumorDailyPath(uid, set.dayId)),
      {
        dayId: set.dayId,
        schema: HUMOR_CORE_DAY_SCHEMA,
        kind: set.kind,
        setId: applied.state.today.setId,
        contentIds: set.contentIds,
        total: progress.total,
        answeredCount: progress.answeredCount,
        ratedCount: progress.statuses.filter((status) => status === "rated").length,
        completed: true,
        completedAt: now,
        updatedAt: now,
      },
      {merge: true},
    );
  }
}

export type HumorCoreResponseInput = {
  db: Firestore;
  uid: string;
  nowMs: number;
  contentId: string;
  /** Null only together with `mediaFailed`. */
  rating: HumorRating | null;
  /** The media would not play. Never evidence. */
  mediaFailed: boolean;
  /** The day the client believes it is answering; checked when sent. */
  expectedDayId?: string;
  dwellMs?: number;
  replayCount?: number;
  saved?: boolean;
  gestureHints?: HumorGestureHints | null;
  sequence?: readonly HumorCoreEntry[];
};

export type HumorCoreResponseResult = {
  dayId: string;
  kind: HumorCoreSet["kind"];
  progress: HumorCoreSetProgress;
  /** The response changed nothing: same rating again, or media skip on a resolved entry. */
  alreadyAnswered: boolean;
  completedTodayNow: boolean;
  onboardingCompletedNow: boolean;
  calibration: CalibrationStateView;
  profile: {interactionCount: number; confidence: number};
};

/**
 * One response to a Core entry: a rating, or a media failure.
 *
 * Refused unless the entry is in the set the server computes for the member's
 * today (`not-in-set`), and unless the day the client names — when it names
 * one — is the server's day (`day-closed`). So tomorrow's entries, an
 * arbitrary content id and a stale day are all rejected before anything is
 * learned. Idempotent: the same rating again changes nothing; a different
 * rating for an entry of today's set replaces the earlier contribution.
 */
export async function submitHumorCoreResponse(
  input: HumorCoreResponseInput,
): Promise<HumorCoreResponseResult> {
  const {db, uid, nowMs, contentId} = input;
  const sequence = input.sequence ?? HUMOR_CORE_SEQUENCE;
  const mediaFailed = input.mediaFailed === true;
  if (!mediaFailed && !isValidHumorRating(input.rating)) {
    throw new Error("invalid-rating");
  }
  const dayId = await resolveDailyToday(db, nowMs);
  if (input.expectedDayId !== undefined && input.expectedDayId !== dayId) {
    throw new HumorCoreRejected("day-closed");
  }
  if (humorCorePosition(contentId, sequence) === null) {
    throw new HumorCoreRejected("not-in-set");
  }
  const initial = await ensureHumorCoreState({db, uid, todayId: dayId, nowMs, sequence});
  const resolved = await resolveMemberSet(db, initial, dayId, sequence);
  if (!resolved.set.contentIds.includes(contentId)) {
    throw new HumorCoreRejected("not-in-set");
  }

  // Throws `content-unavailable` exactly as the feedback path always has.
  const prepared = await prepareHumorFeedback({
    db,
    uid,
    contentId,
    rating: mediaFailed ? null : input.rating,
    skipped: mediaFailed,
    skipReason: mediaFailed ? "media_failed" : undefined,
    dwellMs: input.dwellMs,
    replayCount: input.replayCount,
    saved: input.saved,
    gestureHints: input.gestureHints,
  });
  const coreRef = db.doc(userHumorCorePath(uid));

  const outcome = await db.runTransaction(async (tx) => {
    const [coreSnap, reads] = await Promise.all([
      tx.get(coreRef),
      readHumorFeedbackState(tx, prepared),
    ]);
    const state = parseHumorCoreState(coreSnap.data(), sequence);
    const set = memberCoreSet(state, dayId, sequence, resolved.unavailable);
    const common = {state, set, id: contentId, nowMs, sequence, unavailable: resolved.unavailable};
    const applied = mediaFailed
      ? applyCoreMediaFailure(common)
      : applyCoreRating({...common, rating: input.rating as HumorRating});
    if (!applied.ok) {
      throw new HumorCoreRejected(applied.reason);
    }
    if (!applied.changed) {
      return {applied, set, feedback: null};
    }
    const feedback = applyHumorFeedbackInTx(tx, prepared, reads);
    writeCoreOutcome({
      tx,
      db,
      uid,
      applied,
      set,
      sequence,
      unavailable: resolved.unavailable,
      calibrationComplete: feedback.calibration.complete,
    });
    return {applied, set, feedback};
  });

  let feedbackResult: HumorFeedbackResult | null = null;
  if (outcome.feedback) {
    feedbackResult = await finishHumorFeedback(db, prepared, outcome.feedback);
  }
  const profile = feedbackResult
    ? {interactionCount: feedbackResult.interactionCount, confidence: feedbackResult.confidence}
    : await loadUserHumorProfile(db, uid).then((p) => ({
        interactionCount: p.interactionCount,
        confidence: p.confidence,
      }));
  const state = outcome.applied.state;
  return {
    dayId,
    kind: outcome.set.kind,
    progress: coreSetProgress(state, outcome.set),
    alreadyAnswered: !outcome.applied.changed,
    completedTodayNow: outcome.applied.completedTodayNow,
    onboardingCompletedNow: outcome.applied.onboardingCompletedNow,
    calibration: coreCalibrationView(
      coreOnboardingProgress(state, sequence, resolved.unavailable),
    ),
    profile,
  };
}

/** The `submitHumorFeedback` response shape, from a Core response. */
export function toHumorFeedbackResult(
  result: Pick<HumorCoreResponseResult, "calibration" | "profile">,
): HumorFeedbackResult {
  return {
    ok: true,
    profileBuilding: result.calibration.complete
      ? false
      : result.calibration.completedCount > 0 ||
        isProfileBuilding(result.profile.interactionCount),
    interactionCount: result.profile.interactionCount,
    confidence: result.profile.confidence,
    calibration: result.calibration,
  };
}

/**
 * After a member reported [contentId]: waive it for them if it is one of
 * today's Core entries, so the report never leaves a hole they are stuck on.
 * A no-op for anything else.
 */
export async function waiveReportedHumorCoreItem(input: {
  db: Firestore;
  uid: string;
  nowMs: number;
  contentId: string;
  sequence?: readonly HumorCoreEntry[];
}): Promise<void> {
  const {db, uid, nowMs, contentId} = input;
  const sequence = input.sequence ?? HUMOR_CORE_SEQUENCE;
  if (humorCorePosition(contentId, sequence) === null) {
    return;
  }
  const dayId = await resolveDailyToday(db, nowMs);
  const initial = await ensureHumorCoreState({db, uid, todayId: dayId, nowMs, sequence});
  const resolved = await resolveMemberSet(db, initial, dayId, sequence);
  if (!resolved.set.contentIds.includes(contentId)) {
    return;
  }
  const coreRef = db.doc(userHumorCorePath(uid));
  const calibrationRef = db.doc(HUMOR_CALIBRATION_DOC(uid));
  await db.runTransaction(async (tx) => {
    const [coreSnap, calibrationSnap] = await Promise.all([
      tx.get(coreRef),
      tx.get(calibrationRef),
    ]);
    const state = parseHumorCoreState(coreSnap.data(), sequence);
    const set = memberCoreSet(state, dayId, sequence, resolved.unavailable);
    const applied = applyCoreReport({
      state,
      set,
      id: contentId,
      nowMs,
      sequence,
      unavailable: resolved.unavailable,
    });
    if (!applied.ok || !applied.changed) {
      return;
    }
    writeCoreOutcome({
      tx,
      db,
      uid,
      applied,
      set,
      sequence,
      unavailable: resolved.unavailable,
      calibrationComplete: parseCalibrationState(calibrationSnap.data()).complete,
    });
  });
}

// ---------------------------------------------------------------------------
// Sequence report (admin console, seed tool)
// ---------------------------------------------------------------------------

export type HumorCoreSequenceReportItem = {
  position: number;
  contentId: string;
  /** In the first `onboardingCount` positions. */
  onboarding: boolean;
  /** Active in the sequence (not retired). */
  active: boolean;
  retiredReason: string | null;
  supersedes: string | null;
  /** The content document exists. */
  exists: boolean;
  contentActive: boolean;
  safetyStatus: string | null;
  /** Would be handed out to a member right now. */
  servable: boolean;
  type: string | null;
  category: string | null;
  /** The heaviest vector dimensions, e.g. `absurd 0.9`. */
  topDimensions: string[];
  provider: string | null;
  sourceTrust: string | null;
  thumbUrl: string | null;
  ratingCount: number;
};

export type HumorCoreSequenceReport = {
  released: boolean;
  onboardingCount: number;
  dailyCount: number;
  total: number;
  servableCount: number;
  /** The sequence is well-formed and every active entry can be handed out. */
  healthy: boolean;
  /** Malformed sequence entries (see `humorCoreSequenceProblems`). */
  problems: string[];
  /** Active entries a member cannot be given right now, and why. */
  warnings: string[];
  items: HumorCoreSequenceReportItem[];
};

function topDimensions(content: HumorContentDoc): string[] {
  return Object.entries(normalizeHumorVector(content.humorVector, 0))
    .filter(([, weight]) => weight > 0)
    .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))
    .slice(0, 3)
    .map(([dim, weight]) => `${dim} ${Math.round(weight * 100) / 100}`);
}

/** Every position of the sequence with the state of its content document. */
export async function buildHumorCoreSequenceReport(
  db: Firestore,
  sequence: readonly HumorCoreEntry[] = HUMOR_CORE_SEQUENCE,
): Promise<HumorCoreSequenceReport> {
  const contents = await loadContents(
    db,
    sequence.map((entry) => entry.id),
  );
  const items = sequence.map((entry, index): HumorCoreSequenceReportItem => {
    const content = contents.get(entry.id) ?? null;
    return {
      position: index + 1,
      contentId: entry.id,
      onboarding: index < HUMOR_CORE.onboardingCount,
      active: entry.active,
      retiredReason: entry.retiredReason ?? null,
      supersedes: entry.supersedes ?? null,
      exists: content !== null,
      contentActive: content?.active === true,
      safetyStatus: content?.safetyStatus ?? null,
      servable: entry.active && coreServable(content),
      type: content?.type ?? null,
      category: content?.category ?? null,
      topDimensions: content ? topDimensions(content) : [],
      provider: content?.source?.provider ?? null,
      sourceTrust: content?.sourceTrust ?? null,
      thumbUrl: content?.media?.thumbUrl ?? null,
      ratingCount: content?.stats?.ratingCount ?? 0,
    };
  });
  const problems = sequence === HUMOR_CORE_SEQUENCE ? humorCoreSequenceProblems() : [];
  const warnings = items
    .filter((item) => item.active && !item.servable)
    .map((item) => {
      const why = !item.exists
        ? "content document missing"
        : !item.contentActive
          ? "content inactive"
          : item.safetyStatus !== "approved"
            ? `content ${item.safetyStatus}`
            : "content is not curated";
      return `V${item.position} ${item.contentId}: ${why}`;
    });
  return {
    released: HUMOR_CORE_RELEASE.released,
    onboardingCount: HUMOR_CORE.onboardingCount,
    dailyCount: HUMOR_CORE.dailyCount,
    total: sequence.length,
    servableCount: items.filter((item) => item.servable).length,
    healthy: problems.length === 0 && warnings.length === 0,
    problems,
    warnings,
    items,
  };
}
