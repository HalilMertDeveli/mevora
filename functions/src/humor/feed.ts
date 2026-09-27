import type {Firestore} from "firebase-admin/firestore";
import {
  parseCalibrationState,
  toCalibrationView,
  type CalibrationStateView,
} from "./calibration.js";
import {selectCalibrationItems, type CalibrationSelection} from "./calibrationFeed.js";
import {
  HUMOR_CONTENT_COLLECTION,
  listHumorContentPage,
  parseHumorContent,
  toFeedSafeContent,
  type HumorScanPosition,
} from "./contentRepository.js";
import {canServeHumorContent} from "./moderation.js";
import {defaultUserHumorProfile} from "./profile.js";
import {rankHumorFeed} from "./ranking.js";
import {
  HUMOR_FEED_PAGE_SIZE,
  HUMOR_PROFILE_BUILDING_THRESHOLD,
  type HumorContentDoc,
  type HumorFeedItem,
  type UserHumorCalibrationDoc,
  type UserHumorProfileDoc,
} from "./types.js";

export const HUMOR_CALIBRATION_DOC = (uid: string): string =>
  `users/${uid}/humor/calibration`;

const HUMOR_SUMMARY_DOC = (uid: string): string => `users/${uid}/humor/summary`;

export async function loadUserHumorCalibration(
  db: Firestore,
  uid: string,
): Promise<UserHumorCalibrationDoc> {
  const snap = await db.doc(HUMOR_CALIBRATION_DOC(uid)).get();
  return parseCalibrationState(snap.data() as Record<string, unknown> | undefined);
}

function parseUserHumorProfile(
  data: Record<string, unknown> | undefined,
): UserHumorProfileDoc {
  const base = defaultUserHumorProfile();
  if (!data) {
    return base;
  }
  return {
    ...base,
    vector: {...base.vector, ...((data.vector as UserHumorProfileDoc["vector"]) ?? {})},
    confidence: Number(data.confidence ?? 0),
    interactionCount: Number(data.interactionCount ?? 0),
    exploredCategories: Array.isArray(data.exploredCategories)
      ? data.exploredCategories.map((c: unknown) => String(c))
      : [],
    lastUpdatedAt: data.lastUpdatedAt as UserHumorProfileDoc["lastUpdatedAt"],
    version: Number(data.version ?? base.version),
  };
}

export async function loadUserHumorProfile(
  db: Firestore,
  uid: string,
): Promise<UserHumorProfileDoc> {
  const snap = await db.doc(HUMOR_SUMMARY_DOC(uid)).get();
  return parseUserHumorProfile(snap.exists ? snap.data() : undefined);
}

/**
 * How far the feed may walk the catalog in one request.
 *
 * Bounds the work per call to at most MAX_SCAN_PAGES × SCAN_PAGE_SIZE catalog
 * reads, plus one interaction lookup per servable document looked at. The walk
 * stops as soon as it has enough unseen items to fill the page.
 */
const SCAN_PAGE_SIZE = 60;
const MAX_SCAN_PAGES = 4;

/**
 * Seen checks run in chunks so a page that fills early does not pay for a
 * lookup of every document the scan happened to fetch.
 */
const MIN_SEEN_CHECK_CHUNK = 20;

/** Served-but-unrated ids remembered for the next cold start (≈ two pages). */
const MAX_PENDING = 30;

/**
 * How long a completed walk ("caught up") is trusted before the catalog is
 * walked again from the top. New content always lands above the floor and is
 * picked up immediately; the re-walk exists for content whose servability
 * changed later (moderation approval, re-activation) under an old `createdAt`.
 */
const FLOOR_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * Calibration picks are verified against the interaction docs and re-selected
 * when one was already seen. Each round is one pool read plus one getAll of at
 * most a page of refs.
 */
const CALIBRATION_SELECT_ROUNDS = 4;

