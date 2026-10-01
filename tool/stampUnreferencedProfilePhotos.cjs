#!/usr/bin/env node
/**
 * Marks profile photos that left their profile before the mark existed.
 *
 * A ledger entry (users/{uid}/photoModeration/{imageId}) whose photo is not in
 * profiles/{uid}.photos is stamped `unreferencedSince` whenever the profile is
 * reconciled, and the daily profilePhotoOrphanSweep deletes what has been
 * stamped for longer than the grace period. A profile is only reconciled when
 * something writes it, so photos orphaned before that code was deployed stay
 * unmarked until their member next edits the profile — for an inactive member,
 * for ever. This walks every profile once and writes the missing stamps.
 *
 * It deletes nothing and changes no photo, status or profile field: only
 * `unreferencedSince` on ledger entries, set where the photo is off the
 * profile and cleared where a stamp is wrong. What it stamps waits out the
 * same grace period, counted from this run, and goes through the same sweep.
 *
 * Run it after the functions that know the stamp are deployed; before that the
 * stamps are harmless but nothing acts on them or keeps them up to date.
 *
 * Dry run (default) lists what would change; --confirm writes.
 *
 * Production (owner-run, Application Default Credentials):
 *   npm --prefix functions run build
 *   node tool/stampUnreferencedProfilePhotos.cjs --project mevora-d6ed0 [--confirm]
 *
 * Emulator: set FIRESTORE_EMULATOR_HOST.
 */
const path = require("node:path");

const functionsDir = path.join(__dirname, "..", "functions");
// Resolve firebase-admin (and its subpath exports) from functions/node_modules.
const req = require("node:module").createRequire(path.join(functionsDir, "package.json"));
const {initializeApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {stampUnreferencedPhotos} = require(path.join(functionsDir, "lib", "moderation", "photoOrphanSweep.js"));

function arg(name, fallback = null) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const project = arg("project");
  const confirm = process.argv.includes("--confirm");
  if (!project) {
    console.error("Usage: --project <id> [--confirm]");
    process.exit(2);
  }
  initializeApp({projectId: project});
  const db = getFirestore();

  const summary = {profiles: 0, members: 0, stamped: 0, cleared: 0, failed: 0};
  let last = null;
  for (;;) {
    let query = db.collection("profiles").orderBy("__name__").limit(200);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    last = page.docs[page.docs.length - 1];

    for (const doc of page.docs) {
      summary.profiles += 1;
      const uid = doc.id;
      try {
        const result = await stampUnreferencedPhotos(db, uid, {dryRun: !confirm});
        if (result.stamped.length === 0 && result.cleared.length === 0) continue;
        summary.members += 1;
        summary.stamped += result.stamped.length;
        summary.cleared += result.cleared.length;
        const verb = confirm ? "" : "would ";
        for (const imageId of result.stamped) console.log(`${verb}stamp ${uid}/${imageId}`);
        for (const imageId of result.cleared) console.log(`${verb}clear ${uid}/${imageId}`);
      } catch (error) {
        summary.failed += 1;
        console.log(`fail ${uid}: ${error instanceof Error ? error.message : error}`);
      }
    }
    if (page.size < 200) break;
  }
  console.log(JSON.stringify({...summary, mode: confirm ? "write" : "dry-run"}));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
