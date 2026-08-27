import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {canonicalMatchId} from "./ids.js";
import {preservedMatchScoreFields} from "./matchScore.js";
import {
  istanbulRoundId,
  optimizeMatches,
  predecessorRoundId,
  previousIstanbulRoundId,
  type AnswerMap,
} from "./hourlyMatchingGameEngine.js";
import {
  isValidRelationshipAnswer,
  normalizeAnswerId,
  setIdFor,
} from "./relationshipCompatibility.js";
import {recordMatchingGameParticipation} from "./matchingStreak.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};

const TIMEZONE = "Europe/Istanbul";
const ROUND_COLLECTION = "matchingGameRounds";

type RoundStatus = "OPEN" | "COLLECTING" | "LOCKED" | "MATCHING" | "COMPLETED";

function gameLog(message: string, extra?: unknown): void {
  if (extra === undefined) {
    console.log(`[HOURLY_GAME] ${message}`);
    return;
  }
  console.log(`[HOURLY_GAME] ${message}`, extra);
}

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "unauthenticated");
  return uid;
}

function roundRef(roundId: string) {
  return db.doc(`${ROUND_COLLECTION}/${roundId}`);
}

function participantRef(roundId: string, uid: string) {
  return db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${uid}`);
}

async function loadProfileEligibility(
  uid: string,
): Promise<{ok: true} | {ok: false; reason: string}> {
  const [userSnap, profileSnap] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
  ]);
  const user = userSnap.data() ?? {};
  const profile = profileSnap.data() ?? {};
  if (user.isBanned === true || profile.isBanned === true) {
    return {ok: false, reason: "banned"};
  }
  if (user.accountStatus === "deleted" || user.deletedAt != null) {
    return {ok: false, reason: "deleted"};
  }
  const completed =
    profile.profileCompleted === true ||
    profile.onboardingCompleted === true ||
    profile.isProfileComplete === true ||
    user.profileCompleted === true ||
    user.onboardingCompleted === true;
  if (!completed) {
    return {ok: false, reason: "onboarding-incomplete"};
  }
  return {ok: true};
}

async function ensureRoundOpen(roundId: string, now: Date): Promise<Record<string, unknown>> {
  const ref = roundRef(roundId);
  const snap = await ref.get();
  if (snap.exists) {
    return snap.data() ?? {};
  }
  const payload = {
    roundId,
    status: "OPEN" as RoundStatus,
    timezone: TIMEZONE,
    createdAt: FieldValue.serverTimestamp(),
    opensAt: Timestamp.fromDate(now),
    participantCount: 0,
    submittedCount: 0,
    matchCount: 0,
    unmatchedCount: 0,
  };
  try {
    await ref.create(payload);
    gameLog(`round created ${roundId}`);
  } catch {
    const again = await ref.get();
    if (again.exists) return again.data() ?? {};
    throw new HttpsError("internal", "round-create-failed");
  }
  return payload;
}

async function profilePreview(
  uid: string,
): Promise<{name: string; photoUrl: string | null}> {
  const snap = await db.doc(`profiles/${uid}`).get();
  const data = snap.data() ?? {};
  const name = String(data.displayName ?? data.firstName ?? "Mevora");
  const photos = data.photos;
  let photoUrl: string | null = null;
  if (Array.isArray(photos) && photos.length > 0) {
    const primary =
      photos.find((p: {isPrimary?: boolean}) => p?.isPrimary) ?? photos[0];
    if (typeof primary?.downloadUrl === "string") {
      photoUrl = primary.downloadUrl;
    }
  }
  return {name, photoUrl};
}

async function createHourlyMatch(input: {
  uid: string;
  otherUid: string;
  roundId: string;
  score: number;
  exactAligned: number;
}): Promise<string> {
  const matchId = canonicalMatchId(input.uid, input.otherUid);
  const matchRef = db.doc(`matches/${matchId}`);
  const existing = await matchRef.get();
  if (existing.exists && existing.data()?.isActive === true) {
    return matchId;
  }
  const [actor, other] = await Promise.all([
    profilePreview(input.uid),
    profilePreview(input.otherUid),
  ]);
  const previous = existing.data();
  await matchRef.set({
    userIds: [input.uid, input.otherUid].sort(),
    createdAt: previous?.createdAt ?? FieldValue.serverTimestamp(),
    lastMessage: null,
    lastMessageAt: FieldValue.serverTimestamp(),
    isActive: true,
    unmatchedBy: null,
    unmatchedAt: null,
    unreadCounts: {[input.uid]: 0, [input.otherUid]: 0},
    isNewFor: {[input.uid]: true, [input.otherUid]: true},
    participantNames: {
      [input.uid]: actor.name,
      [input.otherUid]: other.name,
    },
    participantPhotos: {
      ...(actor.photoUrl ? {[input.uid]: actor.photoUrl} : {}),
      ...(other.photoUrl ? {[input.otherUid]: other.photoUrl} : {}),
    },
    ...preservedMatchScoreFields(previous),
    source: "hourly_matching_game",
    matchType: "relationship",
    matchingGameRoundId: input.roundId,
    hourlyCompatibilityScore: input.score,
    hourlyExactAligned: input.exactAligned,
  });
  return matchId;
}

async function runMatchingForRound(roundId: string): Promise<void> {
  const ref = roundRef(roundId);
  const started = Date.now();

  const lock = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) {
      return "missing" as const;
    }
    const status = String(snap.data()?.status ?? "");
    if (status === "COMPLETED" || status === "MATCHING") {
      return status as "COMPLETED" | "MATCHING";
    }
    tx.update(ref, {
      status: "MATCHING",
      lockedAt: FieldValue.serverTimestamp(),
    });
    return "locked" as const;
  });

  if (lock === "COMPLETED" || lock === "MATCHING") {
    gameLog(`round ${roundId} skip matching (status=${lock})`);
    return;
  }
  if (lock === "missing") {
    gameLog(`round ${roundId} missing`);
    return;
  }

  const partsSnap = await ref
    .collection("participants")
    .where("status", "==", "submitted")
    .get();

  const participants: Array<{uid: string; answers: AnswerMap}> = [];
  for (const doc of partsSnap.docs) {
    const data = doc.data();
    const answers = (data.answerSnapshot ?? {}) as AnswerMap;
    if (Object.keys(answers).length === 0) continue;
    participants.push({uid: doc.id, answers});
  }

  gameLog(`matching started ${roundId}`, {participantCount: participants.length});

  const recentRepeat = new Set<string>();
  const prevId = predecessorRoundId(roundId);
  if (prevId != null && prevId !== roundId) {
    const prevMatches = await roundRef(prevId).collection("matches").limit(500).get();
    for (const doc of prevMatches.docs) {
      const users = doc.data().userIds;
      if (Array.isArray(users) && users.length === 2) {
        recentRepeat.add([String(users[0]), String(users[1])].sort().join("|"));
      }
    }
  }

  const pairs = optimizeMatches({
    participants,
    topK: 20,
    repeatPairs: recentRepeat,
    repeatPenalty: 15,
  });

  let matchCount = 0;
  const matchedUids = new Set<string>();

  for (const pair of pairs) {
    matchedUids.add(pair.userA);
    matchedUids.add(pair.userB);
    const matchId = await createHourlyMatch({
      uid: pair.userA,
      otherUid: pair.userB,
      roundId,
      score: pair.score,
      exactAligned: pair.exactAligned,
    });
    matchCount += 1;
    await ref.collection("matches").doc(matchId).set({
      matchId,
      userIds: [pair.userA, pair.userB],
      score: pair.score,
      exactAligned: pair.exactAligned,
      shared: pair.shared,
      avgDistance: pair.avgDistance,
      roundId,
      createdAt: FieldValue.serverTimestamp(),
    });
    await Promise.all([
      participantRef(roundId, pair.userA).set(
        {
          status: "matched",
          matchId,
          partnerId: pair.userB,
          compatibilityScore: pair.score,
          matchedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
      participantRef(roundId, pair.userB).set(
        {
          status: "matched",
          matchId,
          partnerId: pair.userA,
          compatibilityScore: pair.score,
          matchedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      ),
    ]);
  }

  await Promise.all(
    participants
      .filter((p) => !matchedUids.has(p.uid))
      .map((p) =>
        participantRef(roundId, p.uid).set(
          {
            status: "unmatched",
            matchId: null,
            partnerId: null,
            compatibilityScore: null,
            unmatchedAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        ),
      ),
  );

  const unmatchedCount = participants.length - matchedUids.size;
  await ref.set(
    {
      status: "COMPLETED",
      matchCount,
      unmatchedCount,
      submittedCount: participants.length,
      completedAt: FieldValue.serverTimestamp(),
      matchingDurationMs: Date.now() - started,
    },
    {merge: true},
  );
  gameLog(`matching completed ${roundId}`, {
    matchCount,
    unmatchedCount,
    durationMs: Date.now() - started,
  });
}

export const matchingGameHourlyTick = onSchedule(
  {
    schedule: "0 * * * *",
    timeZone: TIMEZONE,
    region: "europe-west1",
  },
  async () => {
    const now = new Date();
    const currentId = istanbulRoundId(now);
    const previousId = previousIstanbulRoundId(now);
    await ensureRoundOpen(currentId, now);
    if (previousId === currentId) return;
    const prev = await roundRef(previousId).get();
    if (!prev.exists) {
      gameLog(`no previous round ${previousId}`);
      return;
    }
    const status = String(prev.data()?.status ?? "");
    if (status === "OPEN" || status === "COLLECTING" || status === "LOCKED") {
      await runMatchingForRound(previousId);
    }
  },
);

function nextIstanbulHourMs(now: Date): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TIMEZONE,
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const bag: Record<string, string> = {};
  for (const p of parts) {
    if (p.type !== "literal") bag[p.type] = p.value;
  }
  const minute = Number(bag.minute ?? "0");
  const second = Number(bag.second ?? "0");
  const remainSec = (59 - minute) * 60 + (60 - second);
  return now.getTime() + remainSec * 1000;
}

export const getMatchingGameRound = onCall(callableOptions, async (request) => {
  requireUid(request);
  const now = new Date();
  const roundId = istanbulRoundId(now);
  const data = await ensureRoundOpen(roundId, now);
  const nextMs = nextIstanbulHourMs(now);
  return {
    roundId,
    status: data.status ?? "OPEN",
    timezone: TIMEZONE,
    serverNowMs: now.getTime(),
    nextRoundAtMs: nextMs,
    closesAtMs: nextMs,
  };
});

export const joinMatchingGameRound = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const roundId = String(request.data?.roundId ?? istanbulRoundId());
  const eligibility = await loadProfileEligibility(uid);
  if (eligibility.ok === false) {
    throw new HttpsError("failed-precondition", eligibility.reason);
  }
  await ensureRoundOpen(roundId, new Date());
  const status = String((await roundRef(roundId).get()).data()?.status ?? "OPEN");
  if (status !== "OPEN" && status !== "COLLECTING") {
    throw new HttpsError("failed-precondition", "round-closed");
  }
  const pref = participantRef(roundId, uid);
  const existing = await pref.get();
  if (existing.exists) {
    // Rejoin still counts as daily participation (idempotent per Istanbul day).
    await recordMatchingGameParticipation(uid, roundId);
    return {
      roundId,
      status: existing.data()?.status ?? "joined",
      alreadyJoined: true,
    };
  }
  await pref.set({
    userId: uid,
    roundId,
    status: "joined",
    joinedAt: FieldValue.serverTimestamp(),
    matched: false,
  });
  await roundRef(roundId).set(
    {participantCount: FieldValue.increment(1), status: "COLLECTING"},
    {merge: true},
  );
  await recordMatchingGameParticipation(uid, roundId);
  return {roundId, status: "joined", alreadyJoined: false};
});

export const submitMatchingGameAnswers = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const roundId = String(request.data?.roundId ?? "");
  const questionIds = Array.isArray(request.data?.questionIds)
    ? request.data.questionIds.map((v: unknown) => String(v))
    : [];
  const rawAnswers = (request.data?.answers ?? {}) as Record<string, unknown>;
  if (!roundId || questionIds.length === 0) {
    throw new HttpsError("invalid-argument", "invalid-payload");
  }
  const setId = setIdFor(questionIds);
  if (!setId) {
    throw new HttpsError("failed-precondition", "invalid-question-set");
  }
  const answers: AnswerMap = {};
  for (const qid of questionIds) {
    const aid =
      normalizeAnswerId(rawAnswers[qid]) ?? String(rawAnswers[qid] ?? "");
    if (!isValidRelationshipAnswer(qid, aid)) {
      throw new HttpsError("invalid-argument", "invalid-relationship-answer");
    }
    answers[qid] = aid;
  }

  const eligibility = await loadProfileEligibility(uid);
  if (eligibility.ok === false) {
    throw new HttpsError("failed-precondition", eligibility.reason);
  }

  const roundSnap = await roundRef(roundId).get();
  if (!roundSnap.exists) {
    throw new HttpsError("failed-precondition", "round-missing");
  }
  const status = String(roundSnap.data()?.status ?? "");
  if (status !== "OPEN" && status !== "COLLECTING") {
    throw new HttpsError("failed-precondition", "round-closed");
  }

  const pref = participantRef(roundId, uid);
  const existing = await pref.get();
  if (existing.exists && existing.data()?.status === "submitted") {
    return {roundId, status: "submitted", alreadySubmitted: true, setId};
  }

  await pref.set(
    {
      userId: uid,
      roundId,
      status: "submitted",
      setId,
      questionIds,
      answerSnapshot: answers,
      submittedAt: FieldValue.serverTimestamp(),
      joinedAt: existing.data()?.joinedAt ?? FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  if (!existing.exists) {
    await roundRef(roundId).set(
      {participantCount: FieldValue.increment(1), status: "COLLECTING"},
      {merge: true},
    );
  }
  await roundRef(roundId).set(
    {submittedCount: FieldValue.increment(1)},
    {merge: true},
  );

  const batch = db.batch();
  for (const [questionId, answerId] of Object.entries(answers)) {
    batch.set(
      db.doc(`users/${uid}/relationshipAnswers/${questionId}`),
      {questionId, answerId, answeredAt: FieldValue.serverTimestamp()},
      {merge: true},
    );
  }
  await batch.commit();

  return {roundId, status: "submitted", alreadySubmitted: false, setId};
});

export const getMatchingGameResult = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const roundId = String(request.data?.roundId ?? istanbulRoundId());
  const roundSnap = await roundRef(roundId).get();
  if (!roundSnap.exists) {
    return {roundId, roundStatus: "missing", participantStatus: null};
  }
  const roundStatus = String(roundSnap.data()?.status ?? "OPEN");
  const part = await participantRef(roundId, uid).get();
  if (!part.exists) {
    return {roundId, roundStatus, participantStatus: null};
  }
  const data = part.data() ?? {};
  let partner: {uid: string; displayName: string; photoUrl: string | null} | null =
    null;
  if (typeof data.partnerId === "string" && data.partnerId) {
    const preview = await profilePreview(data.partnerId);
    partner = {
      uid: data.partnerId,
      displayName: preview.name,
      photoUrl: preview.photoUrl,
    };
  }
  return {
    roundId,
    roundStatus,
    participantStatus: data.status ?? null,
    matchId: data.matchId ?? null,
    compatibilityScore: data.compatibilityScore ?? null,
    partner,
  };
});

export const runMatchingGameRoundNow = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const isEmu = process.env.FUNCTIONS_EMULATOR === "true";
  const isAdmin = request.auth?.token?.admin === true;
  if (!isEmu && !isAdmin) {
    throw new HttpsError("permission-denied", "admin-required");
  }
  const roundId = String(request.data?.roundId ?? istanbulRoundId());
  gameLog(`manual matching by ${uid} for ${roundId}`);
  await runMatchingForRound(roundId);
  const snap = await roundRef(roundId).get();
  return snap.data() ?? {roundId};
});