const MAX_CURSOR_LENGTH = 512;
const MAX_LANGUAGES = 5;
const MAX_LANGUAGE_LENGTH = 8;
const CURSOR_CONTENT_ID = /^[A-Za-z0-9_-]{1,128}$/;
/** Firestore Timestamp range: 0001-01-01T00:00:00Z .. 9999-12-31T23:59:59Z. */
const TIMESTAMP_MIN_SECONDS = -62_135_596_800;
const TIMESTAMP_MAX_SECONDS = 253_402_300_799;

type IdCheck = (id: string) => boolean;

/** Strict: ids a client may name in a cursor. */
const isCursorContentId: IdCheck = (id) => CURSOR_CONTENT_ID.test(id);

/** Loose: any id Firestore itself could have produced, as stored server-side. */
const isStoredContentId: IdCheck = (id) =>
  id.length > 0 && id.length <= 1500 && !id.includes("/") && id !== "." && id !== "..";

function makePosition(
  seconds: unknown,
  nanos: unknown,
  contentId: unknown,
  idOk: IdCheck,
): HumorScanPosition | null {
  if (
    typeof seconds !== "number" ||
    !Number.isInteger(seconds) ||
    seconds < TIMESTAMP_MIN_SECONDS ||
    seconds > TIMESTAMP_MAX_SECONDS
  ) {
    return null;
  }
  if (typeof nanos !== "number" || !Number.isInteger(nanos) || nanos < 0 || nanos > 999_999_999) {
    return null;
  }
  if (typeof contentId !== "string" || !idOk(contentId)) {
    return null;
  }
  return {seconds, nanos, contentId};
}

/**
 * Positions used to be epoch millis. The real timestamp lies somewhere inside
 * that millisecond, so a legacy position is rounded *up* to its last
 * nanosecond: resuming may re-offer a document sharing that millisecond (the
 * seen check drops it once rated), but it can never skip one.
 */
function positionFromLegacyMillis(
  ms: unknown,
  contentId: unknown,
  idOk: IdCheck,
): HumorScanPosition | null {
  if (typeof ms !== "number" || !Number.isInteger(ms)) {
    return null;
  }
  const seconds = Math.floor(ms / 1000);
  return makePosition(seconds, (ms - seconds * 1000) * 1_000_000 + 999_999, contentId, idOk);
}

function parsePosition(raw: unknown, idOk: IdCheck): HumorScanPosition | null {
  if (!raw || typeof raw !== "object") {
    return null;
  }
  const value = raw as Record<string, unknown>;
  if ("createdAtMs" in value) {
    return positionFromLegacyMillis(value.createdAtMs, value.contentId, idOk);
  }
  return makePosition(value.s, value.n, value.id, idOk);
}

type WirePosition = {s: number; n: number; id: string};

function toWire(position: HumorScanPosition): WirePosition {
  return {s: position.seconds, n: position.nanos, id: position.contentId};
}

function samePosition(a: HumorScanPosition | null, b: HumorScanPosition | null): boolean {
  if (a === null || b === null) {
    return a === b;
  }
  return a.seconds === b.seconds && a.nanos === b.nanos && a.contentId === b.contentId;
}

/**
 * Negative when `a` comes first in the walk (createdAt desc, then id desc).
 * `null` is the top of the catalog.
 */
function compareWalkOrder(a: HumorScanPosition | null, b: HumorScanPosition | null): number {
  if (a === null || b === null) {
    return a === b ? 0 : a === null ? -1 : 1;
  }
  if (a.seconds !== b.seconds) {
    return b.seconds - a.seconds;
  }
  if (a.nanos !== b.nanos) {
    return b.nanos - a.nanos;
  }
  if (a.contentId === b.contentId) {
    return 0;
  }
  return a.contentId > b.contentId ? -1 : 1;
}

/**
 * The cursor carries a catalog *position*: where to continue, or `top`.
 *
 * Anything malformed — including a well-formed position outside the Timestamp
 * range or an id that is not a plain document id — decodes to "no cursor", so
 * the call falls back to the server-held position instead of failing.
 */
