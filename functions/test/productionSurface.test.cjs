/**
 * What a DEPLOYED backend exposes, as opposed to the emulator.
 *
 * Test and QA surface may live in the repository, but it must not exist in a
 * deployed backend, and production fails closed. `FUNCTIONS_EMULATOR` is the
 * one switch: the Functions emulator sets it to "true" for discovery and for
 * every invocation, and neither `firebase deploy` nor a deployed function ever
 * has it. Each block below pins one thing on both sides of that switch:
 *
 * 1. the entry point exports the emulator-only callables to the emulator and
 *    to nothing else, and a deploy does not even load the smoke module;
 * 2. the smoke callables refuse outside the emulator, whatever secret is sent;
 * 3. a smoke-flagged account gets no fast path through photo moderation there;
 * 4. a draft Humor Core sequence is handed out by the emulator only;
 * 5. relationship matching writes nothing about a pair to the logs;
 * 6. purchase verifier logs never carry the request URL or the token;
 * 7. the smoke harness refuses to run against anything but local emulators.
 */
const {afterEach, before, beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {pathToFileURL} = require("node:url");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const FUNCTIONS_DIR = path.join(__dirname, "..");
const REPO_ROOT = path.join(FUNCTIONS_DIR, "..");

const EMULATOR_ONLY = [
  "cleanupSmokeTestUsers",
  "debugPersonalizationRanking",
  "prepareSmokeTestUsers",
  "searchHumorProviderCandidates",
];
/** What a process that is not the emulator can have in the variable. */
const NOT_THE_EMULATOR = [undefined, "", "false", "1", "TRUE", "yes"];

// The callable modules bind getFirestore() / getAuth() at load, so the doubles
// go in first. Nothing below can reach a network or a real project.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const savedEmulatorFlag = process.env.FUNCTIONS_EMULATOR;
function runAs(flag) {
  if (flag === undefined) delete process.env.FUNCTIONS_EMULATOR;
  else process.env.FUNCTIONS_EMULATOR = flag;
}
const asEmulator = () => runAs("true");
const asDeployed = () => runAs(undefined);
afterEach(() => runAs(savedEmulatorFlag));

/** Runs [fn] with every logger level and console.log captured. */
async function capturingLogs(fn) {
  const {logger} = require("firebase-functions");
  const levels = ["debug", "info", "log", "warn", "error"];
  const savedLogger = Object.fromEntries(levels.map((level) => [level, logger[level]]));
  const savedConsoleLog = console.log;
  const lines = [];
  for (const level of levels) {
    logger[level] = (...args) => lines.push({level, args});
  }
  console.log = (...args) => lines.push({level: "console.log", args});
  try {
    await fn();
  } finally {
    Object.assign(logger, savedLogger);
    console.log = savedConsoleLog;
  }
  return lines;
}

// ---------------------------------------------------------------------------
// 1. The entry point
// ---------------------------------------------------------------------------

/**
 * Loads `lib/index.js` in a fresh process the way Firebase does to find out
 * what to deploy (it enumerates the module's exports), with FUNCTIONS_EMULATOR
 * set to [flag] or absent.
 */
function loadEntryPoint(flag) {
  const env = {
    ...process.env,
    GCLOUD_PROJECT: "demo-production-surface",
    FIREBASE_CONFIG: JSON.stringify({
      projectId: "demo-production-surface",
      storageBucket: "demo-production-surface.appspot.com",
    }),
  };
  delete env.FUNCTIONS_EMULATOR;
  if (flag !== undefined) env.FUNCTIONS_EMULATOR = flag;
  const marker = "@@production-surface@@";
  const script = `
    const entry = require(${JSON.stringify(path.join(FUNCTIONS_DIR, "lib", "index.js"))});
    const {declaredParams} = require("firebase-functions/params");
    const loaded = (suffix) => Object.keys(require.cache).some((file) => file.replace(/\\\\/g, "/").endsWith(suffix));
    process.stdout.write(${JSON.stringify(marker)} + JSON.stringify({
      exports: Object.keys(entry),
      params: declaredParams.map((param) => param.name),
      smokeModuleLoaded: loaded("/lib/smoke/smokeTestUsers.js"),
      emulatorOnlyModuleLoaded: loaded("/lib/emulatorOnly.js"),
    }));
  `;
  const result = spawnSync(process.execPath, ["-e", script], {
    cwd: FUNCTIONS_DIR,
    env,
    encoding: "utf8",
  });
  assert.equal(result.status, 0, `the entry point failed to load:\n${result.stderr}`);
  return JSON.parse(result.stdout.slice(result.stdout.lastIndexOf(marker) + marker.length));
}

describe("entry point: emulator-only callables", () => {
  let deployed;
  let emulator;
  before(() => {
    deployed = loadEntryPoint(undefined);
    emulator = loadEntryPoint("true");
  });

  it("a deploy-style load exports none of them", () => {
    for (const name of EMULATOR_ONLY) {
      assert.equal(deployed.exports.includes(name), false, `${name} would be deployed`);
    }
    // Not vacuous: the real surface is there.
    assert.ok(deployed.exports.length > 100, `only ${deployed.exports.length} exports`);
    for (const name of ["getHumorFeed", "resetMyPersonalization", "getDiscoveryCandidates"]) {
      assert.ok(deployed.exports.includes(name), `${name} is missing from the deploy surface`);
    }
  });

  it("a deploy-style load does not load the smoke module or declare its secret", () => {
    assert.equal(deployed.emulatorOnlyModuleLoaded, false);
    assert.equal(deployed.smokeModuleLoaded, false);
    // A declared secret is a deploy requirement even when no function uses it.
    assert.equal(deployed.params.includes("SMOKE_TEST_SECRET"), false);
  });

  it("only the exact value \"true\" opens the gate", () => {
    for (const flag of NOT_THE_EMULATOR.filter((value) => value !== undefined)) {
      const surface = loadEntryPoint(flag);
      assert.deepEqual(
        surface.exports.filter((name) => EMULATOR_ONLY.includes(name)),
        [],
        `FUNCTIONS_EMULATOR=${JSON.stringify(flag)} exported emulator-only callables`,
      );
      assert.equal(surface.smokeModuleLoaded, false);
    }
  });

  it("the emulator gets all four, and nothing else changes", () => {
    const added = emulator.exports.filter((name) => !deployed.exports.includes(name)).sort();
    assert.deepEqual(added, EMULATOR_ONLY);
    assert.deepEqual(
      deployed.exports.filter((name) => !emulator.exports.includes(name)),
      [],
    );
    assert.equal(emulator.smokeModuleLoaded, true);
    assert.ok(emulator.params.includes("SMOKE_TEST_SECRET"));
  });

  it("index.ts reaches the emulator-only module through the gate alone", () => {
    const entry = fs.readFileSync(path.join(FUNCTIONS_DIR, "src", "index.ts"), "utf8");
    for (const name of EMULATOR_ONLY) {
      assert.equal(entry.includes(name), false, `index.ts names ${name}`);
    }
    assert.equal(/from\s+["']\.\/emulatorOnly/.test(entry), false, "a static import is not lazy");
    assert.match(
      entry,
      /if \(process\.env\.FUNCTIONS_EMULATOR === "true"\) \{\s*Object\.assign\(exports, require\("\.\/emulatorOnly\.js"\)\);\s*\}/,
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Smoke callables
// ---------------------------------------------------------------------------

describe("smoke callables outside the emulator process", () => {
  const SECRET = "production-surface-smoke-secret";
  const {cleanupSmokeTestUsers, prepareSmokeTestUsers} = require("../lib/smoke/smokeTestUsers.js");
  let created;
  let savedGetAuth;
  let savedSecret;

  beforeEach(() => {
    created = [];
    db.reset({});
    savedSecret = process.env.SMOKE_TEST_SECRET;
    process.env.SMOKE_TEST_SECRET = SECRET;
    savedGetAuth = require("firebase-admin/auth").getAuth;
    const notFound = () => Object.assign(new Error("no user record"), {code: "auth/user-not-found"});
    require("firebase-admin/auth").getAuth = () => ({
      async getUserByEmail() {
        throw notFound();
      },
      async createUser(properties) {
        created.push(properties.email);
        return {uid: `smoke-uid-${created.length}`, ...properties};
      },
      async deleteUser() {},
    });
  });
  afterEach(() => {
    require("firebase-admin/auth").getAuth = savedGetAuth;
    if (savedSecret === undefined) delete process.env.SMOKE_TEST_SECRET;
    else process.env.SMOKE_TEST_SECRET = savedSecret;
  });

  const emulatorOnly = (error) => {
    assert.equal(error.code, "failed-precondition");
    assert.equal(error.message, "emulator-only");
    return true;
  };

  it("refuse even with the right secret, and create nothing", async () => {
    for (const flag of NOT_THE_EMULATOR) {
      runAs(flag);
      await assert.rejects(callAs(prepareSmokeTestUsers, null, {secret: SECRET}), emulatorOnly);
      await assert.rejects(callAs(cleanupSmokeTestUsers, null, {secret: SECRET}), emulatorOnly);
    }
    assert.deepEqual(created, []);
    assert.deepEqual(db.paths(), []);
  });

  it("refuse before the secret is looked at", async () => {
    asDeployed();
    // The same answer for a wrong secret, no secret and an unconfigured one:
    // a live copy gives nothing away about the secret.
    await assert.rejects(callAs(prepareSmokeTestUsers, null, {secret: "wrong"}), emulatorOnly);
    await assert.rejects(callAs(prepareSmokeTestUsers, null, {}), emulatorOnly);
    delete process.env.SMOKE_TEST_SECRET;
    await assert.rejects(callAs(prepareSmokeTestUsers, null, {secret: SECRET}), emulatorOnly);
  });

  it("still work inside the emulator process", async () => {
    asEmulator();
    const result = await callAs(prepareSmokeTestUsers, null, {secret: SECRET});
    assert.equal(result.ok, true);
    assert.equal(created.length, 2);
  });
});

// ---------------------------------------------------------------------------
// 3. Photo moderation
// ---------------------------------------------------------------------------

describe("smoke-flagged account: photo fast path", () => {
  const {processPendingProfilePhoto} = require("../lib/moderation/photoModerationService.js");
  const {JPEG, createFaceAnchorWorld} = require("./helpers/faceAnchorHarness.cjs");
  const UID = "member-1";

  /** A smoke-flagged account uploads bytes that are an image in name only. */
  async function upload(imageId) {
    const w = createFaceAnchorWorld();
    await w.db.doc(`users/${UID}`).set({isSmokeTestUser: true}, {merge: true});
    const pendingPath = `users/${UID}/profile/pending/${imageId}.jpg`;
    const bytes = JPEG(imageId);
    w.bucket.put(pendingPath, bytes);
    w.db.resetStats();
    const status = await processPendingProfilePhoto({
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId,
      pendingPath,
      contentType: "image/jpeg",
      sizeBytes: bytes.length,
    });
    return {w, status};
  }

  it("does not apply in a deployed backend: the upload is checked like anyone's", async () => {
    for (const flag of NOT_THE_EMULATOR) {
      runAs(flag);
      const {w, status} = await upload("fresh");
      // The fixture has no readable dimensions, so the real checks hold it.
      assert.equal(status, "manual_review");
      assert.equal(w.ledger("fresh").status, "manual_review");
      assert.notEqual(w.ledger("fresh").reason, "smoke-test-fast-path");
      // The flag is not even read there.
      assert.equal(w.db.stats().byPath.get(`users/${UID}`), undefined);
    }
  });

  it("applies inside the emulator process", async () => {
    asEmulator();
    const {w, status} = await upload("fresh");
    assert.equal(status, "approved");
    assert.equal(w.ledger("fresh").status, "approved");
  });

  it("is only for flagged accounts, in the emulator too", async () => {
    asEmulator();
    const w = createFaceAnchorWorld();
    const pendingPath = `users/${UID}/profile/pending/plain.jpg`;
    const bytes = JPEG("plain");
    w.bucket.put(pendingPath, bytes);
    const status = await processPendingProfilePhoto({
      db: w.db,
      bucket: w.bucket,
      uid: UID,
      imageId: "plain",
      pendingPath,
      contentType: "image/jpeg",
      sizeBytes: bytes.length,
    });
    assert.equal(status, "manual_review");
  });
});

// ---------------------------------------------------------------------------
// 4. Humor Core
// ---------------------------------------------------------------------------

describe("Humor Core: a draft sequence is served by the emulator only", () => {
  const humor = require("../lib/humor/index.js");
  const core = require("../lib/humor/coreService.js");
  const {seedCalibrationCatalog} = require("../lib/humor/calibrationCatalog.js");
  const {DAILY_DEV_CLOCK_DOC} = require("../lib/humor/clock.js");
  const {canonicalDayId, shiftDayId} = require("../lib/humor/daily.js");
  const {HUMOR_CORE, HUMOR_CORE_RELEASE, HUMOR_CORE_SEQUENCE} = require("../lib/humor/coreSequence.js");

  const V = (n) => HUMOR_CORE_SEQUENCE[n - 1].id;
  const Vs = (from, to) => Array.from({length: to - from + 1}, (_, i) => V(from + i));
  const ids = (items) => items.map((item) => item.contentId);
  const under = (prefix) => db.paths().filter((docPath) => docPath.startsWith(prefix));
  // Once the owner releases the sequence a deployed backend serves it, and
  // the blocks about the draft no longer describe anything.
  const draftOnly = HUMOR_CORE_RELEASE.released
    ? {skip: "the Core sequence is released: a deployed backend serves it"}
    : {};

  const rejectedWith = (code, message) => (error) => {
    assert.equal(error.code, code);
    assert.equal(error.message, message);
    return true;
  };

  beforeEach(async () => {
    db.reset({});
    await seedCalibrationCatalog(db);
  });

  it("decides from the release flag and the process", () => {
    asDeployed();
    assert.equal(core.isHumorCoreServed({released: false}), false);
    assert.equal(core.isHumorCoreServed({released: true}), true);
    for (const flag of NOT_THE_EMULATOR) {
      runAs(flag);
      assert.equal(core.isHumorCoreServed({released: false}), false, `flag ${JSON.stringify(flag)}`);
    }
    asEmulator();
    assert.equal(core.isHumorCoreServed({released: false}), true);
    assert.equal(core.isHumorCoreServed({released: true}), true);
    // With no argument it reads the sequence's own flag.
    asDeployed();
    assert.equal(core.isHumorCoreServed(), HUMOR_CORE_RELEASE.released);
  });

  it("a deployed backend hands a new member nothing: feed, daily set and feedback", draftOnly, async () => {
    asDeployed();
    db.resetStats();

    const feed = await callAs(humor.getHumorFeed, "member-live", {});
    assert.deepEqual(feed.items, []);
    assert.equal(feed.nextCursor, null);
    // "There is nothing here", not "you have seen everything".
    assert.equal(feed.catalogEmpty, true);
    assert.equal(feed.catalogExhausted, false);
    assert.equal(feed.calibration.insufficientPool, true);
    assert.equal(feed.calibration.complete, false);
    assert.equal(feed.calibration.totalCount, 0);

    const daily = await callAs(humor.getDailyHumorSet, "member-live", {});
    assert.equal(daily.status, "locked");
    assert.equal(daily.lockedReason, "calibration_incomplete");
    assert.deepEqual(daily.items, []);

    await assert.rejects(
      callAs(humor.submitHumorFeedback, "member-live", {contentId: V(1), rating: "funny"}),
      rejectedWith("failed-precondition", "not-in-set"),
    );
    await assert.rejects(
      callAs(humor.submitHumorFeedback, "member-live", {contentId: V(1), skipped: true, skipReason: "media_failed"}),
      rejectedWith("failed-precondition", "not-in-set"),
    );
    const sentDay = canonicalDayId(Date.now());
    await assert.rejects(
      callAs(humor.submitDailyHumorResponse, "member-live", {dayId: sentDay, contentId: V(16), rating: "funny"}),
      // `day-closed` only if midnight fell between the line above and the call.
      (error) =>
        rejectedWith(
          "failed-precondition",
          canonicalDayId(Date.now()) === sentDay ? "slot-replaced" : "day-closed",
        )(error),
    );

    // Nothing was learned and no content document was even read.
    assert.deepEqual(under("users/member-live/humorInteractions/"), []);
    assert.equal(db.read("users/member-live/humor/summary"), undefined);
    assert.equal(db.read("users/member-live/humor/calibration"), undefined);
    assert.deepEqual(
      [...db.stats().byPath.keys()].filter((docPath) => docPath.startsWith("humorContent/")),
      [],
    );
  });

  it("the emulator serves the same member the draft: feed, feedback and the daily five", async () => {
    asEmulator();
    const uid = "member-emulator";
    // The emulator-only clock pins the day, so the real time of day (and a
    // midnight in the middle of the run) cannot change what is asserted.
    const day = "2026-10-01";
    await db.doc(DAILY_DEV_CLOCK_DOC).set({dayId: day});

    const feed = await callAs(humor.getHumorFeed, uid, {});
    assert.deepEqual(ids(feed.items), Vs(1, HUMOR_CORE.onboardingCount));
    assert.equal(feed.catalogEmpty, false);

    for (const contentId of Vs(1, HUMOR_CORE.onboardingCount)) {
      const result = await callAs(humor.submitHumorFeedback, uid, {contentId, rating: "funny"});
      assert.equal(result.ok, true);
    }
    assert.equal((await callAs(humor.getHumorFeed, uid, {})).calibration.complete, true);
    assert.equal(under(`users/${uid}/humorInteractions/`).length, HUMOR_CORE.onboardingCount);

    // The next logical day.
    await db.doc(DAILY_DEV_CLOCK_DOC).set({dayId: shiftDayId(day, 1)});
    const daily = await callAs(humor.getDailyHumorSet, uid, {});
    assert.equal(daily.status, "ready");
    assert.equal(daily.dayId, shiftDayId(day, 1));
    assert.deepEqual(ids(daily.items), Vs(16, 15 + HUMOR_CORE.dailyCount));
  });

  it("a deployed backend hands a calibrated member nothing either", draftOnly, async () => {
    const uid = "member-calibrated";
    const now = Date.now();
    asEmulator();
    for (const contentId of Vs(1, HUMOR_CORE.onboardingCount)) {
      await core.submitHumorCoreResponse({db, uid, nowMs: now, contentId, rating: "funny", mediaFailed: false});
    }
    const nextDay = now + 24 * 60 * 60 * 1000;
    assert.deepEqual(
      ids((await core.getHumorCoreDailyView({db, uid, nowMs: nextDay})).items),
      Vs(16, 15 + HUMOR_CORE.dailyCount),
    );

    asDeployed();
    const before = db.read(`users/${uid}/humor/summary`).interactionCount;
    const feed = await core.getHumorCoreFeedView({db, uid, nowMs: nextDay});
    assert.deepEqual(feed.items, []);
    assert.equal(feed.catalogExhausted, true);
    const daily = await core.getHumorCoreDailyView({db, uid, nowMs: nextDay});
    assert.equal(daily.status, "locked");
    assert.deepEqual(daily.items, []);
    await assert.rejects(
      core.submitHumorCoreResponse({db, uid, nowMs: nextDay, contentId: V(16), rating: "funny", mediaFailed: false}),
      (error) => error instanceof core.HumorCoreRejected && error.reason === "not-in-set",
    );
    assert.equal(db.read(`users/${uid}/humor/summary`).interactionCount, before);
    // What they rated in the emulator is untouched.
    assert.equal(under(`users/${uid}/humorInteractions/`).length, HUMOR_CORE.onboardingCount);
  });
});

// ---------------------------------------------------------------------------
// 5. Relationship matching logs
// ---------------------------------------------------------------------------

describe("relationship matching: nothing about a pair is logged", () => {
  const {scoreRelationshipCompatibility} = require("../lib/relationshipCompatibility.js");
  const {relationshipScoreFromSummaries, saveRelationshipAnswer} = require("../lib/relationshipMatch.js");

  it("the debug helper is gone from the source and from the build", () => {
    for (const file of ["src/relationshipMatch.ts", "lib/relationshipMatch.js"]) {
      const text = fs.readFileSync(path.join(FUNCTIONS_DIR, file), "utf8");
      assert.equal(text.includes("RELATIONSHIP_DEBUG"), false, `${file} still has the debug tag`);
      assert.equal(/console\.(log|info|debug)/.test(text), false, `${file} writes to the console`);
      assert.equal(/relDebug/.test(text), false, `${file} still has the debug helper`);
    }
  });

  it("scores a pair exactly as before, silently", async () => {
    const viewer = {answers: {rq_001: "a", rq_002: "b", rq_005: "a"}};
    const partial = {answers: {rq_001: "a", rq_002: "b", rq_007: "c"}};
    const opposite = {answers: {rq_001: "b", rq_002: "a"}};
    const keyed = (answers) => ({answers, compatibilityKey: "rq_001:a|rq_002:b|rq_005:a"});
    let results;
    const lines = await capturingLogs(async () => {
      results = {
        partial: relationshipScoreFromSummaries("uid-viewer", "uid-candidate", viewer, partial),
        opposite: relationshipScoreFromSummaries("uid-viewer", "uid-candidate", viewer, opposite),
        missing: relationshipScoreFromSummaries("uid-viewer", "uid-candidate", viewer, undefined),
        exactKey: relationshipScoreFromSummaries(
          "uid-viewer",
          "uid-candidate",
          keyed(viewer.answers),
          keyed(opposite.answers),
        ),
      };
    });
    assert.deepEqual(lines, [], "the pair score wrote to the logs");

    const expected = scoreRelationshipCompatibility(viewer.answers, partial.answers);
    assert.deepEqual(results.partial, {
      score: expected.score,
      sharedQuestionCount: expected.sharedQuestionCount,
      alignedCount: expected.alignedCount,
      topTopics: expected.topTopics,
    });
    assert.deepEqual([results.partial.score, results.partial.alignedCount], [100, 2]);
    // No aligned answer and no comparable answers are both "no signal".
    assert.equal(results.opposite, null);
    assert.equal(results.missing, null);
    // An identical session key counts as a full three-answer match.
    assert.deepEqual(
      [results.exactKey.score, results.exactKey.alignedCount, results.exactKey.sharedQuestionCount],
      [100, 3, 3],
    );
  });

  it("saving an answer logs neither the answer nor the question", async () => {
    db.reset({});
    let saved;
    const lines = await capturingLogs(async () => {
      saved = await callAs(saveRelationshipAnswer, "uid-member", {questionId: "rq_001", answerId: "a"});
      await assert.rejects(
        callAs(saveRelationshipAnswer, "uid-member", {questionId: "rq_999", answerId: "a"}),
        (error) => error.code === "invalid-argument",
      );
    });
    assert.deepEqual(saved.answeredIds, ["rq_001"]);
    assert.deepEqual(lines, []);
  });

  it("an unexpected failure is logged once, by code only", async () => {
    db.reset({});
    const run = db.runTransaction.bind(db);
    db.runTransaction = async () => {
      throw Object.assign(new Error("ABORTED: users/uid-member/relationshipAnswers/rq_002 answer=b"), {code: 10});
    };
    let lines;
    try {
      lines = await capturingLogs(async () => {
        await assert.rejects(
          callAs(saveRelationshipAnswer, "uid-member", {questionId: "rq_002", answerId: "b"}),
          /ABORTED/,
        );
      });
    } finally {
      db.runTransaction = run;
    }
    assert.equal(lines.length, 1);
    assert.equal(lines[0].level, "error");
    assert.deepEqual(lines[0].args, ["saveRelationshipAnswer failed", {uid: "uid-member", code: 10}]);
  });
});

// ---------------------------------------------------------------------------
// 6. Purchase verifier logs
// ---------------------------------------------------------------------------

describe("purchase verifier logs", () => {
  const {safeErrorMeta} = require("../lib/security/logHygiene.js");
  const {PlayDeveloperApi} = require("../lib/subscription/googleSubscriptionVerifier.js");
  const {GooglePurchaseVerifier} = require("../lib/boost/googlePurchaseVerifier.js");

  const TOKEN = "kpnjfhdgeTOKENo.AO-J1Oz_purchase-token+with/odd=chars";
  /** What an HTTP client's error can look like: the request rides along. */
  function requestError(url) {
    const error = new TypeError(`request to ${url} failed, reason: getaddrinfo ENOTFOUND`);
    error.cause = Object.assign(new Error("getaddrinfo ENOTFOUND"), {code: "ENOTFOUND"});
    error.config = {url, headers: {Authorization: "Bearer play-access-token"}};
    return error;
  }
  const leaks = (lines) => {
    const text = JSON.stringify(lines);
    return [TOKEN, encodeURIComponent(TOKEN), "play-access-token", "androidpublisher.googleapis.com"].filter(
      (needle) => text.includes(needle),
    );
  };

  it("safeErrorMeta keeps the kind of failure and drops URLs and named secrets", () => {
    const url = `https://androidpublisher.googleapis.com/v3/tokens/${encodeURIComponent(TOKEN)}`;
    const meta = safeErrorMeta(requestError(url), [TOKEN]);
    assert.deepEqual(Object.keys(meta).sort(), ["code", "message", "name", "status"]);
    assert.equal(meta.name, "TypeError");
    assert.equal(meta.code, "ENOTFOUND");
    assert.equal(meta.status, null);
    assert.equal(meta.message, "request to [redacted-url] failed, reason: getaddrinfo ENOTFOUND");

    // A secret quoted outside a URL, raw or encoded, goes too.
    const bare = safeErrorMeta(new Error(`bad token ${TOKEN} / ${encodeURIComponent(TOKEN)}`), [TOKEN]);
    assert.equal(bare.message, "bad token [redacted] / [redacted]");

    assert.deepEqual(safeErrorMeta({status: 503, code: "UNAVAILABLE", message: "x".repeat(500)}), {
      name: "object",
      code: "UNAVAILABLE",
      status: 503,
      message: "x".repeat(200),
    });
    assert.deepEqual(safeErrorMeta("plain string"), {
      name: "string",
      code: null,
      status: null,
      message: "plain string",
    });
    assert.equal(safeErrorMeta(undefined, [null, undefined, ""]).message, "undefined");
  });

  it("a failed subscription lookup logs no URL, token or credential", async () => {
    const api = new PlayDeveloperApi({
      accessToken: async () => "play-access-token",
      fetchImpl: async (url) => {
        throw requestError(String(url));
      },
    });
    let result;
    const lines = await capturingLogs(async () => {
      result = await api.fetchSubscription({packageName: "com.mevora.app", purchaseToken: TOKEN});
    });
    assert.deepEqual(result, {ok: false, error: "transient"});
    assert.equal(lines.length, 1);
    assert.deepEqual(leaks(lines), []);
    // Still useful: what failed and why.
    assert.equal(lines[0].args[0], "premium: Google Play request failed");
    assert.equal(lines[0].args[1].error.code, "ENOTFOUND");
  });

  it("an unreadable subscription response logs no body beyond a short message", async () => {
    const api = new PlayDeveloperApi({
      accessToken: async () => "play-access-token",
      fetchImpl: async () => ({
        ok: true,
        status: 200,
        json: async () => {
          throw new SyntaxError(`Unexpected token in ${TOKEN}`);
        },
      }),
    });
    const lines = await capturingLogs(async () => {
      await api.fetchSubscription({packageName: "com.mevora.app", purchaseToken: TOKEN});
    });
    assert.equal(lines.length, 1);
    assert.deepEqual(leaks(lines), []);
    assert.equal(lines[0].args[1].error.name, "SyntaxError");
  });

  it("a failed Boost verification and consume log no URL or token", async () => {
    asDeployed();
    const verifier = new GooglePurchaseVerifier({
      accessToken: async () => "play-access-token",
      fetch: async (url) => {
        throw requestError(String(url));
      },
    });
    const request = {platform: "android", productId: "boost_1", transactionId: "GPA.1", purchaseToken: TOKEN};
    let verified;
    let consumed;
    const lines = await capturingLogs(async () => {
      verified = await verifier.verify(request);
      consumed = await verifier.consume(request);
    });
    assert.equal(verified.error, "unavailable");
    assert.equal(consumed, false);
    assert.equal(lines.length, 2);
    assert.deepEqual(leaks(lines), []);
  });

  it("no store verifier logs a raw error or its text", () => {
    for (const file of [
      "src/subscription/googleSubscriptionVerifier.ts",
      "src/subscription/appleSubscriptionVerifier.ts",
      "src/boost/googlePurchaseVerifier.ts",
      "src/boost/applePurchaseVerifier.ts",
    ]) {
      const text = fs.readFileSync(path.join(FUNCTIONS_DIR, file), "utf8");
      assert.equal(/\{\s*error\s*\}/.test(text), false, `${file} logs a raw error object`);
      assert.equal(/String\(error\)/.test(text), false, `${file} logs raw error text`);
    }
  });
});

// ---------------------------------------------------------------------------
// 7. Tooling and configuration
// ---------------------------------------------------------------------------

describe("smoke harness and local configuration", () => {
  const EMULATORS = {
    SMOKE_USE_EMULATOR: "true",
    SMOKE_FIREBASE_PROJECT: "demo-smoke",
    FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
    FIREBASE_AUTH_EMULATOR_HOST: "localhost:9099",
    FIREBASE_STORAGE_EMULATOR_HOST: "[::1]:9199",
  };
  let guard;
  before(async () => {
    guard = await import(pathToFileURL(path.join(REPO_ROOT, "tools", "smoke", "lib", "emulatorOnly.mjs")).href);
  });

  it("runs when everything it writes to is a local emulator", () => {
    assert.deepEqual(guard.smokeTargetProblems(EMULATORS), []);
    assert.equal(guard.smokeProjectId(EMULATORS), "demo-smoke");
    assert.equal(guard.smokeProjectId({GCLOUD_PROJECT: "demo-from-cli"}), "demo-from-cli");
  });

  it("has no default project and refuses an empty environment", () => {
    assert.equal(guard.smokeProjectId({}), null);
    assert.equal(guard.smokeTargetProblems({}).length, 5);
  });

  it("refuses without the emulator flag, even with emulator hosts set", () => {
    for (const flag of NOT_THE_EMULATOR) {
      const problems = guard.smokeTargetProblems({...EMULATORS, SMOKE_USE_EMULATOR: flag});
      assert.equal(problems.length, 1, JSON.stringify(flag));
      assert.match(problems[0], /SMOKE_USE_EMULATOR=true is required/);
    }
  });

  it("refuses when any service would be a live one: the flag alone redirects nothing", () => {
    for (const name of guard.SMOKE_EMULATOR_HOST_VARS) {
      for (const value of [undefined, "", "firestore.googleapis.com:443", "10.0.0.5:8080", "127.0.0.1"]) {
        const problems = guard.smokeTargetProblems({...EMULATORS, [name]: value});
        assert.equal(problems.length, 1, `${name}=${JSON.stringify(value)}`);
        assert.ok(problems[0].startsWith(`${name} must point at an emulator on this machine`));
      }
    }
  });

  it("the runner checks before it initialises anything, and names no live project", () => {
    const runner = fs.readFileSync(path.join(REPO_ROOT, "tools", "smoke", "run_smoke_test.mjs"), "utf8");
    assert.ok(runner.indexOf("smokeTargetProblems()") > 0);
    assert.ok(runner.indexOf("smokeTargetProblems()") < runner.indexOf("initAdmin();"));
    for (const file of ["run_smoke_test.mjs", "lib/helpers.mjs", "lib/emulatorOnly.mjs"]) {
      const text = fs.readFileSync(path.join(REPO_ROOT, "tools", "smoke", file), "utf8");
      assert.equal(/mevora-(production|d6ed0|staging)/.test(text), false, `${file} names a live project`);
    }
  });

  it(".env.example sends local values to a file a deploy does not upload", () => {
    const example = fs.readFileSync(path.join(FUNCTIONS_DIR, ".env.example"), "utf8");
    assert.match(example, /Copy to functions\/\.env\.local for the emulator/);
    assert.equal(/Copy to functions\/\.env for the emulator/.test(example), false);
  });
});
