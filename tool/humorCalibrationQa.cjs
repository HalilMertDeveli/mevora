/**
 * Seed the curated humor calibration catalog into a cloud project and verify
 * the calibration engine end to end against it.
 *
 * Runs the real server code paths — `upsertHumorContentDoc`, `buildHumorFeed`,
 * `submitHumorFeedbackTx` — against real Firestore. The unit suite proves the
 * policy with an in-memory double and `functions/test/emulator/*` proves it on
 * the emulator; this is the layer that proves the deployed composite indexes,
 * the curation metadata and the transaction line up on an actual project.
 *
 * Refuses to touch production. Dev and staging only — seeding writes 36
 * documents and the verification creates (then deletes) throwaway user state,
 * neither of which belongs in a live database.
 *
 * Usage, from the repo root:
 *
 *   node tool/humorCalibrationQa.cjs --project mevora-d6ed0
 *   node tool/humorCalibrationQa.cjs --project mevora-d6ed0 --verify-only
 *
 * Credentials, in order of preference:
 *   1. GOOGLE_APPLICATION_CREDENTIALS / application default credentials
 *   2. `gcloud auth print-access-token` (picked up automatically)
 */
const path = require("node:path");
const {execSync} = require("node:child_process");
const {createRequire} = require("node:module");

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));

// --------------------------------------------------------------------------
// Arguments and guard rails
// --------------------------------------------------------------------------

const argv = process.argv.slice(2);
const projectId = argv[argv.indexOf("--project") + 1];
const verifyOnly = argv.includes("--verify-only");

