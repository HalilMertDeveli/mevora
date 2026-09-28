#!/usr/bin/env node
/**
 * Seeds the curated humor calibration catalogue into the Firebase Emulator
 * Suite, so "Mizahını Keşfet" has content to calibrate on locally.
 *
 * It runs exactly what the admin-only `seedInternalHumorContent` callable
 * runs: `seedCalibrationCatalog` from the COMPILED functions output, so the
 * emulator gets the same catalogue the deployed functions would seed.
 *
 * The catalogue is ACTIVE_CALIBRATION_CATALOG ("curated_giphy") in
 * functions/src/humor/calibrationSeed.ts: the hand-picked GIPHY items
 * (CURATED_GIPHY_CATALOG). Text-joke documents an earlier seed wrote are retired —
 * deactivated and un-curated, never deleted — as is any `ext_giphy_<id>` sync
 * copy of a curated clip and any `hc_gif_*` doc that left the catalogue.
 * The script reports how many docs it created, refreshed, converted (type
 * changed) and retired.
 *
 * Emulator only. It refuses to run unless FIRESTORE_EMULATOR_HOST points at a
 * loopback address; with that variable set the Admin SDK cannot reach a cloud
 * database at all.
 *
 * Idempotent. `upsertHumorContentDoc` merges, keeps each item's createdAt and
 * stats, and never touches users/*, so re-running it (tool/ensure_emulators.ps1
 * does on every F5) refreshes the catalogue without resetting anyone's
 * calibration progress, ratings or profile.
 *
 * Optional provider top-up (--provider-topup): when functions/.secret.local
 * declares a GIPHY_API_KEY entry (only the NAME is checked; the value is never
 * read into anything, printed or logged), it calls the admin-only
 * `syncHumorFromProvider` callable on the Functions emulator as a throwaway
 * emulator admin and prints the diagnostic counts. Without that entry it
 * prints one line and moves on. Needs FIREBASE_AUTH_EMULATOR_HOST and
 * --functions-host (both loopback). A provider failure never fails the seed.
 *
 * Usage, from the repo root (PowerShell):
 *
 *   npm --prefix functions run build
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   node tool/seedEmulatorHumorCatalog.cjs [--project mevora-d6ed0]
 *
 *   # plus the provider top-up:
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   node tool/seedEmulatorHumorCatalog.cjs --provider-topup --functions-host 127.0.0.1:5001
 *
 * The project defaults to QA_PROJECT_ID, then mevora-d6ed0 — the project the
 * app's "full emulator suite" launch configuration talks to. It must match the
 * --project the emulators were started with.
 */
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));

// --------------------------------------------------------------------------
// Guard rails — before anything is loaded or initialised
// --------------------------------------------------------------------------

const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST is not set. This script only " +
      "ever seeds the Firestore emulator (e.g. 127.0.0.1:8080).",
  );
  process.exit(2);
}
if (!LOOPBACK_HOST.test(firestoreHost)) {
  console.error(
    `REFUSING TO RUN: FIRESTORE_EMULATOR_HOST="${firestoreHost}" is not a ` +
      "loopback address (127.x.x.x, localhost or [::1]).",
  );
  process.exit(2);
}

const argv = process.argv.slice(2);
function flagValue(name) {
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : undefined;
}
const projectId = flagValue("--project") ?? (process.env.QA_PROJECT_ID || "mevora-d6ed0");
if (!projectId || !/^[a-z0-9][a-z0-9-]{2,62}$/.test(projectId)) {
  console.error(
    "usage: node tool/seedEmulatorHumorCatalog.cjs [--project <projectId>] " +
      "[--provider-topup --functions-host <127.0.0.1:port>]",
  );
  process.exit(2);
}
const providerTopUp = argv.includes("--provider-topup");
const functionsHost = flagValue("--functions-host");

// --------------------------------------------------------------------------
// Dependencies and compiled output both live under functions/
// --------------------------------------------------------------------------

function requireFromFunctions(id) {
  try {
    return fromFunctions(id);
  } catch (_) {
    console.error(`${id} not found — run: npm --prefix functions ci`);
    process.exit(2);
  }
}

