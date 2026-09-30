#!/usr/bin/env node
/**
 * Emulator-only developer tool for "Bugünün Mizah Turu" (daily humor sets).
 *
 *   status              today's canonical day (and the test clock), and the
 *                       manifest for that day if one exists
 *   publish             publish today's set now (same code as the admin-only
 *                       `publishDailyHumorSet` callable), or report not-ready
 *   clock <YYYY-MM-DD>  move the emulator's daily clock to that day
 *   clock +<n>          move it n days past the real canonical day
 *   clock clear         back to the real canonical day
 *
 * The clock is the `devClock/humorDaily` document, which the daily callables
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
 *   node tool/humorDailyDev.cjs status [--project mevora-d6ed0]
 *   node tool/humorDailyDev.cjs clock +1
 *   node tool/humorDailyDev.cjs clock clear
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
const [command, arg] = argv.filter((_, i) => i !== flagIndex && i !== flagIndex + 1);
const usage =
  "usage: node tool/humorDailyDev.cjs status|publish|clock <YYYY-MM-DD|+n|clear> [--project <id>]";
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
const daily = compiled("humor/daily.js");
const service = compiled("humor/dailyService.js");

initializeApp({projectId});
const db = getFirestore();

async function status() {
  const realToday = daily.canonicalDayId(Date.now());
  const clock = (await db.doc(service.DAILY_DEV_CLOCK_DOC).get()).data()?.dayId ?? null;
  const today = clock ?? realToday;
  console.log(`real canonical day : ${realToday} (Europe/Istanbul)`);
  console.log(`emulator clock     : ${clock ?? "(not set)"}`);
  const manifest = (await db.doc(service.humorDailySetPath(today)).get()).data();
  if (!manifest) {
    console.log(`manifest ${today}  : none yet (published on the first eligible request)`);
    return;
  }
  console.log(`manifest ${today}  : ${manifest.status}, version ${manifest.version ?? "-"}`);
  (manifest.contentIds ?? []).forEach((id, i) =>
    console.log(`  ${String(i + 1).padStart(2)}. ${id}  ${(manifest.categories ?? [])[i] ?? ""}`),
  );
}

async function publish() {
  // The service reads the test clock only inside the Functions emulator.
  process.env.FUNCTIONS_EMULATOR = "true";
  const nowMs = Date.now();
  const dayId = await service.resolveDailyToday(db, nowMs);
  const result = await service.ensureDailySet({
    db,
    dayId,
    nowMs,
    publishedBy: "dev-tool",
    force: true,
  });
  console.log(
    result.status === "published"
      ? `${dayId}: published (${result.created ? "new" : "already existed"}), ` +
          `${result.manifest.contentIds.length} items`
      : `${dayId}: NOT READY — eligible pool ${result.eligiblePoolSize}`,
  );
}

async function clock(value) {
  const ref = db.doc(service.DAILY_DEV_CLOCK_DOC);
  if (value === "clear") {
    await ref.delete();
    console.log("emulator daily clock cleared");
    return;
  }
  const realToday = daily.canonicalDayId(Date.now());
  const dayId = /^\+\d{1,3}$/.test(value ?? "")
    ? daily.shiftDayId(realToday, Number(value.slice(1)))
    : value;
  if (!daily.isDayId(dayId)) {
    console.error(usage);
    process.exit(2);
  }
  await ref.set({dayId, setBy: "tool/humorDailyDev.cjs", setAtMs: Date.now()});
  console.log(`emulator daily clock set to ${dayId}`);
}

const run = {status, publish, clock: () => clock(arg)}[command];
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
