import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentSnapshot, type Transaction} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const callableOptions = {region: "europe-west1" as const};

export const INITIAL_MATCH_SCORE = 50;
export const MATCH_BONUS = 1;
export const INTERACTION_BONUS = 1;
export const INTERACTION_WINDOW_MS = 3 * 24 * 60 * 60 * 1000;
export const FEEDBACK_MAX_CHARS = 200;

export type MatchScoreHistoryType = "new_match" | "post_match_interaction";
export type MatchEndedReason = "unmatch" | "block";

const INSULT_RE = new RegExp(
  [
    "\\bidiot\\b",
    "\\bstupid\\b",
    "\\bdumb\\b",
    "\\bwhore\\b",
    "\\bslut\\b",
    "\\bbitch\\b",
    "\\bfuck(?:ing|er)?\\b",
    "\\bshit\\b",
    "\\basshole\\b",
    "\\bretard(?:ed)?\\b",
    "orospu",
    "siktir",
    "\\bamk\\b",
    "amına",
    "amina",
    "piç",
    "\\bpic\\b",
    "salak",
    "gerizekal[ıi]",
    "aptal",
    "\\bmal\\b",
    "kahpe",
    "yarrak",
  ].join("|"),
  "gi",
);

const EMAIL_RE = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const PHONE_RE = /(?:\+?\d[\d\s().-]{8,}\d)/g;

export function seedScore(current: unknown): number {
  return typeof current === "number" && Number.isFinite(current)
    ? current
    : INITIAL_MATCH_SCORE;
}

export function toMillis(value: unknown, fallback = 0): number {
  if (value && typeof value === "object" && "toMillis" in value) {
    return (value as {toMillis: () => number}).toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  return fallback;
}

export function shouldAwardMatchBonus(alreadyAwarded: unknown): boolean {
  return alreadyAwarded !== true;
}

export function isWithinInteractionWindow(matchedAtMs: number, nowMs: number): boolean {
  if (!matchedAtMs) {
    return false;
  }
  return nowMs - matchedAtMs <= INTERACTION_WINDOW_MS;
}

export function shouldAwardInteractionBonus(input: {
  alreadyAwarded: unknown;
  matchedAtMs: number;
  nowMs: number;
  messagedUserIds: string[];
  userIds: string[];
}): boolean {
  if (input.alreadyAwarded === true) {
    return false;
  }
  if (!isWithinInteractionWindow(input.matchedAtMs, input.nowMs)) {
    return false;
  }
  if (input.userIds.length !== 2) {
    return false;
  }
  const sent = new Set(input.messagedUserIds);
  return input.userIds.every((id) => sent.has(id));
}

export function sanitizeFeedback(raw: unknown): string {
  let text = String(raw ?? "").trim();
  if (text.length > FEEDBACK_MAX_CHARS) {
    text = text.slice(0, FEEDBACK_MAX_CHARS);
  }
  text = text.replace(EMAIL_RE, "***");
  text = text.replace(PHONE_RE, "***");
  text = text.replace(INSULT_RE, "***");
  return text.replace(/\s+/g, " ").trim();
}

export function canSubmitFeedback(input: {
  uid: string;
  isActive: unknown;
  unmatchedBy: unknown;
  alreadySubmitted: boolean;
}): boolean {
  if (input.alreadySubmitted) {
    return false;
  }
  if (input.isActive === true) {
    return false;
  }
  const endedBy = String(input.unmatchedBy ?? "");
  if (!endedBy || endedBy === input.uid) {
    return false;
  }
  return true;
}

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

export async function ensureMatchScore(uid: string): Promise<number> {
  const ref = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.data()?.matchScore;
    if (typeof current === "number" && Number.isFinite(current)) {
      return current;
    }
    tx.set(
      ref,
      {matchScore: INITIAL_MATCH_SCORE, matchCount: snap.data()?.matchCount ?? 0},
      {merge: true},
    );
    return INITIAL_MATCH_SCORE;
  });
}

async function incrementScoreTx(
  tx: Transaction,
  uid: string,
  userSnap: DocumentSnapshot,
  type: MatchScoreHistoryType,
  bumpMatchCount: boolean,
): Promise<void> {
  const userRef = db.doc(`users/${uid}`);
  const data = userSnap.data() ?? {};
  const next = seedScore(data.matchScore) + 1;
  const matchCount = Number(data.matchCount ?? 0) + (bumpMatchCount ? 1 : 0);
  tx.set(
    userRef,
    {
      matchScore: next,
      matchCount,
    },
    {merge: true},
  );
  tx.set(db.collection(`users/${uid}/matchScoreHistory`).doc(), {
    type,
    delta: 1,
    createdAt: FieldValue.serverTimestamp(),
  });
}

export async function awardUniqueMatchBonus(matchId: string): Promise<void> {
  const matchRef = db.doc(`matches/${matchId}`);
  await db.runTransaction(async (tx) => {
    const matchSnap = await tx.get(matchRef);
    const data = matchSnap.data();
    if (!matchSnap.exists || !data) {
      return;
    }
    if (!shouldAwardMatchBonus(data.matchBonusAwarded)) {
      return;
    }
    const userIds = ((data.userIds as string[]) ?? []).filter(Boolean);
    if (userIds.length !== 2) {
      return;
    }
    const userSnaps = await Promise.all(userIds.map((uid) => tx.get(db.doc(`users/${uid}`))));
    tx.update(matchRef, {matchBonusAwarded: true});
    for (let i = 0; i < userIds.length; i += 1) {
      incrementScoreTx(tx, userIds[i], userSnaps[i], "new_match", true);
    }
  });
}

