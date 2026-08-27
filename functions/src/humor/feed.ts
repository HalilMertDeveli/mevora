import type {Firestore} from "firebase-admin/firestore";
import {listCandidateHumorContent, toFeedSafeContent} from "./contentRepository.js";
import {canServeHumorContent} from "./moderation.js";
import {defaultUserHumorProfile} from "./profile.js";
import {rankHumorFeed} from "./ranking.js";
import {
  HUMOR_FEED_PAGE_SIZE,
  HUMOR_PROFILE_BUILDING_THRESHOLD,
  type HumorFeedItem,
  type UserHumorProfileDoc,
} from "./types.js";

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
}> {
  const limit = Math.min(15, Math.max(10, input.limit ?? HUMOR_FEED_PAGE_SIZE));
  const languages =
    (input.languages ?? []).map((l) => l.toLowerCase()).filter(Boolean).length > 0
      ? (input.languages ?? []).map((l) => l.toLowerCase())
      : ["tr", "en"];

  const [profile, seenFromDb] = await Promise.all([
    loadUserHumorProfile(input.db, input.uid),
    loadSeenContentIds(input.db, input.uid),
  ]);
  const cursorSeen = decodeCursor(input.cursor);
  const seen = new Set([...seenFromDb, ...cursorSeen]);
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
    items: page.map((c) => toFeedSafeContent(c)),
    nextCursor,
    profileBuilding: profile.interactionCount < HUMOR_PROFILE_BUILDING_THRESHOLD,
    interactionCount: profile.interactionCount,
  };
}
