import type {Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {listCandidateHumorContent, toFeedSafeContent} from "./contentRepository.js";
import {canServeHumorContent} from "./moderation.js";
import {defaultUserHumorProfile} from "./profile.js";
import {topUpHumorFromProviders} from "./providerOrchestrator.js";
import {rankHumorFeed} from "./ranking.js";
import {safeLogMeta} from "../security/logHygiene.js";
import {isUserPremium} from "../premium.js";
import {
  HUMOR_FEED_PAGE_SIZE,
  HUMOR_PROFILE_BUILDING_THRESHOLD,
  type HumorContentDoc,
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
    funnyCount: Math.max(0, Number(data.funnyCount ?? 0)),
    notFunnyCount: Math.max(0, Number(data.notFunnyCount ?? 0)),
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

/** Avoid long runs of the same provider in a page. */
export function diversifyByProvider(items: HumorContentDoc[]): HumorContentDoc[] {
  if (items.length <= 2) {
    return items;
  }
  const remaining = [...items];
  const out: HumorContentDoc[] = [];
  let lastProvider: string | null = null;
  while (remaining.length > 0) {
    let idx = remaining.findIndex((c) => (c.source?.provider ?? "") !== lastProvider);
    if (idx < 0) {
      idx = 0;
    }
    const [picked] = remaining.splice(idx, 1);
    out.push(picked);
    lastProvider = picked.source?.provider ?? null;
  }
  return out;
}

/** Prefer category spread within a page. */
export function diversifyByCategory(items: HumorContentDoc[]): HumorContentDoc[] {
  if (items.length <= 2) {
    return items;
  }
  const remaining = [...items];
  const out: HumorContentDoc[] = [];
  let lastCategory: string | null = null;
  while (remaining.length > 0) {
    let idx = remaining.findIndex((c) => String(c.category) !== lastCategory);
    if (idx < 0) {
      idx = 0;
    }
    const [picked] = remaining.splice(idx, 1);
    out.push(picked);
    lastCategory = String(picked.category);
  }
  return out;
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
  isPremium: boolean;
  adsEnabled: boolean;
  providerMeta?: {
    attempts: unknown[];
    toppedUp: number;
  };
}> {
  const limit = Math.min(15, Math.max(10, input.limit ?? HUMOR_FEED_PAGE_SIZE));
  const languages =
    (input.languages ?? []).map((l) => l.toLowerCase()).filter(Boolean).length > 0
      ? (input.languages ?? []).map((l) => l.toLowerCase())
      : ["tr", "en"];

  const [profile, seenFromDb, premium] = await Promise.all([
    loadUserHumorProfile(input.db, input.uid),
    loadSeenContentIds(input.db, input.uid),
    isUserPremium(input.uid),
  ]);
  const cursorSeen = decodeCursor(input.cursor);
  const seen = new Set([...seenFromDb, ...cursorSeen]);

  let candidates = await listCandidateHumorContent(input.db, {
    languages,
    limit: 120,
  });
  let eligible = candidates.filter((c) =>
    canServeHumorContent({active: c.active, safetyStatus: c.safetyStatus}),
  );
  let unseenEligible = eligible.filter((c) => !seen.has(c.contentId));

  let providerMeta: {attempts: unknown[]; toppedUp: number} | undefined;

  // Live top-up when pool is thin — YouTube → GIPHY → (Tenor off) → internal.
  if (unseenEligible.length < limit) {
    try {
      const topUp = await topUpHumorFromProviders({
        db: input.db,
        languages,
        needed: limit - unseenEligible.length + 4,
        excludeIds: new Set([...seen, ...eligible.map((c) => c.contentId)]),
      });
      providerMeta = {
        attempts: topUp.attempts,
        toppedUp: topUp.contentIds.length,
      };
      if (topUp.contentIds.length > 0) {
        candidates = await listCandidateHumorContent(input.db, {
          languages,
          limit: 120,
        });
        eligible = candidates.filter((c) =>
          canServeHumorContent({active: c.active, safetyStatus: c.safetyStatus}),
        );
        unseenEligible = eligible.filter((c) => !seen.has(c.contentId));
      }
    } catch (error) {
      logger.warn(
        "humor live top-up failed; serving internal pool",
        safeLogMeta({uid: input.uid, error: String(error)}),
      );
    }
  }

  let ranked = diversifyByCategory(
    diversifyByProvider(
      rankHumorFeed({
        profile,
        items: eligible.map((content) => ({
          content,
          seen: seen.has(content.contentId),
        })),
        userLanguages: languages,
        limit: limit * 2,
      }).filter((c) => !seen.has(c.contentId)),
    ),
  );

  // Infinite feed: recycle seen catalog when unseen pool is exhausted.
  if (ranked.length < limit && eligible.length > 0) {
    const recycled = diversifyByCategory(
      diversifyByProvider(
        rankHumorFeed({
          profile,
          items: eligible.map((content) => ({
            content,
            seen: true,
          })),
          userLanguages: languages,
          limit: limit * 2,
        }).filter((c) => !ranked.some((r) => r.contentId === c.contentId)),
      ),
    );
    ranked = [...ranked, ...recycled].slice(0, limit);
  }

  const page = ranked.slice(0, limit);
  const pageIds = page.map((c) => c.contentId);
  const nextSeen = [...seen, ...pageIds];
  // Keep paging while catalog has anything to show.
  const nextCursor = eligible.length > 0 && page.length > 0 ? encodeCursor(nextSeen) : null;

  return {
    items: page.map((c) => toFeedSafeContent(c)),
    nextCursor,
    profileBuilding: profile.interactionCount < HUMOR_PROFILE_BUILDING_THRESHOLD,
    interactionCount: profile.interactionCount,
    isPremium: premium,
    adsEnabled: !premium,
    providerMeta,
  };
}
