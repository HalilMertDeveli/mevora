/**
 * Reusable Firebase security-rules test harness.
 *
 * Wraps @firebase/rules-unit-testing so every suite gets the same actor model,
 * the same deterministic setup/teardown, and behavioural (execute-the-rule)
 * allow/deny assertions instead of substring checks on the rules file.
 *
 * Actors:
 *   anon    unauthenticated visitor
 *   userA   owner / first match participant
 *   userB   second match participant
 *   userC   unrelated authenticated attacker
 *
 * Run from the repo root:
 *   npm --prefix firebase/tests run test:emulator
 */
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

const firebaseDir = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** Canonical UIDs. Every suite uses the same three so fixtures stay comparable. */
export const UID = Object.freeze({
  A: "user-a",
  B: "user-b",
  C: "user-c",
});

/** Match / block IDs are derived exactly as the product derives them. */
export const canonicalMatchId = (a, b) => [a, b].sort().join("_");
export const canonicalBlockId = (blockerId, blockedUserId) => `${blockerId}_${blockedUserId}`;

export const MATCH_AB = canonicalMatchId(UID.A, UID.B);

function hostPort(envVar, fallbackPort) {
  const raw = process.env[envVar];
  if (!raw) {
    process.env[envVar] = `127.0.0.1:${fallbackPort}`;
    return {host: "127.0.0.1", port: fallbackPort};
  }
  const [host, port] = String(raw).split(":");
  return {host: host || "127.0.0.1", port: Number(port || fallbackPort)};
}

/**
 * The project ID must match the one the emulators booted with. storage.rules
 * reaches into Firestore via firestore.exists(); that cross-service lookup is
 * resolved by the Storage emulator against its own project, so a test-only
 * projectId would silently read an empty database and deny every participant.
 */
export function emulatorProjectId() {
  return process.env.GCLOUD_PROJECT || process.env.FIREBASE_PROJECT || "mevora-rules-ci";
}

/**
 * Boots a rules test environment against the running emulators.
 * Rules are read from the real firebase/*.rules files, never a copy.
 */
export async function createSecurityEnv({projectId = emulatorProjectId(), storage = false} = {}) {
  const firestore = hostPort("FIRESTORE_EMULATOR_HOST", 8080);
  const config = {
    projectId,
    firestore: {
      rules: readFileSync(resolve(firebaseDir, "firestore.rules"), "utf8"),
      host: firestore.host,
      port: firestore.port,
    },
  };
  if (storage) {
    const bucket = hostPort("FIREBASE_STORAGE_EMULATOR_HOST", 9199);
    config.storage = {
      rules: readFileSync(resolve(firebaseDir, "storage.rules"), "utf8"),
      host: bucket.host,
      port: bucket.port,
    };
  }
  return initializeTestEnvironment(config);
}

/**
 * The four actors. `.db` / `.bucket` are lazily bound per call so a suite can
 * mix Firestore and Storage assertions without re-deriving contexts.
 */
export function actorsFor(env) {
  const build = (context, name) => ({
    name,
    db: () => context.firestore(),
    bucket: () => context.storage(),
  });
  return {
    anon: build(env.unauthenticatedContext(), "anonymous"),
    userA: build(env.authenticatedContext(UID.A), "userA"),
    userB: build(env.authenticatedContext(UID.B), "userB"),
    userC: build(env.authenticatedContext(UID.C), "userC"),
  };
}

/** Admin-privileged seeding. Rules are bypassed here on purpose. */
export async function seed(env, fn) {
  await env.withSecurityRulesDisabled(fn);
}

/** Deterministic isolation between suites. */
export async function resetState(env, {storage = false} = {}) {
  await env.clearFirestore();
  if (storage) {
    await env.clearStorage();
  }
}

/**
 * Behavioural assertions. These execute the rule against the emulator and
 * fail the test on the wrong outcome — they never inspect the rules text.
 */
export async function allow(op) {
  return assertSucceeds(typeof op === "function" ? op() : op);
}

export async function deny(op) {
  return assertFails(typeof op === "function" ? op() : op);
}

/**
 * Marks a probe that asserts the *correct* security behaviour while a verified
 * finding is still open. node:test reports these under `# todo` so the suite
 * stays runnable, the expectation stays honest, and the probe starts passing
 * the moment the finding is fixed (at which point drop the marker).
 *
 * Usage: it("...", knownFinding("B-01", "blocks doc ID unbound"), async () => {...})
 */
export function knownFinding(id, summary) {
  return {todo: `KNOWN FINDING ${id} — ${summary} (expected-security-behaviour probe; currently failing by design)`};
}

/** Bytes helper for Storage upload assertions. */
export function bytes(size, fill = 1) {
  return new Uint8Array(size).fill(fill);
}

/** A minimal, rules-valid E2EE message payload. */
export function encryptedMessage({senderId, receiverId, overrides = {}}) {
  return {
    senderId,
    receiverId,
    type: "text",
    encrypted: true,
    ciphertext: "Y2lwaGVydGV4dA==",
    nonce: "bm9uY2U=",
    mac: "bWFj",
    text: "",
    deleted: false,
    createdAt: new Date("2026-09-01T00:00:00Z"),
    ...overrides,
  };
}

/** An active A<->B match, shaped the way recordSwipe writes it. */
export function activeMatchAB(overrides = {}) {
  return {
    userIds: [UID.A, UID.B],
    createdAt: new Date("2026-09-01T00:00:00Z"),
    lastMessage: null,
    lastMessageAt: new Date("2026-09-01T00:00:00Z"),
    isActive: true,
    unmatchedBy: null,
    unmatchedAt: null,
    unreadCounts: {[UID.A]: 0, [UID.B]: 0},
    isNewFor: {[UID.A]: true, [UID.B]: true},
    participantNames: {[UID.A]: "Ada", [UID.B]: "Mina"},
    participantPhotos: {},
    participantVerified: {[UID.A]: false, [UID.B]: false},
    source: "mutual_like",
    ...overrides,
  };
}

/** A profile doc in its real post-onboarding state (lifecycle flags false). */
export function baseProfile(uid, overrides = {}) {
  return {
    uid,
    displayName: uid,
    bio: "",
    city: "Istanbul",
    interests: ["travel"],
    photos: [],
    isDiscoverable: false,
    profileCompleted: false,
    onboardingCompleted: false,
    isProfileComplete: false,
    ...overrides,
  };
}

/** An account doc in its real post-signup state. */
export function baseAccount(uid, overrides = {}) {
  return {
    uid,
    id: uid,
    isBanned: false,
    isSuspended: false,
    isVerified: false,
    phoneVerified: false,
    accountStatus: "active",
    ...overrides,
  };
}
