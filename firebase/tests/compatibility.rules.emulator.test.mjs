/**
 * Firestore emulator rules for match compatibility snapshot immutability.
 * Run from repo root:
 *   npx.cmd firebase emulators:exec --only firestore --project mevora-dev "npm --prefix firebase/tests test"
 */
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const rules = readFileSync(resolve(root, "firestore.rules"), "utf8");

const matchId = "user-a_user-b";
const baseMatch = {
  userIds: ["user-a", "user-b"],
  createdAt: new Date("2026-08-01T00:00:00Z"),
  lastMessage: null,
  lastMessageAt: new Date("2026-08-01T00:00:00Z"),
  isActive: true,
  unmatchedBy: null,
  unmatchedAt: null,
  unreadCounts: {"user-a": 0, "user-b": 0},
  isNewFor: {"user-a": true, "user-b": true},
  participantNames: {"user-a": "Ada", "user-b": "Mina"},
  participantPhotos: {},
  participantVerified: {"user-a": false, "user-b": false},
  source: "mutual_like",
  compatibilitySnapshots: {
    "user-a": {
      compatibilityScore: 94,
      compatibilityBreakdown: {
        overallScore: 94,
        relationshipScore: 100,
        interestScore: 80,
        lifestyleScore: 70,
        questionScore: null,
        musicScore: null,
        communicationScore: null,
      },
      sharedInterests: ["travel"],
      compatibilityReasons: ["Shared interests"],
    },
    "user-b": {
      compatibilityScore: 91,
      compatibilityBreakdown: {
        overallScore: 91,
        relationshipScore: 100,
        interestScore: 75,
        lifestyleScore: 70,
        questionScore: null,
        musicScore: null,
        communicationScore: null,
      },
      sharedInterests: ["travel"],
      compatibilityReasons: ["Shared interests"],
    },
  },
  compatibilityCalculatedAt: new Date("2026-08-01T00:00:01Z"),
};

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
  }

  const env = await initializeTestEnvironment({
    projectId: "mevora-rules-compat",
    firestore: {
      rules,
      host: "127.0.0.1",
      port: Number(String(process.env.FIRESTORE_EMULATOR_HOST).split(":")[1] || 8080),
    },
  });

  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc(`matches/${matchId}`).set(baseMatch);
    });

    const a = env.authenticatedContext("user-a").firestore();
    const b = env.authenticatedContext("user-b").firestore();
    const stranger = env.authenticatedContext("user-c").firestore();
    const anon = env.unauthenticatedContext().firestore();

    // Participant can read match + snapshot payload.
    const snapA = await assertSucceeds(a.doc(`matches/${matchId}`).get());
    const dataA = snapA.data();
    if (!dataA?.compatibilitySnapshots?.["user-a"]) {
      throw new Error("participant read missing compatibilitySnapshots");
    }
    await assertSucceeds(b.doc(`matches/${matchId}`).get());

    // Non-participant / unauthenticated cannot read.
    await assertFails(stranger.doc(`matches/${matchId}`).get());
    await assertFails(anon.doc(`matches/${matchId}`).get());

    // Client cannot create matches.
    await assertFails(
      a.doc("matches/user-a_user-c").set({
        ...baseMatch,
        userIds: ["user-a", "user-c"],
      }),
    );

    // Participant cannot mutate compatibilitySnapshots.
    await assertFails(
      a.doc(`matches/${matchId}`).update({
        compatibilitySnapshots: {
          "user-a": {
            ...baseMatch.compatibilitySnapshots["user-a"],
            compatibilityScore: 1,
          },
          "user-b": baseMatch.compatibilitySnapshots["user-b"],
        },
      }),
    );

    // Participant cannot mutate compatibilityCalculatedAt.
    await assertFails(
      a.doc(`matches/${matchId}`).update({
        compatibilityCalculatedAt: new Date("2099-01-01T00:00:00Z"),
      }),
    );

    // Participant cannot inject legacy top-level compatibilityScore.
    await assertFails(
      a.doc(`matches/${matchId}`).update({
        compatibilityScore: 99,
      }),
    );

    // Allowed participant chat-side update still works (lastMessage / unread).
    await assertSucceeds(
      a.doc(`matches/${matchId}`).update({
        lastMessage: "Merhaba",
        lastMessageAt: new Date("2026-08-01T00:05:00Z"),
        "unreadCounts.user-b": 1,
        "isNewFor.user-a": false,
      }),
    );

    console.log("compatibility.rules.emulator.ok");
  } finally {
    await env.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
