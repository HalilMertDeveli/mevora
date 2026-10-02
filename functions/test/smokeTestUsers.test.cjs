const {after, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * The smoke-test callables take no Firebase auth: a shared secret is their
 * gate. They used to be exported to every deploy, and to create
 * email-verified accounts whose password was a template written in this
 * repository, so anyone who could read the source could sign in as a smoke
 * user on any project where the pair existed.
 *
 * They are emulator-only now (not exported to a deploy, and refusing outside
 * the emulator process — both pinned in productionSurface.test.cjs), so every
 * test here runs as the emulator process.
 *
 * What is pinned here:
 * - the password is random per run, never the old template, and only ever
 *   leaves the server in the response to the caller who presented the secret;
 * - running prepare again replaces the password and ends existing sessions;
 * - a wrong, empty or non-string secret is refused, and so is every call
 *   while the secret is not configured at all.
 */
const SECRET = "correct-horse-battery-staple-smoke";
const EMAIL_A = "smoke-a@mevora.test";
const EMAIL_B = "smoke-b@mevora.test";
const OLD_TEMPLATE = (label) => `Smoke!${label}9Mevora`;

// smokeTestUsers.js binds getFirestore() at load and asks for getAuth() per
// call, so the in-memory doubles go in first.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

/** Just enough of the Admin Auth client for the two smoke callables. */
function createFakeAuth() {
  const byUid = new Map();
  let seq = 0;
  const notFound = () => {
    const error = new Error("no user record");
    error.code = "auth/user-not-found";
    return error;
  };
  return {
    byUid,
    revoked: [],
    byEmail(email) {
      return [...byUid.values()].find((user) => user.email === email) ?? null;
    },
    async getUserByEmail(email) {
      const user = this.byEmail(email);
      if (!user) throw notFound();
      return {...user};
    },
    async createUser(properties) {
      seq += 1;
      const user = {uid: `smoke-uid-${seq}`, ...properties};
      byUid.set(user.uid, user);
      return {...user};
    },
    async updateUser(uid, properties) {
      const user = byUid.get(uid);
      if (!user) throw notFound();
      Object.assign(user, properties);
      return {...user};
    },
    async revokeRefreshTokens(uid) {
      if (!byUid.has(uid)) throw notFound();
      this.revoked.push(uid);
    },
    async deleteUser(uid) {
      if (!byUid.has(uid)) throw notFound();
      byUid.delete(uid);
    },
  };
}

let auth = createFakeAuth();
require("firebase-admin/auth").getAuth = () => auth;

const {
  cleanupSmokeTestUsers,
  prepareSmokeTestUsers,
  smokeSecretMatches,
} = require("../lib/smoke/smokeTestUsers.js");

async function rejectsWith(promise, code, message) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  });
}

const prepare = (data) => callAs(prepareSmokeTestUsers, null, data);
const cleanup = (data) => callAs(cleanupSmokeTestUsers, null, data);

const savedEmulatorFlag = process.env.FUNCTIONS_EMULATOR;
beforeEach(() => {
  auth = createFakeAuth();
  process.env.SMOKE_TEST_SECRET = SECRET;
  process.env.FUNCTIONS_EMULATOR = "true";
});
after(() => {
  if (savedEmulatorFlag === undefined) delete process.env.FUNCTIONS_EMULATOR;
  else process.env.FUNCTIONS_EMULATOR = savedEmulatorFlag;
});

describe("smoke callables: the shared secret", () => {
  it("refuses every call while the secret is not configured", async () => {
    delete process.env.SMOKE_TEST_SECRET;
    for (const secret of [undefined, "", "undefined", SECRET]) {
      const data = secret === undefined ? {} : {secret};
      await rejectsWith(prepare(data), "failed-precondition", "smoke-secret-not-configured");
      await rejectsWith(cleanup(data), "failed-precondition", "smoke-secret-not-configured");
    }
    assert.equal(auth.byUid.size, 0);
  });

  it("treats an empty configured secret as not configured", async () => {
    process.env.SMOKE_TEST_SECRET = "";
    await rejectsWith(prepare({secret: ""}), "failed-precondition", "smoke-secret-not-configured");
    await rejectsWith(prepare({}), "failed-precondition", "smoke-secret-not-configured");
    assert.equal(auth.byUid.size, 0);
  });

  it("refuses a wrong, empty, partial or non-string secret", async () => {
    const wrong = [
      undefined,
      "",
      "wrong",
      SECRET.slice(0, -1),
      `${SECRET}x`,
      SECRET.toUpperCase(),
      [SECRET],
      {toString: () => SECRET},
      0,
      true,
    ];
    for (const secret of wrong) {
      const data = secret === undefined ? {} : {secret};
      await rejectsWith(prepare(data), "permission-denied", "smoke-secret-invalid");
      await rejectsWith(cleanup(data), "permission-denied", "smoke-secret-invalid");
    }
    await rejectsWith(callAs(prepareSmokeTestUsers, null, null), "permission-denied", "smoke-secret-invalid");
    assert.equal(auth.byUid.size, 0);
  });

  it("compares secrets of any length without throwing", () => {
    assert.equal(smokeSecretMatches(SECRET, SECRET), true);
    assert.equal(smokeSecretMatches("a", SECRET), false);
    assert.equal(smokeSecretMatches(`${SECRET}${SECRET}`, SECRET), false);
    assert.equal(smokeSecretMatches("", SECRET), false);
    assert.equal(smokeSecretMatches("", ""), false);
    assert.equal(smokeSecretMatches(undefined, SECRET), false);
    assert.equal(smokeSecretMatches(null, SECRET), false);
  });
});

