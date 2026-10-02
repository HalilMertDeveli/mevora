/**
 * Seed the curated humor catalogue into a cloud project — or the local
 * Firestore emulator — and verify the initial calibration (V1–V15 of the Humor
 * Core sequence) end to end against it.
 *
 * Runs the real server code paths — `seedCalibrationCatalog`,
 * `getHumorCoreFeedView`, `submitHumorCoreResponse` — against real Firestore. The unit suite proves the
 * policy with an in-memory double and `functions/test/emulator/*` proves it on
 * the emulator; this is the layer that proves the deployed composite indexes,
 * the curation metadata and the transaction line up on an actual project.
 *
 * Refuses to touch production. Dev and staging only — seeding writes 36
 * documents and the verification creates (then deletes) throwaway user state,
 * neither of which belongs in a live database.
 *
 * The target is always explicit and printed before any write:
 *
 *   Cloud — FIRESTORE_EMULATOR_HOST must be unset:
 *     node tool/humorCalibrationQa.cjs --project mevora-d6ed0
 *     node tool/humorCalibrationQa.cjs --project mevora-d6ed0 --verify-only
 *
 *   Emulator — FIRESTORE_EMULATOR_HOST must be a loopback address; no
 *   credentials are looked up and --project defaults to the .firebaserc
 *   default (mevora-d6ed0, the project the app's emulator launch uses):
 *     $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *     node tool/humorCalibrationQa.cjs --emulator [--verify-only]
 *
 *   To only seed the emulator catalogue, without the verification's scratch
 *   users, use tool/seedEmulatorHumorCatalog.cjs instead.
 *
 * Cloud credentials, in order of preference:
 *   1. GOOGLE_APPLICATION_CREDENTIALS / application default credentials
 *   2. `gcloud auth print-access-token` (picked up automatically)
 */
const fs = require("node:fs");
const path = require("node:path");
const {execSync} = require("node:child_process");
const {createRequire} = require("node:module");

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));

// --------------------------------------------------------------------------
// Arguments and guard rails
// --------------------------------------------------------------------------

const argv = process.argv.slice(2);
const verifyOnly = argv.includes("--verify-only");
const emulatorMode = argv.includes("--emulator");
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;

/** The emulator talks to whatever project the suite was started with. */
function firebasercDefault() {
  try {
    const rc = JSON.parse(fs.readFileSync(path.join(__dirname, "..", ".firebaserc"), "utf8"));
    return rc.projects && rc.projects.default;
  } catch (_) {
    return undefined;
  }
}

const projectId = argv.includes("--project")
  ? argv[argv.indexOf("--project") + 1]
  : emulatorMode
    ? firebasercDefault()
    : undefined;

if (!projectId || projectId.startsWith("--")) {
  console.error(
    "usage: node tool/humorCalibrationQa.cjs --project <projectId> [--verify-only]\n" +
      "       node tool/humorCalibrationQa.cjs --emulator [--project <projectId>] [--verify-only]",
  );
  process.exit(2);
}

// The Firestore client silently follows FIRESTORE_EMULATOR_HOST, so the
// variable alone must never decide where 36 documents land.
if (emulatorMode) {
  if (!emulatorHost || !LOOPBACK_HOST.test(emulatorHost)) {
    console.error(
      "--emulator needs FIRESTORE_EMULATOR_HOST on a loopback address " +
        `(e.g. 127.0.0.1:8080); got "${emulatorHost ?? ""}"`,
    );
    process.exit(2);
  }
} else if (emulatorHost) {
  console.error(
    `FIRESTORE_EMULATOR_HOST is set ("${emulatorHost}"). Pass --emulator to ` +
      "target that emulator, or unset it to target the cloud project.",
  );
  process.exit(2);
}

// A project id, not an alias: `.firebaserc` aliases only resolve inside the
// Firebase CLI, and silently seeding the wrong database would be worse than
// failing here.
if (/production|prod$/i.test(projectId)) {
  console.error(`refusing to run against "${projectId}" — dev and staging only`);
  process.exit(2);
}