if (!projectId || projectId.startsWith("--")) {
  console.error("usage: node tool/humorCalibrationQa.cjs --project <projectId> [--verify-only]");
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

const {
  INTERNAL_HUMOR_SEED,
  upsertHumorContentDoc,
  listCalibrationPool,
} = requireCompiled("lib/humor/contentRepository.js");
const {
  ANCHOR_SLOTS,
  CALIBRATION_TOTAL,
  HUMOR_CALIBRATION_VERSION,
} = requireCompiled("lib/humor/calibration.js");
const {buildHumorFeed, loadUserHumorCalibration} = requireCompiled("lib/humor/feed.js");
const {submitHumorFeedbackTx} = requireCompiled("lib/humor/feedback.js");

// --------------------------------------------------------------------------
// Harness
// --------------------------------------------------------------------------

const UID = "qa_humor_calibration";
const SCRATCH_UIDS = [UID, `${UID}_resume`, `${UID}_rotA`, `${UID}_rotB`];
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

/** Throwaway users must not outlive the run. */
async function wipe(uid) {
  for (const sub of ["humor", "humorInteractions"]) {
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
  console.log(`project: ${projectId}${verifyOnly ? " (verify only)" : ""}\n`);

  if (!verifyOnly) {
    await step("seed the curated calibration catalog", async () => {
      for (const item of INTERNAL_HUMOR_SEED) {
        await upsertHumorContentDoc(db, {
          ...item,
          safetyStatus: "approved",
          active: true,
        });
      }
      return `${INTERNAL_HUMOR_SEED.length} curated documents upserted`;
    });
  }

  await step("every anchor slot has a rotatable pool", async () => {
    const pool = await listCalibrationPool(db, {
      calibrationVersion: HUMOR_CALIBRATION_VERSION,
      limit: 200,
    });
    assert(pool.length > 0, "calibration pool is empty — run without --verify-only");
    const bySlot = new Map();
    for (const item of pool) {
      if (item.calibration.slot) {
        bySlot.set(item.calibration.slot, (bySlot.get(item.calibration.slot) ?? 0) + 1);
      }
    }
    for (const slot of ANCHOR_SLOTS) {
      const n = bySlot.get(slot.id) ?? 0;
      assert(n >= 2, `${slot.id} has ${n} candidates — cannot rotate`);
    }
    const open = pool.filter((i) => !i.calibration.slot).length;
    const needed = CALIBRATION_TOTAL - ANCHOR_SLOTS.length;
    assert(open >= needed, `open pool has ${open}, adaptive + exploration need ${needed}`);
    return `${pool.length} eligible, ${bySlot.size} slots, open pool ${open}`;
  });

  await step("a fresh user gets a 6 / 6 / 3 calibration page", async () => {
    await wipe(UID);
    const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
    assert(!feed.calibration.complete, "fresh user already complete");
    assert(feed.calibration.insufficientPool === false, "pool reported insufficient");
    assert(
      feed.items.length === CALIBRATION_TOTAL,
      `got ${feed.items.length} items, expected ${CALIBRATION_TOTAL}`,
    );
    const stages = feed.items.map((i) => i.calibrationStage);
    const count = (s) => stages.filter((x) => x === s).length;
    assert(count("anchor") === 6, `anchor=${count("anchor")}`);
    assert(count("adaptive") === 6, `adaptive=${count("adaptive")}`);
    assert(count("exploration") === 3, `exploration=${count("exploration")}`);
    const ids = feed.items.map((i) => i.contentId);
    assert(new Set(ids).size === ids.length, "duplicate content in calibration");
    for (const item of feed.items) {
      assert(!("humorVector" in item), "feed leaked humorVector");
      assert(!("calibrationSlot" in item), "feed leaked the anchor slot");
      assert(!("safetyFlags" in item), "feed leaked safetyFlags");
    }
    return "6 anchor, 6 adaptive, 3 exploration, no duplicates, no leaks";
  });

  await step("rating all 15 completes calibration", async () => {
    let guard = 0;
    while (guard < 40) {
      const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 15});
      if (feed.calibration.complete || feed.items.length === 0) break;
      await submitHumorFeedbackTx({
        db,
        uid: UID,
        contentId: feed.items[0].contentId,
        rating: guard % 3 === 0 ? "very_funny" : "funny",
      });
      guard += 1;
    }
    const state = await loadUserHumorCalibration(db, UID);
    assert(state.complete, `stuck at ${state.completedCount}/${CALIBRATION_TOTAL}`);
    assert(
      state.degradedCount === 0,
      `${state.degradedCount} positions filled with uncurated content`,
    );
    assert(
      state.coveredSlots.length === ANCHOR_SLOTS.length,
      `covered ${state.coveredSlots.length} of ${ANCHOR_SLOTS.length} slots`,
    );
    return `slots: ${state.coveredSlots.join(", ")}`;
  });

  await step("interrupting mid-run resumes from server state", async () => {
    const uid = `${UID}_resume`;
    await wipe(uid);
    const first = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 15});
    for (const item of first.items.slice(0, 4)) {
      await submitHumorFeedbackTx({db, uid, contentId: item.contentId, rating: "funny"});
    }
    // A cold client sends no cursor — only persisted state can carry this.
    const resumed = await buildHumorFeed({db, uid, languages: ["tr", "en"], limit: 15});
    assert(
      resumed.calibration.completedCount === 4,
      `resumed at ${resumed.calibration.completedCount}`,
    );
    assert(
      resumed.items.length === CALIBRATION_TOTAL - 4,
      `got ${resumed.items.length} remaining`,
    );
    const state = await loadUserHumorCalibration(db, uid);
    const rated = new Set(state.ratedContentIds);
    for (const item of resumed.items) {
      assert(!rated.has(item.contentId), `re-served ${item.contentId}`);
    }
    await wipe(uid);
    return `resumed at 4/${CALIBRATION_TOTAL}, ${resumed.items.length} left, nothing repeated`;
  });

  await step("learning continues after the 15th", async () => {
    const before = (await db.doc(`users/${UID}/humor/summary`).get()).data();
    const feed = await buildHumorFeed({db, uid: UID, languages: ["tr", "en"], limit: 12});
    assert(feed.calibration.complete, "calibration not complete");
    assert(feed.profileBuilding === false, "still reporting building");
    assert(feed.items.length > 0, "no ordinary content left to learn from");
    for (const item of feed.items) {
      assert(!item.calibrationStage, "ordinary feed item labelled as calibration");
    }
    await submitHumorFeedbackTx({
      db,
      uid: UID,
      contentId: feed.items[0].contentId,
      rating: "very_funny",
    });
    const after = (await db.doc(`users/${UID}/humor/summary`).get()).data();
    assert(
      after.interactionCount === before.interactionCount + 1,
      `interactionCount ${before.interactionCount} -> ${after.interactionCount}`,
    );
    assert(
      after.confidence > before.confidence,
      `confidence did not grow: ${before.confidence} -> ${after.confidence}`,
    );
    const state = await loadUserHumorCalibration(db, UID);
    assert(state.completedCount === CALIBRATION_TOTAL, "the milestone moved past 15");
    return `interactionCount ${before.interactionCount} -> ${after.interactionCount}, milestone frozen at 15`;
  });

  await step("two users get different anchors from the same slots", async () => {
    const [a, b] = [`${UID}_rotA`, `${UID}_rotB`];
    await wipe(a);
    await wipe(b);
    const fa = await buildHumorFeed({db, uid: a, languages: ["tr", "en"], limit: 15});
    const fb = await buildHumorFeed({db, uid: b, languages: ["tr", "en"], limit: 15});
    const anchors = (f) =>
      f.items.filter((i) => i.calibrationStage === "anchor").map((i) => i.contentId);
    const [aa, ab] = [anchors(fa), anchors(fb)];
    assert(aa.length === 6 && ab.length === 6, "anchor count wrong");
    const shared = aa.filter((id) => ab.includes(id));
    assert(shared.length < 6, "both users got an identical anchor set");
    await wipe(a);
    await wipe(b);
    return `${6 - shared.length}/6 anchors differ`;
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