function requireCompiled(relative) {
  const full = path.join(FUNCTIONS_DIR, relative);
  if (!fs.existsSync(full)) {
    console.error(
      `compiled functions output missing (functions/${relative}) — run: ` +
        "npm --prefix functions run build",
    );
    process.exit(2);
  }
  return require(full);
}

/** A seed compiled before its source changed would seed yesterday's catalogue. */
function warnIfStale(sourceRelative, compiledRelative) {
  try {
    const source = fs.statSync(path.join(FUNCTIONS_DIR, sourceRelative)).mtimeMs;
    const compiled = fs.statSync(path.join(FUNCTIONS_DIR, compiledRelative)).mtimeMs;
    if (source > compiled) {
      console.warn(
        `WARNING: functions/${sourceRelative} is newer than its compiled output — ` +
          "run: npm --prefix functions run build",
      );
    }
  } catch (_) {
    // Source not checked out next to lib (unusual); the compiled seed still works.
  }
}

const admin = requireFromFunctions("firebase-admin");
const {HUMOR_CONTENT_COLLECTION} = requireCompiled("lib/humor/contentRepository.js");
const {seedCalibrationCatalog} = requireCompiled("lib/humor/calibrationCatalog.js");
const {buildCalibrationPoolReport} = requireCompiled("lib/humor/calibrationPoolReport.js");
warnIfStale("src/humor/calibrationSeed.ts", "lib/humor/calibrationSeed.js");

// --------------------------------------------------------------------------
// Provider top-up (optional)
// --------------------------------------------------------------------------

const PROVIDER_SKIPPED =
  "Provider content skipped: GIPHY key unavailable (billing disabled; add " +
  "functions/.secret.local to enable)";

/**
 * True when functions/.secret.local declares GIPHY_API_KEY. Only the part of
 * each line before "=" is looked at; the value is never kept or printed.
 * HUMOR_TOPUP_SECRET_FILE overrides the path (for testing this script).
 */
function giphyKeyDeclared() {
  const file =
    process.env.HUMOR_TOPUP_SECRET_FILE || path.join(FUNCTIONS_DIR, ".secret.local");
  let text;
  try {
    text = fs.readFileSync(file, "utf8");
  } catch (_) {
    return false;
  }
  return text.split(/\r?\n/).some((line) => {
    const name = line.split("=", 1)[0].replace(/^\s*export\s+/, "").trim();
    return name === "GIPHY_API_KEY" && line.includes("=");
  });
}