function accessToken() {
  // `shell: true` is required on Windows: gcloud ships as a .cmd shim, and
  // Node 20+ refuses to execFile batch files without a shell. No user input
  // reaches this command, so there is nothing to inject.
  try {
    return execSync("gcloud auth print-access-token", {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch (_) {
    return null;
  }
}

/** Dependencies and compiled output both live under functions/. */
function requireFromFunctions(id, hint) {
  try {
    return fromFunctions(id);
  } catch (_) {
    console.error(`${id} not found — run: ${hint}`);
    process.exit(2);
  }
}

function requireCompiled(relative) {
  const full = path.join(FUNCTIONS_DIR, relative);
  try {
    return require(full);
  } catch (error) {
    if (error.code === "MODULE_NOT_FOUND") {
      console.error(
        `compiled output missing (${relative}) — run: npm --prefix functions run build`,
      );
      process.exit(2);
    }
    throw error;
  }
}

function openFirestore() {
  const {Firestore} = requireFromFunctions(
    "@google-cloud/firestore",
    "npm --prefix functions ci",
  );
  if (emulatorMode) {
    // The client reads FIRESTORE_EMULATOR_HOST itself and sends no real
    // credentials to it, so there is nothing to look up.
    return new Firestore({projectId});
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return new Firestore({projectId});
  }
  const token = accessToken();
  if (!token) {
    console.error(
      "no credentials — run `gcloud auth application-default login`, " +
        "or make sure `gcloud auth print-access-token` works",
    );
    process.exit(2);
  }
  // firebase-admin's Firestore rejects a bare access token and insists on a
  // certificate or ADC. The underlying client accepts an auth client, and it
  // is the same class firebase-admin wraps, so the code under test is
  // unchanged.
  const {OAuth2Client} = requireFromFunctions(
    "google-auth-library",
    "npm --prefix functions ci",
  );
  const authClient = new OAuth2Client();
  authClient.setCredentials({access_token: token});
  return new Firestore({projectId, authClient});
}

const db = openFirestore();

const {seedCalibrationCatalog} = requireCompiled("lib/humor/calibrationCatalog.js");
const {CALIBRATION_TOTAL} = requireCompiled("lib/humor/calibration.js");
const {HUMOR_CORE, HUMOR_CORE_SEQUENCE} = requireCompiled("lib/humor/coreSequence.js");
const core = requireCompiled("lib/humor/coreService.js");
const {getDailyHumorSetView} = requireCompiled("lib/humor/dailyService.js");
const {loadUserHumorCalibration} = requireCompiled("lib/humor/feed.js");

// The service hands out a draft Core sequence only as the Functions emulator
// process (`isHumorCoreServed`); a deployed backend serves none of it until
// the owner releases it. This tool runs the service in its own process to
// prove the catalogue, the indexes and the transaction, so it runs as the
// emulator process against either target. The only other thing the flag
// switches on in this code is the dev clock document, which this tool never
// writes.
process.env.FUNCTIONS_EMULATOR = "true";

// --------------------------------------------------------------------------
// Harness
// --------------------------------------------------------------------------

const UID = "qa_humor_calibration";
const SCRATCH_UIDS = [UID, `${UID}_resume`, `${UID}_twinA`, `${UID}_twinB`];
const FIRST_FIFTEEN = HUMOR_CORE_SEQUENCE.slice(0, HUMOR_CORE.onboardingCount).map((e) => e.id);
let failures = 0;

async function step(name, fn) {
  try {
    const detail = await fn();
    console.log(`PASS  ${name}${detail ? ` — ${detail}` : ""}`);
  } catch (error) {
    failures += 1;
    console.error(`FAIL  ${name}\n      ${error.message}`);
  }
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const sameIds = (a, b) => a.length === b.length && a.every((id, i) => id === b[i]);
const feedFor = (uid) => core.getHumorCoreFeedView({db, uid, nowMs: Date.now()});
const rate = (uid, contentId, rating) =>
  core.submitHumorCoreResponse({db, uid, nowMs: Date.now(), contentId, rating, mediaFailed: false});

/** Throwaway users must not outlive the run. */
async function wipe(uid) {
  for (const sub of ["humor", "humorInteractions", "humorDaily"]) {
    const snap = await db.collection(`users/${uid}/${sub}`).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function wipeAll() {
  for (const uid of SCRATCH_UIDS) {
    await wipe(uid);
  }
}

// --------------------------------------------------------------------------

(async () => {
  const target = emulatorMode
    ? `Firestore EMULATOR at ${emulatorHost}`
    : "CLOUD Firestore";
  console.log(
    `target: ${target} · project: ${projectId}${verifyOnly ? " (verify only)" : ""}\n`,
  );

  if (!verifyOnly) {
    await step("seed the curated catalogue", async () => {
      // Same path as the seedInternalHumorContent callable: writes the active
      // catalogue and retires what it replaced (the old text cards).
      const seeded = await seedCalibrationCatalog(db);
      return `${seeded.written} curated documents upserted (${seeded.kind}), ${seeded.retired} retired`;
    });
  }

  await step("every entry of the Core sequence can be handed out", async () => {
    const report = await core.buildHumorCoreSequenceReport(db);
    assert(report.total > 0, "the Core sequence is empty");
    assert(
      report.healthy,
      `sequence not healthy — run without --verify-only: ${[...report.problems, ...report.warnings].join("; ")}`,
    );
    return (
      `${report.servableCount}/${report.total} servable, ` +
      (report.released ? "released" : "draft — a deployed backend serves none of it until released")
    );
  });

  await step("a fresh user gets V1–V15 in canonical order", async () => {
    await wipe(UID);
    const feed = await feedFor(UID);
    assert(!feed.calibration.complete, "fresh user already complete");
    assert(feed.catalogEmpty === false, "catalogue reported empty");
    const ids = feed.items.map((i) => i.contentId);
    assert(sameIds(ids, FIRST_FIFTEEN), `got ${ids.length} items, not V1–V${CALIBRATION_TOTAL} in order`);
    for (const item of feed.items) {
      assert(!("humorVector" in item), "feed leaked humorVector");
      assert(!("calibrationSlot" in item), "feed leaked the anchor slot");
      assert(!("safetyFlags" in item), "feed leaked safetyFlags");
    }
    return `${ids.length} items, no leaks`;
  });

  await step("two users get the same fifteen", async () => {
    const [a, b] = [`${UID}_twinA`, `${UID}_twinB`];
    await wipe(a);
    await wipe(b);
    const [fa, fb] = [await feedFor(a), await feedFor(b)];
    assert(
      sameIds(
        fa.items.map((i) => i.contentId),
        fb.items.map((i) => i.contentId),
      ),
      "two fresh users were given different content",
    );
    await wipe(a);
    await wipe(b);
    return "identical ids, identical order";
  });

  await step("interrupting mid-run resumes from server state", async () => {
    const uid = `${UID}_resume`;
    await wipe(uid);
    for (const id of FIRST_FIFTEEN.slice(0, 4)) {
      await rate(uid, id, "funny");
    }
    // A cold client sends nothing — only persisted state can carry this.
    const resumed = await feedFor(uid);
    assert(
      resumed.calibration.completedCount === 4,
      `resumed at ${resumed.calibration.completedCount}`,
    );
    assert(
      sameIds(
        resumed.items.map((i) => i.contentId),
        FIRST_FIFTEEN.slice(4),
      ),
      `resumed with ${resumed.items.length} items that are not V5–V15`,
    );
    await wipe(uid);
    return `resumed at 4/${CALIBRATION_TOTAL}, next is V5, nothing repeated`;
  });

  await step("rating all 15 completes calibration", async () => {
    let result;
    for (const [index, id] of FIRST_FIFTEEN.entries()) {
      result = await rate(UID, id, index % 3 === 0 ? "very_funny" : "funny");
    }
    assert(result.calibration.complete, `stuck at ${result.calibration.completedCount}`);
    const state = await loadUserHumorCalibration(db, UID);
    assert(state.complete, `calibration document at ${state.completedCount}/${CALIBRATION_TOTAL}`);
    assert(
      state.degradedCount === 0,
      `${state.degradedCount} positions counted as degraded`,
    );
    const summary = (await db.doc(`users/${UID}/humor/summary`).get()).data();
    assert(
      summary.interactionCount === CALIBRATION_TOTAL,
      `interactionCount ${summary.interactionCount}`,
    );
    return `slots: ${state.coveredSlots.join(", ")}`;
  });

  await step("the feed closes and the daily five wait for the next day", async () => {
    const feed = await feedFor(UID);
    assert(feed.calibration.complete, "calibration not complete");
    assert(feed.profileBuilding === false, "still reporting building");
    assert(feed.items.length === 0, `the closed feed served ${feed.items.length} items`);
    const daily = await getDailyHumorSetView({db, uid: UID, nowMs: Date.now()});
    assert(
      daily.status === "locked" && daily.lockedReason === "starts_tomorrow",
      `daily set is ${daily.status}/${daily.lockedReason} on the calibration day`,
    );
    const next = HUMOR_CORE_SEQUENCE[HUMOR_CORE.onboardingCount].id;
    let refused = false;
    try {
      await rate(UID, next, "funny");
    } catch (error) {
      refused = error.reason === "not-in-set";
    }
    assert(refused, "tomorrow's first entry was accepted today");
    return "feed closed, daily locked (starts_tomorrow), V16 refused";
  });

  await step("no verification state is left behind", async () => {
    await wipeAll();
    for (const uid of SCRATCH_UIDS) {
      const left = await db.collection(`users/${uid}/humor`).get();
      assert(left.empty, `state left behind for ${uid}`);
    }
    return `${SCRATCH_UIDS.length} scratch users removed`;
  });

  console.log(
    `\n${failures === 0 ? "ALL CHECKS PASSED" : `${failures} CHECK(S) FAILED`}`,
  );
  process.exit(failures === 0 ? 0 : 1);
})().catch(async (error) => {
  console.error("fatal:", error.message);
  try {
    await wipeAll();
  } catch (_) {
    // Cleanup is best effort — the original failure is what matters.
  }
  process.exit(1);
});
