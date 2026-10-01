#!/usr/bin/env node
/**
 * Emulator-only developer tool for the Humor Core sequence: the initial
 * fifteen and "Bugünün Mizah Turu" (the daily five).
 *
 *   status [member]          the product day (and the test clock); with a member,
 *                            where they stand in the canonical sequence
 *   today <member>           the entries that member has today, with V-numbers
 *   clock <YYYY-MM-DD>       move the emulator's product day to that day
 *   clock +<n>               move it n days past the real product day
 *   clock next               move it one day past wherever it is now
 *   clock clear              back to the real product day
 *   reset <member> --yes     make that member new to humor again: deletes ONLY
 *                            their users/{uid}/humor, humorInteractions and
 *                            humorDaily documents
 *
 * <member> is a uid, or an email when FIREBASE_AUTH_EMULATOR_HOST is set.
 * Add --all to a clock command to move the relationship-questions clock
 * (`devClock/relationshipLearning`) with it, so both features agree on the day.
 *
 * The clock is the `devClock/humorDaily` document, which the humor callables
 * read ONLY inside the Functions emulator (FUNCTIONS_EMULATOR=true). A
 * deployed function never looks at it, and Firestore rules keep every client
 * away from it — so there is no production date override.
 *
 * Emulator only: refuses to run unless FIRESTORE_EMULATOR_HOST is a loopback
 * address, so the Admin SDK cannot reach a cloud database at all.
 *
 * Usage, from the repo root (PowerShell), after `npm --prefix functions run build`:
 *
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"   # only for emails
 *   node tool/humorDailyDev.cjs status qa_user_a@mevora.test
 *   node tool/humorDailyDev.cjs clock next --all
 *   node tool/humorDailyDev.cjs clock clear --all
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

const usage =
  "usage: node tool/humorDailyDev.cjs status [member] | today <member> | " +
  "clock <YYYY-MM-DD|+n|next|clear> [--all] | reset <member> --yes   [--project <id>]";

const argv = process.argv.slice(2);
function takeFlag(name) {
  const index = argv.indexOf(name);
  if (index < 0) return false;
  argv.splice(index, 1);
  return true;
}
function takeOption(name) {
  const index = argv.indexOf(name);
  if (index < 0) return null;
  const [, value] = argv.splice(index, 2);
  return value ?? "";
}
const projectOption = takeOption("--project");
const projectId = projectOption ?? (process.env.QA_PROJECT_ID || "mevora-d6ed0");
const all = takeFlag("--all");
const confirmed = takeFlag("--yes");
const [command, arg] = argv;
if (!/^[a-z0-9][a-z0-9-]{2,62}$/.test(projectId) || !command || argv.length > 2) {
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
const daily = compiled("humor/daily.js");
const {DAILY_DEV_CLOCK_DOC} = compiled("humor/clock.js");
const {HUMOR_CORE, HUMOR_CORE_RELEASE, HUMOR_CORE_SEQUENCE, humorCorePosition} = compiled(
  "humor/coreSequence.js",
);
const core = compiled("humor/coreService.js");

/** The relationship-questions clock; written here only with --all. */
const LEARNING_DEV_CLOCK_DOC = "devClock/relationshipLearning";

initializeApp({projectId});
const db = getFirestore();

async function clockDay() {
  const stored = (await db.doc(DAILY_DEV_CLOCK_DOC).get()).data()?.dayId;
  return daily.isDayId(stored) ? stored : null;
}

/** A uid as given, or the uid behind an email (Auth emulator only). */
async function resolveMember(member) {
  if (!member) {
    console.error(usage);
    process.exit(2);
  }
  if (!member.includes("@")) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(member)) {
      console.error(`not a uid: ${member}`);
      process.exit(2);
    }
    return member;
  }
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  if (!authHost || !LOOPBACK_HOST.test(authHost)) {
    console.error(
      "an email needs FIREBASE_AUTH_EMULATOR_HOST set to a loopback emulator address " +
        "(e.g. 127.0.0.1:9099); or pass the uid",
    );
    process.exit(2);
  }
  const {getAuth} = fromFunctions("firebase-admin/auth");
  return (await getAuth().getUserByEmail(member)).uid;
}

const MARK = {rated: "[x]", waived: "[w]", deferred: "[~]", open: "[ ]"};

async function printDay() {
  const realToday = daily.canonicalDayId(Date.now());
  const clock = await clockDay();
  console.log(`real product day : ${realToday} (Europe/Istanbul)`);
  console.log(`emulator clock   : ${clock ?? "(not set)"}`);
  console.log(
    `sequence         : ${HUMOR_CORE_SEQUENCE.length} entries, ` +
      `${HUMOR_CORE.onboardingCount} first then ${HUMOR_CORE.dailyCount} a day, ` +
      `${HUMOR_CORE_RELEASE.released ? "released" : "DRAFT"}`,
  );
}

