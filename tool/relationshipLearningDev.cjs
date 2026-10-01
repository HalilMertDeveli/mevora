#!/usr/bin/env node
/**
 * Emulator-only developer tool for the relationship questions (Core sequence).
 *
 *   status [uid]        the learning day (and the test clock); with a uid, that
 *                       member's place in the Core sequence and today's set
 *   clock <YYYY-MM-DD>  move the emulator's learning day to that day
 *   clock +<n>          move it n days past the real day
 *   clock clear         back to the real day
 *
 * The clock is the `devClock/relationshipLearning` document, which the
 * learning callables and getMevoraPicks read ONLY inside the Functions
 * emulator (FUNCTIONS_EMULATOR=true). A deployed function never looks at it,
 * and Firestore rules keep every client away from it — so there is no
 * production date override. It moves the learning day only; daily Picks keep
 * the real day.
 *
 * Emulator only: refuses to run unless FIRESTORE_EMULATOR_HOST is a loopback
 * address, so the Admin SDK cannot reach a cloud database at all.
 *
 * Usage, from the repo root (PowerShell), after `npm --prefix functions run build`:
 *
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   node tool/relationshipLearningDev.cjs status [uid] [--project mevora-d6ed0]
 *   node tool/relationshipLearningDev.cjs clock +1
 *   node tool/relationshipLearningDev.cjs clock clear
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

const argv = process.argv.slice(2);
const flagIndex = argv.indexOf("--project");
const projectId =
  flagIndex >= 0 ? argv[flagIndex + 1] : process.env.QA_PROJECT_ID || "mevora-d6ed0";
// Drop `--project <id>` only when it was given: with no flag, indexOf is -1 and
// `flagIndex + 1` would otherwise remove the command itself.
const [command, arg] =
  flagIndex >= 0 ? argv.filter((_, i) => i !== flagIndex && i !== flagIndex + 1) : argv;
const usage =
  "usage: node tool/relationshipLearningDev.cjs status [uid]|clock <YYYY-MM-DD|+n|clear> [--project <id>]";
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
const {getFirestore} = fromFunctions("firebase-admin/firestore");
const schedule = compiled("relationshipLearning/schedule.js");
const store = compiled("relationshipLearning/store.js");
const {corePosition} = compiled("relationshipLearning/coreSequence.js");

initializeApp({projectId});
const db = getFirestore();

const DAY_MS = 86_400_000;

async function status(uid) {
  const realToday = schedule.learningDayKey(Date.now());
  const clock = (await db.doc(store.LEARNING_DEV_CLOCK_DOC).get()).data()?.dateKey ?? null;
  const today = schedule.isDateKey(clock) ? clock : realToday;
  console.log(`real learning day : ${realToday} (Europe/Istanbul)`);
  console.log(`emulator clock    : ${clock ?? "(not set)"}`);
  if (!uid) return;
  const state = await store.loadLearningState(db, uid);
  const progress = schedule.coreProgress(state);
  const set = schedule.memberDailySet(state, today);
  console.log(`member ${uid}`);
  console.log(`  Core answered   : ${progress.answered} / ${progress.total}${progress.exhausted ? " (finished)" : ""}`);
  console.log(`  onboarding done : ${schedule.hasFinishedOnboarding(state)}`);
  console.log(`  set for ${today}: ${set.kind}, ${set.questions.length} question(s), ${set.questionSetId}`);
  for (const ref of set.questions) {
    const answered = state.answers[ref.id]?.version === ref.version;
    console.log(`    Q${String(corePosition(ref.id)).padStart(2)} ${answered ? "[x]" : "[ ]"} ${ref.id}`);
  }
}

async function clock(value) {
  const ref = db.doc(store.LEARNING_DEV_CLOCK_DOC);
  if (value === "clear") {
    await ref.delete();
    console.log("emulator learning clock cleared");
    return;
  }
  const dateKey = /^\+\d{1,3}$/.test(value ?? "")
    ? schedule.learningDayKey(Date.now() + Number(value.slice(1)) * DAY_MS)
    : value;
  if (!schedule.isDateKey(dateKey)) {
    console.error(usage);
    process.exit(2);
  }
  await ref.set({dateKey, setBy: "tool/relationshipLearningDev.cjs", setAtMs: Date.now()});
  console.log(`emulator learning clock set to ${dateKey}`);
}

const run = {status: () => status(arg), clock: () => clock(arg)}[command];
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
