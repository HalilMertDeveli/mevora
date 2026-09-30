#!/usr/bin/env node
/**
 * End-to-end smoke of the finite daily Picks batch against the Firebase
 * Emulator Suite, signed in as the QA users — the same callables the app uses.
 *
 * Needs the emulators running with the QA users and the Picks pool seeded:
 *   node tool/seedEmulatorQaUsers.cjs
 *   node tool/seedEmulatorPicksPool.cjs
 *   node tool/picksEmulatorSmoke.cjs
 * with FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST set, and
 * FUNCTIONS_EMULATOR_HOST (default 127.0.0.1:5001) for the callables.
 *
 * It changes QA data (a pass, a block, batches), so reseed the pool before
 * testing by hand. It never touches production: every host must be local.
 */
const path = require("node:path");
const assert = require("node:assert/strict");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";
const REGION = "europe-west1";
const hosts = {
  FIRESTORE_EMULATOR_HOST: process.env.FIRESTORE_EMULATOR_HOST,
  FIREBASE_AUTH_EMULATOR_HOST: process.env.FIREBASE_AUTH_EMULATOR_HOST,
  FUNCTIONS_EMULATOR_HOST: process.env.FUNCTIONS_EMULATOR_HOST || "127.0.0.1:5001",
};
for (const [name, value] of Object.entries(hosts)) {
  if (!value || !/^(127\.0\.0\.1|localhost|0\.0\.0\.0):\d+$/.test(value)) {
    console.error(`REFUSING TO RUN: ${name} must point at a local emulator (got "${value ?? ""}").`);
    process.exit(1);
  }
}

const fromFunctions = createRequire(path.join(__dirname, "..", "functions", "package.json"));
const admin = fromFunctions("firebase-admin");
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const PASSWORD = process.env.QA_PASSWORD || "MevoraQa!2026";

async function signIn(email) {
  const res = await fetch(
    `http://${hosts.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`,
    {method: "POST", headers: {"Content-Type": "application/json"}, body: JSON.stringify({email, password: PASSWORD, returnSecureToken: true})},
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`sign-in ${email}: ${JSON.stringify(json)}`);
  return json.idToken;
}

async function call(token, name, data = {}) {
  const res = await fetch(`http://${hosts.FUNCTIONS_EMULATOR_HOST}/${PROJECT}/${REGION}/${name}`, {
    method: "POST",
    headers: {"Content-Type": "application/json", Authorization: `Bearer ${token}`},
    body: JSON.stringify({data}),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status} ${JSON.stringify(json)}`);
  return json.result;
}

const results = [];
async function check(name, fn) {
  try {
    await fn();
    results.push(["PASS", name]);
  } catch (error) {
    results.push(["FAIL", name, error.message]);
  }
}

(async () => {
  const a = await signIn("qa_user_a@mevora.test");
  const b = await signIn("qa_user_b@mevora.test");
  const uidsOf = (result) => result.picks.map((item) => item.uid);
  let first;

  await check("two concurrent first opens share one generation", async () => {
    const [x, y] = await Promise.all([call(a, "getMevoraPicks"), call(a, "getMevoraPicks")]);
    assert.equal(x.generationId, y.generationId);
    assert.deepEqual(uidsOf(x), uidsOf(y));
    first = x;
  });
  await check("the day holds exactly the target (10 by default)", async () => {
    assert.equal(first.targetCount, 10);
    assert.equal(first.picks.length, first.targetCount, `status ${first.status}`);
    assert.equal(first.status, "ready");
  });
  await check("no weak (below the floor) or out-of-range candidate is picked", async () => {
    assert.equal(uidsOf(first).some((uid) => /_weak_|_berlin_/.test(uid)), false, uidsOf(first).join(","));
  });
  await check("reopening keeps the generation and the order", async () => {
    const again = await call(a, "getMevoraPicks");
    assert.equal(again.generationId, first.generationId);
    assert.deepEqual(uidsOf(again), uidsOf(first));
  });
  await check("a pass removes the Pick and brings nobody new", async () => {
    const passed = uidsOf(first)[0];
    await call(a, "recordDiscoveryDecision", {candidateUid: passed, action: "pass"});
    const after = await call(a, "getMevoraPicks");
    assert.deepEqual(uidsOf(after), uidsOf(first).slice(1));
  });
  await check("a block hides the Pick immediately", async () => {
    const blocked = uidsOf(first)[1];
    await call(a, "blockUser", {userId: blocked});
    const after = await call(a, "getMevoraPicks");
    assert.equal(uidsOf(after).includes(blocked), false);
  });
  await check("another account gets its own batch", async () => {
    const other = await call(b, "getMevoraPicks");
    assert.notEqual(other.generationId, first.generationId);
    assert.equal(uidsOf(other).some((uid) => uid.startsWith("qa_pick_male_")), false, "B seeks women");
  });
  await check("the open-ended deck is refused", async () => {
    await assert.rejects(() => call(a, "getDiscoveryCandidates", {limit: 20}), /discovery-deck-retired/);
  });
  await check("a new Istanbul day brings a new batch without yesterday's undecided people", async () => {
    await db.doc("users/qa_user_a/mevoraPicks/current").update({refreshAtMs: Date.now() - 1});
    const next = await call(a, "getMevoraPicks");
    assert.notEqual(next.generationId, first.generationId);
    const yesterday = new Set(uidsOf(first));
    assert.equal(uidsOf(next).some((uid) => yesterday.has(uid)), false);
  });

  for (const [verdict, name, detail] of results) {
    console.log(`${verdict}  ${name}${detail ? `\n      ${detail}` : ""}`);
  }
  const failed = results.filter(([verdict]) => verdict === "FAIL").length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
})().catch((error) => {
  console.error("SMOKE FAILED:", error);
  process.exit(1);
});