describe("prepareSmokeTestUsers: passwords", () => {
  it("returns what the caller needs to sign in as each smoke user", async () => {
    const result = await prepare({secret: SECRET});

    const userA = auth.byEmail(EMAIL_A);
    const userB = auth.byEmail(EMAIL_B);
    assert.deepEqual(Object.keys(result).sort(), ["emails", "ok", "passwords", "smokeUserA", "smokeUserB"]);
    assert.equal(result.ok, true);
    assert.equal(result.smokeUserA, userA.uid);
    assert.equal(result.smokeUserB, userB.uid);
    assert.deepEqual(result.emails, {a: EMAIL_A, b: EMAIL_B});
    assert.deepEqual(Object.keys(result.passwords).sort(), ["a", "b"]);
    // The returned password is the one Auth now holds.
    assert.equal(result.passwords.a, userA.password);
    assert.equal(result.passwords.b, userB.password);
    assert.equal(userA.emailVerified, true);
    assert.equal(userB.emailVerified, true);
  });

  it("never issues the template password that used to be in the repository", async () => {
    const result = await prepare({secret: SECRET});

    assert.notEqual(result.passwords.a, OLD_TEMPLATE("A"));
    assert.notEqual(result.passwords.b, OLD_TEMPLATE("B"));
    assert.notEqual(result.passwords.a, result.passwords.b);
    for (const password of Object.values(result.passwords)) {
      assert.equal(typeof password, "string");
      // 32 random bytes, base64url: far beyond guessing, and not derived from
      // the label, the email or the secret.
      assert.ok(password.length >= 43, `password too short: ${password.length}`);
      assert.ok(!password.includes(SECRET));
      assert.ok(!/Mevora|Smoke/i.test(password));
    }
  });

  it("issues a different password on every run", async () => {
    const seen = new Set();
    for (let run = 0; run < 5; run += 1) {
      const result = await prepare({secret: SECRET});
      seen.add(result.passwords.a);
      seen.add(result.passwords.b);
    }
    assert.equal(seen.size, 10);
  });

  it("rotates the password of smoke users that already exist", async () => {
    const first = await prepare({secret: SECRET});
    const second = await prepare({secret: SECRET});

    // Same accounts, new credentials.
    assert.equal(second.smokeUserA, first.smokeUserA);
    assert.equal(second.smokeUserB, first.smokeUserB);
    assert.equal(auth.byUid.size, 2);
    assert.notEqual(second.passwords.a, first.passwords.a);
    assert.notEqual(second.passwords.b, first.passwords.b);
    // The old one stops working: Auth holds only the new password...
    assert.equal(auth.byEmail(EMAIL_A).password, second.passwords.a);
    assert.equal(auth.byEmail(EMAIL_B).password, second.passwords.b);
    // ...and sessions opened with the old one are ended.
    assert.deepEqual(auth.revoked, [first.smokeUserA, first.smokeUserB]);
  });

  it("replaces a template password left by an earlier deploy", async () => {
    const legacy = await auth.createUser({
      email: EMAIL_A,
      emailVerified: true,
      password: OLD_TEMPLATE("A"),
    });

    const result = await prepare({secret: SECRET});

    assert.equal(result.smokeUserA, legacy.uid);
    assert.notEqual(auth.byUid.get(legacy.uid).password, OLD_TEMPLATE("A"));
    assert.equal(auth.byUid.get(legacy.uid).password, result.passwords.a);
    assert.deepEqual(auth.revoked, [legacy.uid]);
  });

  it("keeps smoke accounts flagged, and stores no password", async () => {
    const result = await prepare({secret: SECRET});

    for (const [uid, password] of [
      [result.smokeUserA, result.passwords.a],
      [result.smokeUserB, result.passwords.b],
    ]) {
      const account = (await db.doc(`users/${uid}`).get()).data();
      assert.equal(account.isSmokeTestUser, true);
      assert.ok(!JSON.stringify(account).includes(password));
    }
  });
});

describe("cleanupSmokeTestUsers", () => {
  it("removes the smoke users for a caller with the secret", async () => {
    const prepared = await prepare({secret: SECRET});

    const result = await cleanup({secret: SECRET});

    assert.equal(result.ok, true);
    assert.deepEqual([...result.deleted].sort(), [prepared.smokeUserA, prepared.smokeUserB].sort());
    assert.equal(auth.byUid.size, 0);
    assert.equal((await db.doc(`users/${prepared.smokeUserA}`).get()).exists, false);
  });
});

describe("smoke tooling holds no password in source", () => {
  const repoRoot = path.join(__dirname, "..", "..");
  const sources = [
    "functions/src/smoke/smokeTestUsers.ts",
    "tools/smoke/lib/helpers.mjs",
    "tools/smoke/run_smoke_test.mjs",
    "docs/SMOKE_TEST.md",
  ];

  for (const relative of sources) {
    it(`${relative} has no literal or templated password`, () => {
      const source = fs.readFileSync(path.join(repoRoot, relative), "utf8");
      assert.ok(!source.includes("9Mevora"), "the old password template is still present");
      assert.doesNotMatch(source, /password:\s*[`'"]/);
    });
  }
});
