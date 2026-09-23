import {createHash} from "node:crypto";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import type {DocumentData, Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

/**
 * Boost measurement — what a Boost buyer actually received.
 *
 * Every number here is written by the server from its own observations. The
 * client never reports being viewed, and never writes a counter.
 *
 * Two documents carry the whole model:
 *
 *   users/{uid}/boosts/{boostId}          the session, plus its running totals
 *   users/{uid}/boostReach/{viewerKey}    one row per (viewer, boosted user)
 *
 * The reach row is both the unique-viewer record and the attribution ledger:
 * it remembers which Boost session showed this viewer the profile, so a later
 * like or match can be attributed to that session from a single known-path
 * read — no query, and no guessing from timestamps alone.
 */

/** A currently-running Boost period. `boostId` is the session identity. */
export interface BoostSession {
  boostId: string;
  userId: string;
  startedAt: Date | null;
  expiresAt: Date;
}

export interface BoostMetrics {
  totalImpressions: number;
  uniqueUsersReached: number;
  likesReceived: number;
  matchesCreated: number;
}

export const ZERO_METRICS: BoostMetrics = {
  totalImpressions: 0,
  uniqueUsersReached: 0,
  likesReceived: 0,
  matchesCreated: 0,
};

/**
 * Deterministic, privacy-safe key for a (viewer, boosted user) pair.
 *
 * Salted with the boosted user's id so the same viewer produces a different
 * key under every profile — the rows cannot be joined into a viewing history
 * for a person, and no raw viewer uid is stored in the reach document.
 */
export function viewerKey(viewerUid: string, boostedUid: string): string {
  return createHash("sha256")
    .update(`${viewerUid}:${boostedUid}`)
    .digest("hex")
    .slice(0, 32);
}

export function boostReachPath(boostedUid: string, key: string): string {
  return `users/${boostedUid}/boostReach/${key}`;
}

export function boostSessionPath(uid: string, boostId: string): string {
  return `users/${uid}/boosts/${boostId}`;
}

function toDate(value: unknown): Date | null {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date && Number.isFinite(value.getTime())) {
    return value;
  }
  return null;
}

