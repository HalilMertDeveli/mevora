#!/usr/bin/env node
/**
 * Emulator-only developer tool for Face Anchor verification.
 *
 *   status [uid]                  the outcome the fake provider will give next,
 *                                 and — with a uid — that member's attempt
 *                                 state, verified photos and pending selfies
 *   outcome success               the next verifications succeed (the default)
 *   outcome liveness-fail         … fail the liveness check
 *   outcome mismatch              … pass liveness, fail the face match
 *   outcome provider-error        … hit a provider outage
 *   outcome <name> --once         only the next verification; then back to success
 *   clear                         remove the setting (same as `outcome success`)
 *   budget-reset <uid>            give a member their daily attempts back
 *   sweep                         run the stale-selfie sweep now (the schedule
 *                                 does not fire in the emulator)
 *   sweep --all                   … deleting every pending selfie, whatever its age
 *
 * The outcome is the `devControl/faceAnchor` document. Only the fake provider
 * reads it, and the fake provider exists ONLY inside the Functions emulator
 * (FUNCTIONS_EMULATOR=true): a deployed function never constructs it and never
 * looks at this document, and Firestore rules keep every client away from it.
 * Nothing the app sends can choose an outcome.
 *
 * Emulator only: refuses to run unless FIRESTORE_EMULATOR_HOST is a loopback
 * address, so the Admin SDK cannot reach a cloud database at all.
 *
 * Usage, from the repo root (PowerShell), after `npm --prefix functions run build`:
 *
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199"   # status <uid>, sweep
 *   node tool/faceAnchorDev.cjs status [uid] [--project mevora-d6ed0]
 *   node tool/faceAnchorDev.cjs outcome mismatch --once
 *   node tool/faceAnchorDev.cjs clear
 */
const fs = require("node:fs");
const path = require("node:path");
const {createRequire} = require("node:module");

const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost || !LOOPBACK_HOST.test(firestoreHost)) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST must be set to a loopback emulator " +
      "address (e.g. 127.0.0.1:8080).",
  );
  process.exit(2);
}
const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
if (storageHost && !LOOPBACK_HOST.test(storageHost)) {
  console.error("REFUSING TO RUN: FIREBASE_STORAGE_EMULATOR_HOST must be a loopback emulator address.");
  process.exit(2);
}

const raw = process.argv.slice(2);
const flagIndex = raw.indexOf("--project");
const projectId = flagIndex >= 0 ? raw[flagIndex + 1] : process.env.QA_PROJECT_ID || "mevora-d6ed0";
const rest = flagIndex >= 0 ? raw.filter((_, i) => i !== flagIndex && i !== flagIndex + 1) : raw;
const flags = new Set(rest.filter((value) => value.startsWith("--")));
const [command, arg] = rest.filter((value) => !value.startsWith("--"));
const usage =
  "usage: node tool/faceAnchorDev.cjs status [uid] | " +
  "outcome <success|liveness-fail|mismatch|provider-error> [--once] | clear | " +
  "budget-reset <uid> | sweep [--all]   [--project <id>]";
if (!projectId || !/^[a-z0-9][a-z0-9-]{2,62}$/.test(projectId) || !command) {
  console.error(usage);
  process.exit(2);
}

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(FUNCTIONS_DIR, "package.json"));
function compiled(relative) {
  const full = path.join(FUNCTIONS_DIR, "lib", relative);
  if (!fs.existsSync(full)) {
    console.error(`${relative} is not built — run: npm --prefix functions run build`);
    process.exit(2);
  }
  return require(full);
}

const {initializeApp} = fromFunctions("firebase-admin/app");
const {getFirestore, FieldValue} = fromFunctions("firebase-admin/firestore");
const {getStorage} = fromFunctions("firebase-admin/storage");
const fake = compiled("faceAnchor/fakeProvider.js");
const record = compiled("faceAnchor/faceAnchorRecord.js");

// The emulator's default bucket for this project id.
initializeApp({projectId, storageBucket: `${projectId}.firebasestorage.app`});
const db = getFirestore();

/** What the app shows the member for each fake outcome. */
const OUTCOMES = {
  "success": "success",
  "liveness-fail": "liveness_failed",
  "mismatch": "face_mismatch",
  "provider-error": "provider_error",
};

function requireStorage() {
  if (!storageHost) {
    console.error("set FIREBASE_STORAGE_EMULATOR_HOST (e.g. 127.0.0.1:9199) for this command");
    process.exit(2);
  }
  return getStorage().bucket();
}

