import type {Firestore} from "firebase-admin/firestore";
import {
  parseCalibrationState,
  toCalibrationView,
  type CalibrationStateView,
} from "./calibration.js";
import {selectCalibrationItems} from "./calibrationFeed.js";
import {
  listHumorContentPage,
  toFeedSafeContent,
  type HumorCandidatePage,
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

export async function loadUserHumorCalibration(
  db: Firestore,
  uid: string,
): Promise<UserHumorCalibrationDoc> {
  const snap = await db.doc(HUMOR_CALIBRATION_DOC(uid)).get();
  return parseCalibrationState(snap.data() as Record<string, unknown> | undefined);
}

export async function loadUserHumorProfile(
  db: Firestore,
  uid: string,
): Promise<UserHumorProfileDoc> {
  const snap = await db.doc(`users/${uid}/humor/summary`).get();
  if (!snap.exists) {
    return defaultUserHumorProfile();
  }
  const data = snap.data() ?? {};
  const base = defaultUserHumorProfile();
  return {
    ...base,
    vector: {...base.vector, ...(data.vector ?? {})},
    confidence: Number(data.confidence ?? 0),
    interactionCount: Number(data.interactionCount ?? 0),
    exploredCategories: Array.isArray(data.exploredCategories)
      ? data.exploredCategories.map((c: unknown) => String(c))
      : [],
    lastUpdatedAt: data.lastUpdatedAt,
    version: Number(data.version ?? base.version),
  };
}

export async function loadSeenContentIds(db: Firestore, uid: string): Promise<Set<string>> {
  const snap = await db
    .collection(`users/${uid}/humorInteractions`)
    .select()
    .limit(SEEN_PREFETCH_LIMIT)
    .get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * Bounded prefetch of already-rated ids, used to keep seen content out of the
 * ranking window cheaply. It is a filter, not a guarantee: `dropAlreadyRated`
 * does the exact check on the handful of items actually being served, so a
 * user past this many interactions still never sees a repeat.
 */
const SEEN_PREFETCH_LIMIT = 1000;

/**
 * How far the feed may walk the catalog in one request.
 *
 * Bounds the work per call to at most MAX_SCAN_PAGES × SCAN_PAGE_SIZE reads.
 * The walk stops as soon as it has enough unseen items to fill the page.
 */
const SCAN_PAGE_SIZE = 60;
const MAX_SCAN_PAGES = 4;

/**
 * The cursor now carries a catalog *position* rather than a list of seen ids.
 *
 * The old cursor shipped the client an unbounded, unsigned `seen` array and
 * still could not move past the first 120 documents. Position is bounded,
 * meaningless to forge (every approved item is readable to any signed-in user
 * anyway) and is what actually lets pagination progress.
 */
function decodeCursor(cursor: string | null | undefined): HumorScanPosition | null {
  if (!cursor) {
    return null;
  }
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as {
      createdAtMs?: unknown;
      contentId?: unknown;
    };
    const createdAtMs = Number(parsed.createdAtMs);
    const contentId = String(parsed.contentId ?? "");
    if (!Number.isFinite(createdAtMs) || !contentId || contentId.length > 128) {
      return null;
    }
    return {createdAtMs, contentId};
  } catch {
    return null;
  }
}

function encodeCursor(position: HumorScanPosition): string {
  return Buffer.from(JSON.stringify(position), "utf8").toString("base64url");
}

/**
 * Where this user's catalog walk has reached, persisted server-side.
 *
 * Without it a cold client (app restart, relog, no cursor) rescans the whole
 * rated prefix every time. Once a heavy user has rated more items than one
 * request's scan budget, that prefix is longer than the budget and the feed
 * goes permanently empty — the exhaustion bug in a different disguise.
 *
 * Stored as a field on the existing humor summary rather than a new document,
 * so it inherits the owner-read / client-write-denied rule and the existing
 * account-deletion sweep.
 */
const FEED_POSITION_FIELD = "feedPosition";

function parseFeedPosition(value: unknown): HumorScanPosition | null {
  if (!value || typeof value !== "object") {
    return null;
  }
  const raw = value as {createdAtMs?: unknown; contentId?: unknown};
  const createdAtMs = Number(raw.createdAtMs);
  const contentId = String(raw.contentId ?? "");
  if (!Number.isFinite(createdAtMs) || !contentId) {
    return null;
  }
  return {createdAtMs, contentId};
}

async function loadFeedPosition(
  db: Firestore,
  uid: string,
): Promise<HumorScanPosition | null> {
  const snap = await db.doc(`users/${uid}/humor/summary`).get();
  return parseFeedPosition(snap.data()?.[FEED_POSITION_FIELD]);
}

async function saveFeedPosition(
  db: Firestore,
  uid: string,
  position: HumorScanPosition | null,
): Promise<void> {
  await db
    .doc(`users/${uid}/humor/summary`)
    .set({[FEED_POSITION_FIELD]: position}, {merge: true})
    .catch(() => undefined);
}

/**
 * Final guard against re-serving content.
 *
 * `loadSeenContentIds` is capped, so a heavy user's seen set is incomplete and
 * ranking alone could let an already-rated card slip through. This checks the
 * handful of items actually about to be served, exactly, against the
 * interaction documents — bounded at one `getAll` of at most `limit` refs.
 */
async function dropAlreadyRated(
  db: Firestore,
  uid: string,
  items: HumorContentDoc[],
): Promise<HumorContentDoc[]> {
  if (items.length === 0) {
    return items;
  }
  const refs = items.map((item) =>
    db.doc(`users/${uid}/humorInteractions/${item.contentId}`),
  );
  const snaps = await db.getAll(...refs);
  return items.filter((_, index) => !snaps[index]?.exists);
}

export async function buildHumorFeed(input: {
  db: Firestore;
  uid: string;
  languages?: string[];
  limit?: number;
  cursor?: string | null;
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
  const languages =
    (input.languages ?? []).map((l) => l.toLowerCase()).filter(Boolean).length > 0
      ? (input.languages ?? []).map((l) => l.toLowerCase())
      : ["tr", "en"];

  const [profile, seen, calibrationState] = await Promise.all([
    loadUserHumorProfile(input.db, input.uid),
    loadSeenContentIds(input.db, input.uid),
    loadUserHumorCalibration(input.db, input.uid),
  ]);
  const scanFrom = decodeCursor(input.cursor);

  // Initial calibration owns the page while it is running. It uses its own
  // curated selector rather than the personalized ranker, so the structured
  // 6/6/3 contract cannot be diluted by ranking heuristics.
  const calibrationPicks = calibrationState.complete
    ? {picks: [], unfilled: 0, deficiencies: [] as string[]}
    : await selectCalibrationItems({
        db: input.db,
        uid: input.uid,
        state: calibrationState,
        profile,
        languages,
        limit,
        excludeContentIds: seen,
      });

  const calibrationView = {
    ...toCalibrationView(calibrationState),
    insufficientPool: calibrationPicks.deficiencies.length > 0,
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

  // Walk the catalog from the cursor position, taking unseen items in catalog
  // order until the page is full or the catalog runs out.
  //
  // Two deliberate properties:
  //
  //  * Seen items are dropped *before* ranking. The previous code ranked them
  //    in, capped the result at `limit` and only then filtered them out, so
  //    seen cards silently ate page slots and short-changed every page.
  //  * The cursor stops after the last item actually taken, never after the
  //    last item scanned. Ranking a large window and serving only the top
  //    slice would skip the rest of that window permanently — the user would
  //    only ever reach a fraction of the catalog. Ranking therefore decides
  //    the order the page is presented in, while catalog order decides which
  //    items are due next. Nothing is skipped.
  // An explicit cursor wins; otherwise resume where this user left off.
  const startFrom = scanFrom ?? (await loadFeedPosition(input.db, input.uid));

  const taken: HumorContentDoc[] = [];
  let lastTaken: HumorScanPosition | null = null;
  let scanPosition: HumorScanPosition | null = startFrom;
  let sawAnyContent = false;
  let exhausted = false;

  for (let pageIndex = 0; pageIndex < MAX_SCAN_PAGES && taken.length < limit; pageIndex += 1) {
    const result: HumorCandidatePage = await listHumorContentPage(input.db, {
      languages,
      pageSize: SCAN_PAGE_SIZE,
      after: scanPosition,
    });
    sawAnyContent = sawAnyContent || result.entries.length > 0;

    for (const entry of result.entries) {
      if (taken.length >= limit) {
        break;
      }
      if (seen.has(entry.content.contentId)) {
        continue;
      }
      if (
        !canServeHumorContent({
          active: entry.content.active,
          safetyStatus: entry.content.safetyStatus,
        })
      ) {
        continue;
      }
      taken.push(entry.content);
      lastTaken = entry.position;
    }

    if (result.exhausted) {
      exhausted = true;
      break;
    }
    scanPosition = result.scannedTo;
  }

  // Ranking reorders what is already due; it no longer selects.
  const ranked = rankHumorFeed({
    profile,
    items: taken.map((content) => ({content, seen: false})),
    userLanguages: languages,
    limit,
  });
  const page = await dropAlreadyRated(input.db, input.uid, ranked.slice(0, limit));

  // Where the next request should resume:
  //  * page filled  → just after the last item served, since more may follow
  //    even though this scan happened to touch the end of the catalog;
  //  * page short, catalog exhausted → nowhere, and the stored position resets
  //    so a later call re-scans from the top and picks up new content;
  //  * page short, scan budget spent → continue from where scanning stopped.
  const filledPage = taken.length >= limit;
  const resumeFrom: HumorScanPosition | null = filledPage
    ? lastTaken
    : exhausted
      ? null
      : scanPosition;

  await saveFeedPosition(input.db, input.uid, resumeFrom);

  return {
    items: page.map((c) => toFeedSafeContent(c, null)),
    nextCursor: resumeFrom ? encodeCursor(resumeFrom) : null,
    catalogExhausted: exhausted && page.length === 0,
    catalogEmpty: !sawAnyContent && startFrom === null,
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