function toCount(value: unknown): number {
  const n = Number(value ?? 0);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

export function metricsFromDocument(data: DocumentData | undefined): BoostMetrics {
  if (!data) {
    return {...ZERO_METRICS};
  }
  return {
    totalImpressions: toCount(data.totalImpressions),
    uniqueUsersReached: toCount(data.uniqueUsersReached),
    likesReceived: toCount(data.likesReceived),
    matchesCreated: toCount(data.matchesCreated),
  };
}

/**
 * Decides what a single Discover page means for one boosted profile.
 *
 * Pure so the counting rules are testable without Firestore. A reach row
 * belonging to an older Boost session counts as a fresh unique reach: reach is
 * measured per session, not per lifetime.
 */
export function classifyImpression(
  existing: DocumentData | undefined,
  session: BoostSession,
): {isNewSession: boolean; countsAsUnique: boolean} {
  if (!existing) {
    return {isNewSession: true, countsAsUnique: true};
  }
  const sameSession = existing.boostId === session.boostId;
  return {isNewSession: !sameSession, countsAsUnique: !sameSession};
}

/**
 * Records one Discover page.
 *
 * `shownUids` must be the profiles that actually reached the response — being
 * considered as a ranking candidate is not an impression.
 *
 * Cost is bounded by the density cap: a page of at most 20 holds at most 7
 * boosted profiles, so this is one batched read of ≤7 documents and one
 * batched commit of ≤14 writes, whatever the page size.
 *
 * Never throws into the Discover response: a measurement failure must not cost
 * a user their results.
 */
export async function recordBoostImpressions(params: {
  db?: Firestore;
  viewerUid: string;
  shownUids: string[];
  sessions: Map<string, BoostSession>;
  now?: Date;
}): Promise<{impressions: number; newUniqueReach: number}> {
  const db = params.db ?? getFirestore();
  const now = params.now ?? new Date();
  const targets: BoostSession[] = [];
  const seen = new Set<string>();

  for (const uid of params.shownUids) {
    if (!uid || uid === params.viewerUid || seen.has(uid)) {
      continue;
    }
    const session = params.sessions.get(uid);
    if (!session || session.expiresAt.getTime() <= now.getTime()) {
      continue;
    }
    seen.add(uid);
    targets.push(session);
  }
  if (targets.length === 0) {
    return {impressions: 0, newUniqueReach: 0};
  }

  try {
    const refs = targets.map((session) =>
      db.doc(boostReachPath(session.userId, viewerKey(params.viewerUid, session.userId))),
    );
    const snaps = await db.getAll(...refs);
    const batch = db.batch();
    let newUniqueReach = 0;

    targets.forEach((session, index) => {
      const snap = snaps[index];
      const {isNewSession, countsAsUnique} = classifyImpression(
        snap.exists ? snap.data() : undefined,
        session,
      );
      if (isNewSession) {
        batch.set(refs[index], {
          boostId: session.boostId,
          boostExpiresAt: Timestamp.fromDate(session.expiresAt),
          firstSeenAt: FieldValue.serverTimestamp(),
          lastSeenAt: FieldValue.serverTimestamp(),
          impressions: 1,
          likedAt: null,
          matchedAt: null,
        });
      } else {
        batch.update(refs[index], {
          impressions: FieldValue.increment(1),
          lastSeenAt: FieldValue.serverTimestamp(),
        });
      }
      if (countsAsUnique) {
        newUniqueReach += 1;
      }
      batch.set(
        db.doc(boostSessionPath(session.userId, session.boostId)),
        {
          totalImpressions: FieldValue.increment(1),
          uniqueUsersReached: FieldValue.increment(countsAsUnique ? 1 : 0),
          metricsUpdatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    await batch.commit();
    return {impressions: targets.length, newUniqueReach};
  } catch (error) {
    logger.warn("boost_impression_write_failed", {
      shown: targets.length,
      message: error instanceof Error ? error.message : String(error),
    });
    return {impressions: 0, newUniqueReach: 0};
  }
}

export type AttributionOutcome =
  | "attributed"
  | "no_reach"
  | "already_counted"
  | "boost_ended"
  | "failed";

/**
 * Attributes a like or a match to the Boost session that actually showed the
 * profile to this viewer.
 *
 * Strict, not time-window: the viewer must have a reach row from a session
 * that was still running. A like from someone who never saw the boosted page
 * is not Boost's doing and is not counted.
 *
 * Idempotent — `likedAt` / `matchedAt` are set once per (viewer, session), so
 * a duplicate callable, a retry or a replayed trigger cannot inflate the
 * total.
 */
export async function attributeBoostEvent(params: {
  db?: Firestore;
  viewerUid: string;
  boostedUid: string;
  kind: "like" | "match";
  now?: Date;
}): Promise<{outcome: AttributionOutcome; boostId?: string}> {
  const db = params.db ?? getFirestore();
  const now = params.now ?? new Date();
  if (!params.viewerUid || !params.boostedUid || params.viewerUid === params.boostedUid) {
    return {outcome: "no_reach"};
  }
  const stamp = params.kind === "like" ? "likedAt" : "matchedAt";
  const counter = params.kind === "like" ? "likesReceived" : "matchesCreated";
  const reachRef = db.doc(
    boostReachPath(params.boostedUid, viewerKey(params.viewerUid, params.boostedUid)),
  );

  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(reachRef);
      if (!snap.exists) {
        return {outcome: "no_reach" as const};
      }
      const data = snap.data() ?? {};
      const boostId = typeof data.boostId === "string" ? data.boostId : "";
      if (!boostId) {
        return {outcome: "no_reach" as const};
      }
      if (data[stamp]) {
        return {outcome: "already_counted" as const, boostId};
      }
      const expiresAt = toDate(data.boostExpiresAt);
      if (!expiresAt || expiresAt.getTime() <= now.getTime()) {
        return {outcome: "boost_ended" as const, boostId};
      }
      tx.update(reachRef, {[stamp]: FieldValue.serverTimestamp()});
      tx.set(
        db.doc(boostSessionPath(params.boostedUid, boostId)),
        {
          [counter]: FieldValue.increment(1),
          metricsUpdatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      return {outcome: "attributed" as const, boostId};
    });
  } catch (error) {
    logger.warn("boost_attribution_failed", {
      kind: params.kind,
      message: error instanceof Error ? error.message : String(error),
    });
    return {outcome: "failed"};
  }
}