async function pendingSelfies(uid) {
  if (!storageHost) {
    return null;
  }
  const prefix = uid ? `${record.SELFIE_PREFIX}${uid}/` : record.SELFIE_PREFIX;
  const [files] = await getStorage().bucket().getFiles({prefix});
  return files.map((file) => file.name);
}

async function status(uid) {
  const control = (await db.doc(fake.FACE_ANCHOR_DEV_CONTROL_DOC).get()).data();
  const outcome = fake.FAKE_OUTCOMES.includes(control?.outcome) ? control.outcome : "success";
  console.log(`next fake outcome : ${outcome}${control?.once === true ? " (once)" : ""}${control ? "" : " (not set)"}`);
  const all = await pendingSelfies();
  console.log(`pending selfies   : ${all === null ? "(set FIREBASE_STORAGE_EMULATOR_HOST to list)" : all.length}`);
  if (!uid) {
    return;
  }
  const state = (await db.doc(record.faceAnchorStatePath(uid)).get()).data();
  console.log(`--- ${uid}`);
  if (!state) {
    console.log("attempt state     : none");
  } else {
    console.log(`attempt state     : ${state.status}${state.reason ? ` (${state.reason})` : ""}, photo ${state.photoId ?? "-"}`);
    console.log(`attempts today    : ${state.attemptCount ?? 0}/${record.MAX_ATTEMPTS_PER_WINDOW} (refunded ${state.refundCount ?? 0})`);
  }
  const profile = (await db.doc(`profiles/${uid}`).get()).data() ?? {};
  console.log(`under the rule    : ${profile.faceAnchorRequired === true ? "yes" : "no"}`);
  console.log(`usable anchors    : ${(profile.faceAnchorPhotoIds ?? []).join(", ") || "none"}`);
  const ledger = await db.collection(`users/${uid}/photoModeration`).get();
  for (const doc of ledger.docs) {
    const verified = doc.get("faceAnchor.status") === "verified";
    console.log(`  photo ${doc.id}: ${doc.get("status")}${verified ? ", face anchor verified" : ""}`);
  }
  const mine = await pendingSelfies(uid);
  if (mine !== null) {
    console.log(`their selfies     : ${mine.length ? mine.join(", ") : "none"}`);
  }
}

async function outcome(name) {
  const value = OUTCOMES[name];
  if (!value) {
    console.error(usage);
    process.exit(2);
  }
  const once = flags.has("--once");
  await db.doc(fake.FACE_ANCHOR_DEV_CONTROL_DOC).set({
    outcome: value,
    once,
    setBy: "tool/faceAnchorDev.cjs",
    setAtMs: Date.now(),
  });
  console.log(`fake provider outcome set to ${value}${once ? " for the next verification only" : ""}`);
}

async function clear() {
  await db.doc(fake.FACE_ANCHOR_DEV_CONTROL_DOC).delete();
  console.log("fake provider outcome cleared (success)");
}

async function budgetReset(uid) {
  if (!uid) {
    console.error(usage);
    process.exit(2);
  }
  const ref = db.doc(record.faceAnchorStatePath(uid));
  if (!(await ref.get()).exists) {
    console.log(`${uid}: no attempt state — nothing to reset`);
    return;
  }
  await ref.update({
    attemptCount: 0,
    refundCount: 0,
    windowStartedAtMs: 0,
    lastAttemptAtMs: 0,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await db.doc(`users/${uid}/rateLimits/faceAnchorStart`).delete();
  console.log(`${uid}: attempt budget and cooldown reset`);
}

async function sweep() {
  const bucket = requireStorage();
  const service = compiled("faceAnchor/faceAnchorService.js");
  const result = await service.sweepFaceAnchorSelfies(
    {db, bucket: () => bucket, now: () => Date.now()},
    flags.has("--all") ? {maxAgeMs: 0} : {},
  );
  console.log(`sweep: scanned ${result.scanned}, deleted ${result.deleted}`);
}

const run = {
  status: () => status(arg),
  outcome: () => outcome(arg),
  clear,
  "budget-reset": () => budgetReset(arg),
  sweep,
}[command];
if (!run) {
  console.error(usage);
  process.exit(2);
}
run().then(
  () => process.exit(0),
  (error) => {
    console.error(String(error && error.message ? error.message : error));
    process.exit(1);
  },
);
