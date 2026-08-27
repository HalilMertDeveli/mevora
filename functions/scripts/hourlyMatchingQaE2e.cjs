/**
 * Admin QA harness for hourly matching (no App Check / client).
 * Creates QA_HOUR_* users, seeds a round, runs matching via Admin + engine,
 * verifies A↔B, then optionally cleans up.
 *
 * Usage (from functions/):
 *   node scripts/hourlyMatchingQaE2e.cjs [--cleanup]
 */
const admin = require("firebase-admin");
const {
  istanbulRoundId,
  optimizeMatches,
} = require("../lib/hourlyMatchingGameEngine.js");

const PROJECT = "mevora-d6ed0";
const ROUND_COLLECTION = "matchingGameRounds";
const QA_PREFIX = "qa_hour_";

if (admin.apps.length === 0) {
  admin.initializeApp({projectId: PROJECT});
}
const db = admin.firestore();
const auth = admin.auth();

const answersAbc = {rq_001: "a", rq_002: "b", rq_003: "c"};

async function ensureQaUser(label) {
  const email = `${QA_PREFIX}${label}@mevora-qa.test`;
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch {
    user = await auth.createUser({
      email,
      password: `QaHourly_${label}_2026!`,
      displayName: `QA_HOUR_${label.toUpperCase()}`,
      emailVerified: true,
    });
  }
  const uid = user.uid;
  await db.doc(`users/${uid}`).set(
    {
      email,
      displayName: `QA_HOUR_${label.toUpperCase()}`,
      isQaUser: true,
      qaTag: "hourly-matching-game",
      profileCompleted: true,
      onboardingCompleted: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`profiles/${uid}`).set(
    {
      displayName: `QA_HOUR_${label.toUpperCase()}`,
      profileCompleted: true,
      onboardingCompleted: true,
      isProfileComplete: true,
      isQaUser: true,
      gender: label === "a" ? "man" : "woman",
      photos: [],
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return {uid, email, label};
}

async function seedParticipant(roundId, uid, answers) {
  await db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${uid}`).set(
    {
      userId: uid,
      roundId,
      status: "submitted",
      questionIds: Object.keys(answers),
      answerSnapshot: answers,
      setId: "qa-set",
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      submittedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

async function runAdminMatching(roundId) {
  const ref = db.doc(`${ROUND_COLLECTION}/${roundId}`);
  await ref.set(
    {
      roundId,
      status: "MATCHING",
      timezone: "Europe/Istanbul",
      qa: true,
      lockedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  const parts = await ref.collection("participants").where("status", "==", "submitted").get();
  const participants = parts.docs.map((d) => ({
    uid: d.id,
    answers: d.data().answerSnapshot || {},
  }));
  const pairs = optimizeMatches({participants, topK: 20});
  const matched = new Set();
  for (const pair of pairs) {
    matched.add(pair.userA);
    matched.add(pair.userB);
    const matchId = [pair.userA, pair.userB].sort().join("_");
    await ref.collection("matches").doc(matchId).set({
      matchId,
      userIds: [pair.userA, pair.userB],
      score: pair.score,
      exactAligned: pair.exactAligned,
      roundId,
      qa: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await Promise.all([
      db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${pair.userA}`).set(
        {
          status: "matched",
          matchId,
          partnerId: pair.userB,
          compatibilityScore: pair.score,
        },
        {merge: true},
      ),
      db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${pair.userB}`).set(
        {
          status: "matched",
          matchId,
          partnerId: pair.userA,
          compatibilityScore: pair.score,
        },
        {merge: true},
      ),
    ]);
  }
  await ref.set(
    {
      status: "COMPLETED",
      matchCount: pairs.length,
      unmatchedCount: participants.length - matched.size,
      submittedCount: participants.length,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return {pairs, participantCount: participants.length};
}

async function cleanup(users, roundId) {
  for (const u of users) {
    await db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${u.uid}`).delete().catch(() => {});
    // Keep auth users unless --cleanup-users
  }
  const matches = await db.collection(`${ROUND_COLLECTION}/${roundId}/matches`).get();
  for (const d of matches.docs) {
    await d.ref.delete();
  }
  await db.doc(`${ROUND_COLLECTION}/${roundId}`).delete().catch(() => {});
}

async function main() {
  const doCleanup = process.argv.includes("--cleanup");
  const now = new Date();
  const roundId = `qa_${istanbulRoundId(now)}`;
  console.log(JSON.stringify({step: "start", project: PROJECT, roundId}));

  const a = await ensureQaUser("a");
  const b = await ensureQaUser("b");
  console.log(JSON.stringify({step: "users", a: a.uid, b: b.uid}));

  await db.doc(`${ROUND_COLLECTION}/${roundId}`).set(
    {
      roundId,
      status: "OPEN",
      timezone: "Europe/Istanbul",
      qa: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      participantCount: 2,
      submittedCount: 2,
    },
    {merge: true},
  );
  await seedParticipant(roundId, a.uid, answersAbc);
  await seedParticipant(roundId, b.uid, answersAbc);

  const result = await runAdminMatching(roundId);
  console.log(JSON.stringify({step: "matching", ...result}));

  const partA = await db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${a.uid}`).get();
  const partB = await db.doc(`${ROUND_COLLECTION}/${roundId}/participants/${b.uid}`).get();
  const dataA = partA.data() || {};
  const dataB = partB.data() || {};
  const ok =
    dataA.status === "matched" &&
    dataB.status === "matched" &&
    dataA.partnerId === b.uid &&
    dataB.partnerId === a.uid &&
    dataA.compatibilityScore === 100 &&
    dataB.compatibilityScore === 100 &&
    dataA.matchId === dataB.matchId;

  console.log(
    JSON.stringify({
      step: "verify",
      ok,
      a: {status: dataA.status, partnerId: dataA.partnerId, score: dataA.compatibilityScore},
      b: {status: dataB.status, partnerId: dataB.partnerId, score: dataB.compatibilityScore},
      matchId: dataA.matchId,
    }),
  );

  if (doCleanup) {
    await cleanup([a, b], roundId);
    console.log(JSON.stringify({step: "cleanup", roundId}));
  }

  if (!ok) {
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
