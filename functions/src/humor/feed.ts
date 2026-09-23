import type {Firestore} from "firebase-admin/firestore";
import {
  parseCalibrationState,
  toCalibrationView,
  type CalibrationStateView,
} from "./calibration.js";
import {selectCalibrationItems} from "./calibrationFeed.js";
import {listCandidateHumorContent, toFeedSafeContent} from "./contentRepository.js";
import {canServeHumorContent} from "./moderation.js";
import {defaultUserHumorProfile} from "./profile.js";
import {rankHumorFeed} from "./ranking.js";
import {
  HUMOR_FEED_PAGE_SIZE,
  HUMOR_PROFILE_BUILDING_THRESHOLD,
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
    .limit(500)
    .get();
  return new Set(snap.docs.map((d) => d.id));
}

function decodeCursor(cursor: string | null | undefined): Set<string> {
  if (!cursor) {
    return new Set();
  }
  try {
    const parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8")) as {
      seen?: string[];
    };
    return new Set((parsed.seen ?? []).map(String));
  } catch {
    return new Set();
  }
}

function encodeCursor(seenIds: string[]): string {
  const trimmed = seenIds.slice(-200);
  return Buffer.from(JSON.stringify({seen: trimmed}), "utf8").toString("base64url");
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
  profileBuilding: boolean;
  interactionCount: number;
  calibration: CalibrationStateView & {insufficientPool: boolean};
}> {
  const limit = Math.min(15, Math.max(10, input.limit ?? HUMOR_FEED_PAGE_SIZE));
  const languages =
    (input.languages ?? []).map((l) => l.toLowerCase()).filter(Boolean).length > 0
      ? (input.languages ?? []).map((l) => l.toLowerCase())
      : ["tr", "en"];

  const [profile, seenFromDb, calibrationState] = await Promise.all([
    loadUserHumorProfile(input.db, input.uid),
    loadSeenContentIds(input.db, input.uid),
    loadUserHumorCalibration(input.db, input.uid),
  ]);
  const cursorSeen = decodeCursor(input.cursor);
  const seen = new Set([...seenFromDb, ...cursorSeen]);

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
      profileBuilding: true,
      interactionCount: profile.interactionCount,
      calibration: calibrationView,
    };
  }

  const candidates = await listCandidateHumorContent(input.db, {
    languages,
    limit: 120,
  });
  const eligible = candidates.filter((c) =>
    canServeHumorContent({active: c.active, safetyStatus: c.safetyStatus}),
  );
  const ranked = rankHumorFeed({
    profile,
    items: eligible.map((content) => ({
      content,
      seen: seen.has(content.contentId),
    })),
    userLanguages: languages,
    limit,
  }).filter((c) => !seen.has(c.contentId));

  const page = ranked.slice(0, limit);
  const pageIds = page.map((c) => c.contentId);
  const nextSeen = [...seen, ...pageIds];
  const nextCursor =
    page.length > 0 && eligible.length > page.length
      ? encodeCursor(nextSeen)
      : page.length >= limit
        ? encodeCursor(nextSeen)
        : null;

  return {
    items: page.map((c) => toFeedSafeContent(c, null)),
    nextCursor,
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
