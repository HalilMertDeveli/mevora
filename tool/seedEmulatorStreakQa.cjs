#!/usr/bin/env node
/**
 * Puts one QA member's daily streak into a known state in the Firebase
 * Emulator Suite, so every streak transition can be checked through the real
 * app without touching the computer's clock.
 *
 * The app then opens through the normal code path — `recordDailyCheckIn` is
 * called exactly as in production and decides the outcome from the server
 * clock. This script only rewrites the stored starting point.
 *
 *   fresh           no streak document            → open app: day 1, "started"
 *   yesterday       4 days, last = yesterday       → open app: 5, "continued"
 *   gap             5 days, last = 3 days ago      → open app: 1, "reset", longest 9 kept
 *   personal-best   6 days = longest, last = yday  → open app: 7, new personal best
 *   show            print the stored streak, change nothing
 *
 * "Yesterday" is reckoned in --offset minutes from UTC (default 180, Istanbul),
 * which must match the device's zone for the result to read as intended.
 *
 * Safety: refuses to run unless both emulator hosts point at a local
 * emulator, like the other tool/seedEmulator*.cjs scripts. It never touches
 * production, and there is no callable or client path that does this.
 *
 * Usage (PowerShell, emulators already up):
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   node tool/seedEmulatorStreakQa.cjs yesterday
 *   node tool/seedEmulatorStreakQa.cjs gap --email qa_user_b@mevora.test
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";
const STATES = ["fresh", "yesterday", "gap", "personal-best", "show"];

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (!firestoreHost || !authHost) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST " +
      "must both be set. This script only ever writes to the Emulator Suite.",
  );
  process.exit(1);
}
for (const [name, value] of [
  ["FIRESTORE_EMULATOR_HOST", firestoreHost],
  ["FIREBASE_AUTH_EMULATOR_HOST", authHost],
]) {
  if (!/^(127\.0\.0\.1|localhost|0\.0\.0\.0|10\.0\.2\.2):\d+$/.test(value)) {
    console.error(`REFUSING TO RUN: ${name}="${value}" is not a local emulator host.`);
    process.exit(1);
  }
}

function parseArgs(argv) {
  const args = {state: null, email: "qa_user_a@mevora.test", offset: 180};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--email") args.email = argv[++i];
    else if (arg === "--offset") args.offset = Number(argv[++i]);
    else if (!args.state) args.state = arg;
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));
if (!STATES.includes(args.state) || !Number.isFinite(args.offset)) {
  console.error(`usage: node tool/seedEmulatorStreakQa.cjs <${STATES.join("|")}> [--email x] [--offset minutes]`);
  process.exit(1);
}

const fromFunctions = createRequire(path.join(__dirname, "..", "functions", "package.json"));
let admin;
try {
  admin = fromFunctions("firebase-admin");
} catch (_) {
  console.error("firebase-admin not found — run: npm --prefix functions ci");
  process.exit(1);
}
admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const {FieldValue} = admin.firestore;

const DAY_MS = 24 * 60 * 60 * 1000;
/** Local calendar day [daysAgo] days before today, in the chosen offset. */
function localDay(daysAgo) {
  return new Date(Date.now() + args.offset * 60 * 1000 - daysAgo * DAY_MS).toISOString().slice(0, 10);
}

function stateDoc(state) {
  const base = {
    schemaVersion: 1,
    lastTimezoneOffsetMinutes: args.offset,
    lastCheckInAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  switch (state) {
    case "yesterday":
      return {...base, currentStreak: 4, longestStreak: 10, totalCheckInDays: 20, lastCheckInDay: localDay(1)};
    case "gap":
      return {...base, currentStreak: 5, longestStreak: 9, totalCheckInDays: 20, lastCheckInDay: localDay(3)};
    case "personal-best":
      return {...base, currentStreak: 6, longestStreak: 6, totalCheckInDays: 6, lastCheckInDay: localDay(1)};
    default:
      return null;
  }
}

async function main() {
  let uid;
  try {
    uid = (await admin.auth().getUserByEmail(args.email)).uid;
  } catch (_) {
    console.error(`No emulator account for ${args.email}. Seed users first (tool/seedEmulatorQaUsers.cjs).`);
    process.exit(1);
  }
  const ref = db.doc(`users/${uid}/dailyStreak/current`);

  if (args.state === "fresh") {
    await ref.delete();
  } else if (args.state !== "show") {
    await ref.set(stateDoc(args.state));
  }

  const snap = await ref.get();
  const data = snap.data();
  console.log(`${args.email} (${uid}) today=${localDay(0)} offset=${args.offset}`);
  console.log(
    data
      ? `stored: current=${data.currentStreak} longest=${data.longestStreak} total=${data.totalCheckInDays} last=${data.lastCheckInDay}`
      : "stored: no streak document",
  );
  if (args.state !== "show") {
    console.log("Now cold-start the app (or sign in) to run the real check-in.");
  }
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