export async function applyMessageSideEffects(input: {
  matchId: string;
  senderId: string;
  receiverId: string;
  lastMessage: string;
}): Promise<void> {
  const matchRef = db.doc(`matches/${input.matchId}`);
  await db.runTransaction(async (tx) => {
    const matchSnap = await tx.get(matchRef);
    const data = matchSnap.data();
    if (!matchSnap.exists || !data) {
      return;
    }
    const userIds = ((data.userIds as string[]) ?? []).filter(Boolean);
    const messaged = new Set<string>((data.messagedUserIds as string[]) ?? []);
    messaged.add(input.senderId);
    const matchedAtMs = toMillis(data.matchedAt ?? data.createdAt);
    const willAward = shouldAwardInteractionBonus({
      alreadyAwarded: data.interactionBonusAwarded,
      matchedAtMs,
      nowMs: Date.now(),
      messagedUserIds: [...messaged],
      userIds,
    });
    const userSnaps = willAward
      ? await Promise.all(userIds.map((uid) => tx.get(db.doc(`users/${uid}`))))
      : [];
    const updates: Record<string, unknown> = {
      lastMessage: input.lastMessage,
      lastMessageAt: FieldValue.serverTimestamp(),
      [`unreadCounts.${input.receiverId}`]: FieldValue.increment(1),
      [`isNewFor.${input.receiverId}`]: false,
      messagedUserIds: FieldValue.arrayUnion([input.senderId]),
    };
    if (willAward) {
      updates.interactionBonusAwarded = true;
    }
    tx.update(matchRef, updates);
    if (willAward) {
      for (let i = 0; i < userIds.length; i += 1) {
        incrementScoreTx(tx, userIds[i], userSnaps[i], "post_match_interaction", false);
      }
    }
  });
}

export async function queuePostMatchFeedback(input: {
  matchId: string;
  endedBy: string;
  reason: MatchEndedReason;
  userIds: string[];
}): Promise<void> {
  const other = input.userIds.find((id) => id !== input.endedBy);
  if (!other) {
    return;
  }
  const existing = await db.doc(`users/${other}/matchFeedback/${input.matchId}`).get();
  if (existing.exists) {
    return;
  }
  await db.doc(`users/${other}/pendingMatchFeedback/${input.matchId}`).set({
    matchId: input.matchId,
    endedBy: input.endedBy,
    endedReason: input.reason,
    createdAt: FieldValue.serverTimestamp(),
  });
}

export function preservedMatchScoreFields(existing?: {
  matchedAt?: unknown;
  matchBonusAwarded?: unknown;
  interactionBonusAwarded?: unknown;
  messagedUserIds?: unknown;
  isActive?: unknown;
} | null) {
  const rematching = existing?.isActive === false;
  return {
    matchedAt:
      rematching || !existing?.matchedAt
        ? FieldValue.serverTimestamp()
        : existing.matchedAt,
    matchBonusAwarded: existing?.matchBonusAwarded === true,
    interactionBonusAwarded: existing?.interactionBonusAwarded === true,
    messagedUserIds:
      existing?.interactionBonusAwarded === true
        ? ((existing.messagedUserIds as string[]) ?? [])
        : [],
    endedReason: null,
  };
}

export const seedMatchScoreOnUserCreate = onDocumentCreated(
  {
    document: "users/{userId}",
    region: "europe-west1",
  },
  async (event) => {
    const uid = event.params.userId;
    if (!uid) {
      return;
    }
    await ensureMatchScore(uid);
  },
);

export const awardMatchBonusOnMatchCreate = onDocumentCreated(
  {
    document: "matches/{matchId}",
    region: "europe-west1",
  },
  async (event) => {
    await awardUniqueMatchBonus(event.params.matchId);
  },
);

export const submitMatchFeedback = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const matchId = String(request.data?.matchId ?? "");
  const text = sanitizeFeedback(request.data?.text);
  if (!matchId) {
    throw new HttpsError("invalid-argument", "matchId");
  }
  if (!text) {
    throw new HttpsError("invalid-argument", "empty");
  }
  const matchSnap = await db.doc(`matches/${matchId}`).get();
  const data = matchSnap.data();
  const userIds = (data?.userIds as string[]) ?? [];
  if (!matchSnap.exists || !userIds.includes(uid)) {
    throw new HttpsError("permission-denied", "not-matched");
  }
  const feedbackRef = db.doc(`users/${uid}/matchFeedback/${matchId}`);
  const existing = await feedbackRef.get();
  if (
    !canSubmitFeedback({
      uid,
      isActive: data?.isActive,
      unmatchedBy: data?.unmatchedBy,
      alreadySubmitted: existing.exists,
    })
  ) {
    throw new HttpsError("failed-precondition", "not-eligible");
  }
  await feedbackRef.set({
    matchId,
    endedBy: data?.unmatchedBy ?? null,
    endedReason: data?.endedReason ?? null,
    text,
    createdAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`users/${uid}/pendingMatchFeedback/${matchId}`).delete().catch(() => undefined);
  return {ok: true};
});

export const dismissMatchFeedback = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const matchId = String(request.data?.matchId ?? "");
  if (!matchId) {
    throw new HttpsError("invalid-argument", "matchId");
  }
  await db.doc(`users/${uid}/pendingMatchFeedback/${matchId}`).delete();
  return {ok: true};
});
