#!/usr/bin/env node
/**
 * Renders the display variants (thumb 320px, card 720px) for profile photos
 * that were approved before publishApprovedPhoto started generating them.
 * New approvals get variants automatically; this only catches up the backlog.
 * Clients fall back to the original for any photo without variants, so the
 * backfill is an optimisation, never a prerequisite.
 *
 * Authority is unchanged: a photo is only processed when the server-owned
 * ledger (users/{uid}/photoModeration/{imageId}) says approved AND names the
 * same published storagePath as the profile. Variants are rendered from the
 * published original, recorded in the ledger first, then projected onto
 * profiles/{uid}.photos — the same order the moderation pipeline uses, so
 * enforceProfilePhotoModeration agrees with the result.
 *
 * Run it only after the functions that know about cardUrl are deployed:
 * the old reconciler does not treat cardUrl as server-owned.
 *
 * Dry run (default) lists what would change; --confirm writes.
 *
 * Production (owner-run, Application Default Credentials):
 *   npm --prefix functions run build
 *   node tool/backfillProfilePhotoVariants.cjs --project mevora-d6ed0 --bucket <bucket> [--limit 200] [--confirm]
 *
 * Emulator: set FIRESTORE_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST.
 */
const path = require("node:path");

const functionsDir = path.join(__dirname, "..", "functions");
// Resolve firebase-admin (and its subpath exports) from functions/node_modules.
const req = require("node:module").createRequire(path.join(functionsDir, "package.json"));
const {initializeApp} = req("firebase-admin/app");
const {getFirestore} = req("firebase-admin/firestore");
const {getStorage} = req("firebase-admin/storage");
const {publishPhotoVariants} = require(path.join(functionsDir, "lib", "moderation", "photoVariants.js"));
const {isPublishedStoragePath, ledgerRef} = require(path.join(functionsDir, "lib", "moderation", "photoModerationLedger.js"));

function arg(name, fallback = null) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

async function main() {
  const project = arg("project");
  const bucketName = arg("bucket");
  const limit = Number(arg("limit", "500"));
  const confirm = process.argv.includes("--confirm");
  if (!project || !bucketName) {
    console.error("Usage: --project <id> --bucket <name> [--limit N] [--confirm]");
    process.exit(2);
  }
  initializeApp({projectId: project, storageBucket: bucketName});
  const db = getFirestore();
  const bucket = getStorage().bucket(bucketName);

  const summary = {profiles: 0, candidates: 0, done: 0, skipped: 0, failed: 0};
  let last = null;
  while (summary.candidates < limit) {
    let query = db.collection("profiles").orderBy("__name__").limit(200);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) break;
    last = page.docs[page.docs.length - 1];

    for (const doc of page.docs) {
      summary.profiles += 1;
      const uid = doc.id;
      const photos = Array.isArray(doc.get("photos")) ? doc.get("photos") : [];
      for (const photo of photos) {
        if (summary.candidates >= limit) break;
        const imageId = String(photo?.id ?? "");
        if (!imageId || photo.moderationStatus !== "approved") continue;
        if (photo.thumbUrl && photo.cardUrl) continue;
        if (!isPublishedStoragePath(uid, photo.storagePath)) continue;
        summary.candidates += 1;

        const ledgerSnap = await ledgerRef(db, uid, imageId).get();
        const ledger = ledgerSnap.data() ?? {};
        if (ledger.status !== "approved" || ledger.storagePath !== photo.storagePath) {
          summary.skipped += 1;
          console.log(`skip ${uid}/${imageId}: ledger ${ledger.status ?? "missing"} / path mismatch`);
          continue;
        }
        if (!confirm) {
          console.log(`would render ${uid}/${imageId} from ${photo.storagePath}`);
          continue;
        }
        try {
          const [source] = await bucket.file(photo.storagePath).download({validation: false});
          const variants = await publishPhotoVariants({bucket, uid, imageId, source});
          const thumbUrl = variants.thumb?.url ?? null;
          const cardUrl = variants.card?.url ?? null;
          if (!thumbUrl && !cardUrl) {
            summary.failed += 1;
            console.log(`fail ${uid}/${imageId}: not decodable`);
            continue;
          }
          // Ledger first (the authority), then the profile projection —
          // and only if the photo is still the same approved photo.
          await ledgerRef(db, uid, imageId).set({thumbUrl, cardUrl}, {merge: true});
          await db.runTransaction(async (tx) => {
            const ref = db.doc(`profiles/${uid}`);
            const snap = await tx.get(ref);
            const current = Array.isArray(snap.get("photos")) ? snap.get("photos") : [];
            const next = current.map((p) =>
              String(p?.id ?? "") === imageId &&
              p.moderationStatus === "approved" &&
              p.storagePath === photo.storagePath
                ? {...p, thumbUrl, cardUrl}
                : p);
            tx.set(ref, {photos: next}, {merge: true});
          });
          summary.done += 1;
          console.log(`done ${uid}/${imageId}: thumb ${variants.thumb?.bytes ?? "-"} B, card ${variants.card?.bytes ?? "-"} B`);
        } catch (error) {
          summary.failed += 1;
          console.log(`fail ${uid}/${imageId}: ${error instanceof Error ? error.message : error}`);
        }
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