type FeedCursor = {after: HumorScanPosition | null};

function decodeCursor(cursor: string | null | undefined): FeedCursor | null {
  if (!cursor || cursor.length > MAX_CURSOR_LENGTH) {
    return null;
  }
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as unknown;
    if (parsed && typeof parsed === "object" && (parsed as {top?: unknown}).top === true) {
      return {after: null};
    }
    const after = parsePosition(parsed, isCursorContentId);
    return after ? {after} : null;
  } catch {
    return null;
  }
}

function encodeCursor(after: HumorScanPosition | null): string {
  const body = after === null ? {top: true} : toWire(after);
  return Buffer.from(JSON.stringify(body), "utf8").toString("base64url");
}

/**
 * This user's catalog walk, persisted server-side on the humor summary (so it
 * inherits the owner-read / client-write-denied rule and the account-deletion
 * sweep).
 *
 *  * `at`      — where the walk stands; a cold client (no cursor) resumes here.
 *  * `pending` — ids served recently. A cold start re-offers the ones still
 *                unrated, so a prefetched page, a page the user left early, or
 *                the page fetched just as calibration completed is not skipped
 *                until the walk comes all the way round again.
 *  * `run`     — a clean sweep in progress: it began at the top of the catalog
 *                (whose first document was `top`) and found nothing unseen down
 *                to `at`. Only a sweep that reaches the end this way proves the
 *                user has seen everything.
 *  * `floor`   — that proof: every servable item at or below `top` had been
 *                seen as of `at` (epoch ms). While fresh, the walk only looks
 *                above it, so a caught-up user stays caught up call after call
 *                for the cost of one empty query.
 *
 * All of it is keyed by the language set, since both proofs are per language.
 */
const FEED_POSITION_FIELD = "feedPosition";

type FeedWalkState = {
  lang: string;
  at: HumorScanPosition | null;
  run: {top: HumorScanPosition} | null;
  floor: {top: HumorScanPosition; at: number} | null;
  pending: string[];
};

function emptyWalkState(lang: string, pending: string[] = []): FeedWalkState {
  return {lang, at: null, run: null, floor: null, pending};
}

function parseWalkState(raw: unknown, lang: string): FeedWalkState {
  if (!raw || typeof raw !== "object") {
    return emptyWalkState(lang);
  }
  const value = raw as Record<string, unknown>;
  if (value.v !== 2) {
    // Legacy: a bare millisecond position, written before language keying.
    return {...emptyWalkState(lang), at: parsePosition(value, isStoredContentId)};
  }
  const pending = Array.isArray(value.pending)
    ? value.pending
        .filter((id): id is string => typeof id === "string" && isStoredContentId(id))
        .slice(-MAX_PENDING)
    : [];
  if (value.lang !== lang) {
    return emptyWalkState(lang, pending);
  }
  const runTop =
    value.run && typeof value.run === "object"
      ? parsePosition((value.run as {top?: unknown}).top, isStoredContentId)
      : null;
  const floorRaw =
    value.floor && typeof value.floor === "object"
      ? (value.floor as {top?: unknown; at?: unknown})
      : null;
  const floorTop = floorRaw ? parsePosition(floorRaw.top, isStoredContentId) : null;
  const floorAt =
    floorRaw && typeof floorRaw.at === "number" && Number.isFinite(floorRaw.at)
      ? floorRaw.at
      : null;
  return {
    lang,
    at: parsePosition(value.at, isStoredContentId),
    run: runTop ? {top: runTop} : null,
    floor: floorTop && floorAt !== null ? {top: floorTop, at: floorAt} : null,
    pending,
  };
}