async function postJson(url, body, headers = {}, timeoutMs = 180000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {"Content-Type": "application/json", ...headers},
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const json = await response.json().catch(() => ({}));
    return {status: response.status, json};
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Calls syncHumorFromProvider on the Functions emulator as a throwaway admin
 * created in the Auth emulator, then deletes that admin. Never throws.
 */
async function providerTopUpStep() {
  if (!giphyKeyDeclared()) {
    console.log(`  ${PROVIDER_SKIPPED}`);
    return;
  }
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (!authHost || !LOOPBACK_HOST.test(authHost) || !functionsHost ||
      !LOOPBACK_HOST.test(functionsHost)) {
    console.warn(
      "  Provider top-up skipped: needs loopback FIREBASE_AUTH_EMULATOR_HOST and " +
        "--functions-host <127.0.0.1:port>",
    );
    return;
  }

  const suffix = crypto.randomBytes(6).toString("hex");
  const email = `humor-topup-${suffix}@mevora.test`;
  // Emulator-only credential for a user deleted a few seconds later; never printed.
  const password = crypto.randomBytes(24).toString("base64url");
  let uid = null;
  try {
    const user = await admin.auth().createUser({email, password, displayName: "Humor top-up (emulator)"});
    uid = user.uid;
    await admin.auth().setCustomUserClaims(uid, {admin: true});

    const signIn = await postJson(
      `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator`,
      {email, password, returnSecureToken: true},
    );
    const idToken = signIn.json && signIn.json.idToken;
    if (!idToken) {
      console.warn(`  Provider top-up failed: emulator sign-in answered HTTP ${signIn.status}`);
      return;
    }

    console.log("  Provider top-up: calling syncHumorFromProvider on the Functions emulator");
    const call = await postJson(
      `http://${functionsHost}/${projectId}/europe-west1/syncHumorFromProvider`,
      {data: {language: "tr", limit: 24}},
      {Authorization: `Bearer ${idToken}`},
    );
    const result = call.json && call.json.result;
    if (!result) {
      const status = call.json && call.json.error && call.json.error.status;
      console.warn(`  Provider top-up failed: HTTP ${call.status}${status ? ` (${status})` : ""}`);
      return;
    }
    if (result.configured === false) {
      console.log(
        "  Provider content skipped: the Functions emulator did not load GIPHY_API_KEY " +
          "(restart the emulator suite after adding functions/.secret.local)",
      );
      return;
    }
    const rejected = Object.entries(result.rejected || {})
      .map(([reason, n]) => `${reason} ${n}`)
      .join(", ");
    const errors = Object.entries(result.errors || {})
      .map(([reason, n]) => `${reason} ${n}`)
      .join(", ");
    console.log(
      `  provider: requested ${result.requested}, fetched ${result.fetched}, ` +
        `accepted ${result.accepted}, duplicates ${result.duplicates}, ` +
        `clips ${result.clipsAvailable ? "available" : "unavailable"}`,
    );
    console.log(`  provider rejected: ${rejected || "none"}`);
    if (errors) {
      console.warn(`  provider errors: ${errors}`);
    }
  } catch (error) {
    console.warn(
      `  Provider top-up failed: ${error && error.message ? error.message : String(error)}`,
    );
  } finally {
    if (uid) {
      await admin.auth().deleteUser(uid).catch(() => {});
    }
  }
}

// --------------------------------------------------------------------------

(async () => {
  console.log("Seeding the curated humor catalogue into the Firestore emulator");
  console.log(`  target: ${firestoreHost} (emulator) · project ${projectId}`);

  admin.initializeApp({projectId});
  const db = admin.firestore();
  const collection = db.collection(HUMOR_CONTENT_COLLECTION);

  // Same code path as the admin seedInternalHumorContent callable.
  const seeded = await seedCalibrationCatalog(db);
  const total = (await collection.select().get()).size;
  const label = seeded.kind === "curated_giphy" ? "curated GIPHY items" : "curated text cards";
  console.log(
    `  catalogue: ${seeded.kind} · written: ${seeded.written} ${label} ` +
      `(${seeded.created} new, ${seeded.refreshed} refreshed, ${seeded.converted} converted) · ` +
      `retired: ${seeded.retired} · ${HUMOR_CONTENT_COLLECTION} holds ${total} docs`,
  );
  if (seeded.written === 0) {
    console.warn("  WARNING: the active calibration catalogue is empty");
  }

  const report = await buildCalibrationPoolReport(db);
  console.log(
    `  anchor-slot pools (calibration v${report.calibrationVersion}, ` +
      `${report.totalEligible} eligible):`,
  );
  for (const slot of report.anchorSlots) {
    console.log(
      `    ${slot.slotId.padEnd(18)} ${String(slot.candidates).padStart(2)} candidates, ` +
        `${slot.measuring} measuring ${slot.primary}` +
        `${slot.ok ? "" : "  <-- cannot rotate"}`,
    );
  }
  console.log(`  open pool (adaptive + exploration): ${report.openPoolSize}`);
  if (report.healthy) {
    console.log("  pool: healthy — calibration can run its full 15 without degrading");
  } else {
    console.warn("  WARNING: pool is NOT healthy — calibration will degrade:");
    for (const warning of report.warnings) {
      console.warn(`    - ${warning}`);
    }
  }

  if (providerTopUp) {
    await providerTopUpStep();
  }
  await closeAndExit(0);
})().catch(async (error) => {
  console.error("HUMOR CATALOGUE SEED FAILED:", error && error.message ? error.message : error);
  await closeAndExit(1);
});

/**
 * Close the Admin SDK before leaving. Calling process.exit() while fetch
 * sockets are still closing trips a libuv assertion on Windows
 * (`!(handle->flags & UV_HANDLE_CLOSING)`, src\win\async.c) and turns a
 * successful run into a crash exit code.
 */
async function closeAndExit(code) {
  process.exitCode = code;
  try {
    await Promise.all(admin.apps.filter(Boolean).map((app) => app.delete()));
  } catch (_) {
    // Nothing left to close.
  }
  // Give in-flight sockets a moment to finish closing, then leave even if a
  // stray handle would keep the event loop alive.
  setTimeout(() => process.exit(code), 250).unref();
}