/** The view the callables would compute for [uid] right now. */
async function snapshotFor(uid) {
  // The service reads the test clock only inside the Functions emulator.
  process.env.FUNCTIONS_EMULATOR = "true";
  return core.loadHumorCoreSnapshot({db, uid, nowMs: Date.now()});
}

function printSet(snapshot) {
  const {set, progress} = snapshot;
  const label = set.kind === "onboarding" ? "initial calibration" : "daily five";
  console.log(
    `  set for ${set.dayId} : ${label}, ${progress.answeredCount}/${progress.total} done` +
      `${progress.completed ? " (complete)" : ""}`,
  );
  set.contentIds.forEach((id, index) => {
    const rating = snapshot.state.answers[id]?.rating;
    console.log(
      `    V${String(humorCorePosition(id)).padStart(2)} ${MARK[progress.statuses[index]]} ${id}` +
        `${rating ? `  ${rating}` : ""}`,
    );
  });
  if (set.contentIds.length === 0) {
    console.log(
      snapshot.exhausted
        ? "    (nothing left: every entry of the sequence is behind this member)"
        : "    (nothing today: the daily five start on the next product day)",
    );
  }
}

async function status(member) {
  await printDay();
  if (!member) return;
  const uid = await resolveMember(member);
  const snapshot = await snapshotFor(uid);
  const {state, onboarding} = snapshot;
  const rated = Object.keys(state.answers).length;
  const waived = Object.keys(state.waived).length;
  const next = HUMOR_CORE_SEQUENCE.find(
    (entry) => entry.active && !state.answers[entry.id] && !state.waived[entry.id],
  );
  console.log(`member ${uid}`);
  console.log(
    `  calibration      : ${onboarding.completedCount}/${onboarding.totalCount}` +
      `${onboarding.complete ? " (finished)" : ""}`,
  );
  console.log(`  rated / waived   : ${rated} / ${waived} of ${HUMOR_CORE_SEQUENCE.length}`);
  console.log(`  next open entry  : ${next ? `V${humorCorePosition(next.id)} ${next.id}` : "none"}`);
  console.log(`  completed days   : ${state.completedDays}`);
  if (state.migration && state.migration.from !== "none") {
    console.log(
      `  carried over     : ${state.migration.importedRatings} rating(s), old calibration ` +
        `${state.migration.legacyComplete ? "finished" : `at ${state.migration.legacyCompletedCount}`}`,
    );
  }
  printSet(snapshot);
  console.log("  legend: [x] rated  [~] media failed today  [w] waived  [ ] open");
}

async function today(member) {
  const uid = await resolveMember(member);
  printSet(await snapshotFor(uid));
}

async function clock(value) {
  const refs = [db.doc(DAILY_DEV_CLOCK_DOC)];
  if (all) refs.push(db.doc(LEARNING_DEV_CLOCK_DOC));
  const which = all ? "humor + relationship clocks" : "humor clock";
  if (value === "clear") {
    await Promise.all(refs.map((ref) => ref.delete()));
    console.log(`emulator ${which} cleared`);
    return;
  }
  const realToday = daily.canonicalDayId(Date.now());
  let dayId = value;
  if (value === "next") {
    dayId = daily.shiftDayId((await clockDay()) ?? realToday, 1);
  } else if (/^\+\d{1,3}$/.test(value ?? "")) {
    dayId = daily.shiftDayId(realToday, Number(value.slice(1)));
  }
  if (!daily.isDayId(dayId)) {
    console.error(usage);
    process.exit(2);
  }
  const stamp = {setBy: "tool/humorDailyDev.cjs", setAtMs: Date.now()};
  await db.doc(DAILY_DEV_CLOCK_DOC).set({dayId, ...stamp});
  if (all) await db.doc(LEARNING_DEV_CLOCK_DOC).set({dateKey: dayId, ...stamp});
  console.log(`emulator ${which} set to ${dayId}`);
}

async function reset(member) {
  const uid = await resolveMember(member);
  const collections = [
    `users/${uid}/humor`,
    `users/${uid}/humorInteractions`,
    `users/${uid}/humorDaily`,
  ];
  const snaps = await Promise.all(collections.map((name) => db.collection(name).get()));
  const total = snaps.reduce((sum, snap) => sum + snap.size, 0);
  collections.forEach((name, index) => console.log(`  ${name}: ${snaps[index].size} document(s)`));
  if (!confirmed) {
    console.log(`nothing deleted — pass --yes to delete these ${total} document(s) of ${uid}`);
    return;
  }
  for (const snap of snaps) {
    await Promise.all(snap.docs.map((doc) => doc.ref.delete()));
  }
  console.log(`deleted ${total} humor document(s) of ${uid}; they start at V1 again`);
}

const run = {
  status: () => status(arg),
  today: () => today(arg),
  clock: () => clock(arg),
  reset: () => reset(arg),
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