function serializeWalkState(state: FeedWalkState): Record<string, unknown> {
  return {
    v: 2,
    lang: state.lang,
    at: state.at ? toWire(state.at) : null,
    run: state.run ? {top: toWire(state.run.top)} : null,
    floor: state.floor ? {top: toWire(state.floor.top), at: state.floor.at} : null,
    pending: state.pending,
  };
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

/** Writes only when the walk actually moved; replaces the field wholesale. */
async function saveWalkState(
  db: Firestore,
  uid: string,
  previousRaw: unknown,
  state: FeedWalkState,
): Promise<void> {
  const next = serializeWalkState(state);
  if (stableStringify(previousRaw ?? null) === stableStringify(next)) {
    return;
  }
  await db
    .doc(HUMOR_SUMMARY_DOC(uid))
    .set({[FEED_POSITION_FIELD]: next}, {mergeFields: [FEED_POSITION_FIELD]})
    .catch(() => undefined);
}

/**
 * Caps the client-supplied language list (≤ 5 entries of ≤ 8 characters) and
 * falls back to Turkish + English when nothing usable is left.
 */
export function normalizeFeedLanguages(languages: readonly unknown[] | undefined): string[] {
  const cleaned = (languages ?? [])
    .slice(0, MAX_LANGUAGES)
    .map((l) => String(l).trim().toLowerCase())
    .filter((l) => l.length > 0 && l.length <= MAX_LANGUAGE_LENGTH);
  return cleaned.length > 0 ? [...new Set(cleaned)] : ["tr", "en"];
}

/**
 * Content ids among `ids` that already have an interaction doc.
 *
 * Any interaction doc counts — a rating, a skip marker or a report marker — so
 * this is the single definition of "seen" for both the walk and calibration.
 * Exact, and bounded by the number of ids asked about rather than by the
 * user's history.
 */
async function findSeenContentIds(
  db: Firestore,
  uid: string,
  ids: readonly string[],
): Promise<Set<string>> {
  if (ids.length === 0) {
    return new Set();
  }
  const snaps = await db.getAll(
    ...ids.map((id) => db.doc(`users/${uid}/humorInteractions/${id}`)),
  );
  const seen = new Set<string>();
  snaps.forEach((snap, index) => {
    if (snap.exists) {
      seen.add(ids[index]);
    }
  });
  return seen;
}

function isServable(content: HumorContentDoc): boolean {
  return canServeHumorContent({active: content.active, safetyStatus: content.safetyStatus});
}

/** Re-offer recently served items the user never rated, oldest first. */
async function carryOverPending(input: {
  db: Firestore;
  uid: string;
  pending: readonly string[];
  languages: readonly string[];
  limit: number;
}): Promise<{items: HumorContentDoc[]; stillPending: string[]}> {
  if (input.pending.length === 0) {
    return {items: [], stillPending: []};
  }
  const seen = await findSeenContentIds(input.db, input.uid, input.pending);
  const unrated = input.pending.filter((id) => !seen.has(id));
  const toLoad = unrated.slice(0, input.limit);
  const snaps =
    toLoad.length > 0
      ? await input.db.getAll(
          ...toLoad.map((id) => input.db.collection(HUMOR_CONTENT_COLLECTION).doc(id)),
        )
      : [];
  const items: HumorContentDoc[] = [];
  const dropped = new Set<string>();
  snaps.forEach((snap, index) => {
    const content = snap.exists ? parseHumorContent(snap.id, snap.data()) : null;
    if (content && isServable(content) && input.languages.includes(content.language)) {
      items.push(content);
    } else {
      dropped.add(toLoad[index]);
    }
  });
  return {items, stillPending: unrated.filter((id) => !dropped.has(id))};
}

type WalkResult = {
  items: HumorContentDoc[];
  nextCursor: string | null;
  catalogExhausted: boolean;
  catalogEmpty: boolean;
  state: FeedWalkState;
};

/**
 * Walk the catalog newest-first from the cursor (or the stored position),
 * taking unseen items in catalog order until the page is full.
 *
 *  * Seen items are dropped *before* ranking, so they never eat page slots.
 *  * The walk stops after the last item actually taken, never after the last
 *    item scanned, so nothing scanned-but-not-served is skipped.
 *  * A cold start that reaches the end wraps to the top once, so a user left
 *    near the bottom still gets a full page. A cursor walk never wraps: it is
 *    one pass, ending with a null cursor, so a client paging ahead is never
 *    handed items it already holds; its next cold start begins the next pass.
 *  * `catalogExhausted` is reported only when a clean sweep from the top has
 *    reached the end, never from a partial walk.
 */
async function walkCatalog(input: {
  db: Firestore;
  uid: string;
  languages: string[];
  limit: number;
  cursor: FeedCursor | null;
  state: FeedWalkState;
  now: number;
}): Promise<WalkResult> {
  const {db, uid, languages, limit, cursor, state, now} = input;
  const floorFresh = state.floor !== null && now - state.floor.at < FLOOR_TTL_MS;
  const floorStale = state.floor !== null && !floorFresh;
  const bound = floorFresh ? state.floor!.top : null;

  const taken: HumorContentDoc[] = [];
  const takenIds = new Set<string>();
  const take = (content: HumorContentDoc): void => {
    taken.push(content);
    takenIds.add(content.contentId);
  };

  let stillPending = state.pending;
  if (cursor === null) {
    const carried = await carryOverPending({
      db,
      uid,
      pending: state.pending,
      languages,
      limit,
    });
    carried.items.forEach(take);
    stillPending = carried.stillPending;
  }

  let start: HumorScanPosition | null = cursor ? cursor.after : state.at;
  if (start !== null && bound !== null && compareWalkOrder(start, bound) >= 0) {
    // At or below the verified floor nothing is due; the walk restarts on top.
    start = null;
  }

  let runActive =
    start === null ||
    (state.run !== null && state.at !== null && samePosition(start, state.at));
  let runTop: HumorScanPosition | null | undefined =
    start === null ? undefined : state.run?.top;

  let scanFrom = start;
  let scanRan = false;
  let wrapped = false;
  let hitEnd = false;
  let sawEntry = false;
  let lastTaken: HumorScanPosition | null = null;

  for (let pageIndex = 0; pageIndex < MAX_SCAN_PAGES && taken.length < limit; pageIndex += 1) {
    const page = await listHumorContentPage(db, {
      languages,
      pageSize: SCAN_PAGE_SIZE,
      after: scanFrom,
      before: bound,
    });
    scanRan = true;
    if (runActive && runTop === undefined) {
      runTop = page.firstScanned;
    }
    sawEntry = sawEntry || page.entries.length > 0;
    if (page.entries.some((entry) => takenIds.has(entry.content.contentId))) {
      // Passing an item this call already re-offered: it is unseen, so this
      // stretch is not clean.
      runActive = false;
    }

    const candidates = page.entries.filter(
      (entry) => !takenIds.has(entry.content.contentId) && isServable(entry.content),
    );
    for (let offset = 0; offset < candidates.length && taken.length < limit; ) {
      const chunk = candidates.slice(
        offset,
        offset + Math.max(limit - taken.length, MIN_SEEN_CHECK_CHUNK),
      );
      offset += chunk.length;
      const seen = await findSeenContentIds(
        db,
        uid,
        chunk.map((entry) => entry.content.contentId),
      );
      for (const entry of chunk) {
        if (taken.length >= limit) {
          break;
        }
        if (seen.has(entry.content.contentId)) {
          continue;
        }
        take(entry.content);
        lastTaken = entry.position;
        runActive = false;
      }
    }
    if (taken.length >= limit) {
      break;
    }

    if (page.exhausted) {
      // A clean sweep reaching the end is the exhaustion proof, so it never
      // wraps; neither does a cursor walk, which ends after exactly one pass.
      if (!wrapped && start !== null && cursor === null && !runActive) {
        wrapped = true;
        scanFrom = null;
        runActive = true;
        runTop = undefined;
        continue;
      }
      hitEnd = true;
      break;
    }
    scanFrom = page.scannedTo;
  }

  const pageFull = taken.length >= limit;
  // Where the walk now stands:
  //  * page full → just after the last item the scan took (or unmoved when
  //    the carried-over items alone filled it);
  //  * end reached → the walk is complete, the next one starts on top;
  //  * scan budget spent → where scanning stopped (the top, right after a wrap).
  const ended = !pageFull && hitEnd;
  const nextAt: HumorScanPosition | null = pageFull
    ? (lastTaken ?? start)
    : ended
      ? null
      : scanFrom;

  const catalogEmpty =
    ended &&
    taken.length === 0 &&
    bound === null &&
    !sawEntry &&
    (start === null || wrapped);
  const exhaustedNow = ended && runActive && taken.length === 0 && !catalogEmpty;

  let nextState: FeedWalkState;
  if (exhaustedNow) {
    const floorTop = runTop ?? state.floor?.top ?? null;
    nextState = {
      ...emptyWalkState(state.lang),
      // A sweep bounded by a fresh floor only re-proved the part above it, so
      // the proof keeps the older verification time.
      floor: floorTop ? {top: floorTop, at: floorFresh ? state.floor!.at : now} : null,
    };
  } else {
    let run: FeedWalkState["run"] = null;
    if (!scanRan) {
      run = samePosition(start, state.at) ? state.run : null;
    } else if (runActive && !ended && runTop) {
      run = {top: runTop};
    }
    nextState = {
      lang: state.lang,
      at: nextAt,
      run,
      // A stale floor stays while its re-walk finds nothing, so the user keeps
      // seeing "caught up"; anything unseen turning up retires it.
      floor:
        floorFresh || (floorStale && taken.length === 0 && !catalogEmpty)
          ? state.floor
          : null,
      pending: [
        ...stillPending.filter((id) => !takenIds.has(id)),
        ...taken.map((content) => content.contentId),
      ].slice(-MAX_PENDING),
    };
  }

  const stillCaughtUp = floorStale && !exhaustedNow && taken.length === 0 && !catalogEmpty;
  return {
    items: taken,
    nextCursor: ended || stillCaughtUp ? null : encodeCursor(nextAt),
    catalogExhausted: exhaustedNow || stillCaughtUp,
    catalogEmpty,
    state: nextState,
  };
}

/**
 * Calibration picks, verified exactly against the interaction docs.
 *
 * The selector only knows the calibration's own rated ids. Content the user
 * rated outside calibration, skipped or reported is invisible to it, and it is
 * deterministic — so an already-seen pick would come back on every call and
 * calibration could never advance past it. Each round checks only the picks
 * not yet verified and re-selects with the seen ones excluded; whatever is
 * still unverified after the last round is dropped rather than served.
 */
async function selectUnseenCalibrationItems(input: {
  db: Firestore;
  uid: string;
  state: UserHumorCalibrationDoc;
  profile: UserHumorProfileDoc;
  languages: string[];
  limit: number;
}): Promise<CalibrationSelection & {droppedSeen: number}> {
  const exclude = new Set<string>();
  const verified = new Set<string>();
  let selection: CalibrationSelection = {picks: [], unfilled: 0, deficiencies: []};
  for (let round = 0; round < CALIBRATION_SELECT_ROUNDS; round += 1) {
    selection = await selectCalibrationItems({
      ...input,
      excludeContentIds: new Set(exclude),
    });
    const unchecked = selection.picks
      .map((pick) => pick.content.contentId)
      .filter((id) => !verified.has(id) && !exclude.has(id));
    if (unchecked.length === 0) {
      break;
    }
    const seen = await findSeenContentIds(input.db, input.uid, unchecked);
    for (const id of unchecked) {
      if (seen.has(id)) {
        exclude.add(id);
      } else {
        verified.add(id);
      }
    }
    if (seen.size === 0) {
      break;
    }
  }
  const picks = selection.picks.filter((pick) => verified.has(pick.content.contentId));
  return {...selection, picks, droppedSeen: selection.picks.length - picks.length};
}

export async function buildHumorFeed(input: {
  db: Firestore;
  uid: string;
  languages?: string[];
  limit?: number;
  cursor?: string | null;
  /** Clock override for tests; defaults to `Date.now()`. */
  now?: number;
}): Promise<{
  items: HumorFeedItem[];
  nextCursor: string | null;
  /** The user has worked through every servable item currently in the catalog. */
  catalogExhausted: boolean;
  /** No servable content exists at all — an operational problem, not progress. */
  catalogEmpty: boolean;
  profileBuilding: boolean;
  interactionCount: number;
  calibration: CalibrationStateView & {insufficientPool: boolean};
}> {
  const limit = Math.min(15, Math.max(10, input.limit ?? HUMOR_FEED_PAGE_SIZE));
  const languages = normalizeFeedLanguages(input.languages);

  // The summary is read once: it carries both the profile and the walk state.
  const [summarySnap, calibrationState] = await Promise.all([
    input.db.doc(HUMOR_SUMMARY_DOC(input.uid)).get(),
    loadUserHumorCalibration(input.db, input.uid),
  ]);
  const summary = summarySnap.exists ? summarySnap.data() : undefined;
  const profile = parseUserHumorProfile(summary);

  // Initial calibration owns the page while it is running. It uses its own
  // curated selector rather than the personalized ranker, so the structured
  // 6/6/3 contract cannot be diluted by ranking heuristics.
  const calibrationPicks = calibrationState.complete
    ? {picks: [], unfilled: 0, deficiencies: [] as string[], droppedSeen: 0}
    : await selectUnseenCalibrationItems({
        db: input.db,
        uid: input.uid,
        state: calibrationState,
        profile,
        languages,
        limit,
      });

  const calibrationView = {
    ...toCalibrationView(calibrationState),
    insufficientPool:
      calibrationPicks.deficiencies.length > 0 ||
      (calibrationPicks.picks.length === 0 && calibrationPicks.droppedSeen > 0),
  };

  if (!calibrationState.complete && calibrationPicks.picks.length > 0) {
    const items = calibrationPicks.picks.map((pick) =>
      toFeedSafeContent(pick.content, pick.stage),
    );
    return {
      items,
      // Calibration pages are recomputed from server state on every call, so
      // there is nothing for a cursor to carry.
      nextCursor: null,
      catalogExhausted: false,
      catalogEmpty: false,
      profileBuilding: true,
      interactionCount: profile.interactionCount,
      calibration: calibrationView,
    };
  }

  const langKey = [...languages].sort().join(",");
  const storedRaw = summary?.[FEED_POSITION_FIELD];
  const walk = await walkCatalog({
    db: input.db,
    uid: input.uid,
    languages,
    limit,
    // An explicit cursor wins; otherwise resume where this user left off.
    cursor: decodeCursor(input.cursor),
    state: parseWalkState(storedRaw, langKey),
    now: input.now ?? Date.now(),
  });
  await saveWalkState(input.db, input.uid, storedRaw, walk.state);

  // Ranking reorders what is already due; it no longer selects.
  const page = rankHumorFeed({
    profile,
    items: walk.items.map((content) => ({content, seen: false})),
    userLanguages: languages,
    limit,
  });

  return {
    items: page.map((c) => toFeedSafeContent(c, null)),
    nextCursor: walk.nextCursor,
    catalogExhausted: walk.catalogExhausted,
    catalogEmpty: walk.catalogEmpty,
    // Calibration state is authoritative once it exists; the interaction-count
    // heuristic stays as the fallback for profiles that predate calibration.
    profileBuilding: calibrationState.complete
      ? false
      : calibrationState.completedCount > 0 ||
        profile.interactionCount < HUMOR_PROFILE_BUILDING_THRESHOLD,
    interactionCount: profile.interactionCount,
    calibration: calibrationView,
  };
}
