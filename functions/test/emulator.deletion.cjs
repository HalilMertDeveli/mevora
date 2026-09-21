/**
 * Emulator validation for the account-deletion lifecycle.
 *
 * Not part of `npm test` — it needs the Auth, Firestore and Storage emulators.
 * Run from the repository root:
 *
 *   firebase emulators:exec --only auth,firestore,storage --project demo-mevora \
 *     "node functions/test/emulator.deletion.cjs"
 *
 * The unit suite uses an in-memory Firestore double; this proves the same code
 * against real query semantics (array-contains, orderBy, batched writes) and real
 * Storage prefix deletion, and that no composite index is required.
 */
const assert = require("node:assert/strict");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-mevora";
const BUCKET = `${PROJECT_ID}.appspot.com`;

initializeApp({projectId: PROJECT_ID, storageBucket: BUCKET});

const db = getFirestore();
const bucket = getStorage().bucket();

const {
  anonymizeDeletedUserMessages,
  clearLastMessagePreviewIfAuthored,
  deleteSupportAttachmentsForUser,
  deleteUserScopedRemnants,
  flagModerationRecordsForDeletedUser,
} = require("../lib/automation/accountDataCleanup.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

const A = "emuUserA";
const B = "emuUserB";

const checks = [];
function check(name, fn) {
  checks.push([name, fn]);
}

async function seed() {
  await db.doc(`users/${A}`).set({uid: A, displayName: "A"});
  await db.doc(`profiles/${A}`).set({isDiscoverable: true});
  await db.doc(`authRateLimits/spotify_${A}`).set({count: 3, windowStart: Date.now()});

  await db.doc("matches/emuM1").set({
    userIds: [A, B],
    isActive: true,
    lastMessage: "see you then",
  });
  await db.doc("matches/emuM1/messages/m1").set({
    senderId: A, receiverId: B, type: "text", text: "hi from A",
    imageStoragePath: `users/${A}/chat/emuM1/a.bin`, createdAt: new Date(1000),
  });
  await db.doc("matches/emuM1/messages/m2").set({
    senderId: B, receiverId: A, type: "text", text: "hi from B", createdAt: new Date(2000),
  });
  await db.doc("matches/emuM1/messages/m3").set({
    senderId: A, receiverId: B, type: "text", text: "see you then", createdAt: new Date(3000),
  });

  await db.doc("supportTickets/emuT1").set({
    userId: A, subject: "help", attachments: ["support/emuT1/a.jpg"],
  });
  await db.doc("supportTickets/emuT9").set({
    userId: B, subject: "help", attachments: ["support/emuT9/b.jpg"],
  });

  await db.doc("reports/emuR1").set({reporterId: B, reportedUserId: A, reason: "abuse"});
  await db.doc("reports/emuR2").set({reporterId: A, reportedUserId: "emuUserC", reason: "spam"});

  await Promise.all([
    bucket.file(`users/${A}/profile/photos/p1.jpg`).save("a", {contentType: "image/jpeg"}),
    bucket.file("support/emuT1/a.jpg").save("a", {contentType: "image/jpeg"}),
    bucket.file("support/emuT1/unrecorded.png").save("a", {contentType: "image/png"}),
    bucket.file("support/emuT9/b.jpg").save("b", {contentType: "image/jpeg"}),
  ]);

  await getAuth().createUser({uid: A});
  await getAuth().createUser({uid: B});
}

/** The parts of deleteUserAccount this script exercises, in production order. */
async function runDeletionPass() {
  const matches = await db.collection("matches").where("userIds", "array-contains", A).get();
  for (const match of matches.docs) {
    await anonymizeDeletedUserMessages(db, A, match.ref);
    await clearLastMessagePreviewIfAuthored(A, match.ref);
    await match.ref.set({isActive: false, participantNames: {[A]: "Deleted account"}}, {merge: true});
  }
  await flagModerationRecordsForDeletedUser(db, A);
  const support = await deleteSupportAttachmentsForUser(db, bucket, A);
  const tickets = await db.collection("supportTickets").where("userId", "==", A).get();
  await Promise.all(tickets.docs.map((d) => d.ref.delete()));
  await deleteUserScopedRemnants(db, A);
  await bucket.deleteFiles({prefix: `users/${A}/`});
  await Promise.all([db.doc(`users/${A}`).delete(), db.doc(`profiles/${A}`).delete()]);
  // Mirrors the callable: an already-removed Auth record is not a failure.
  await getAuth().deleteUser(A).catch((error) => {
    if (error.code !== "auth/user-not-found") throw error;
  });
  return support;
}

check("peer messages survive, deleting user's are tombstoned", async () => {
  const [m1, m2, m3] = await Promise.all([
    db.doc("matches/emuM1/messages/m1").get(),
    db.doc("matches/emuM1/messages/m2").get(),
    db.doc("matches/emuM1/messages/m3").get(),
  ]);
  assert.equal(m1.get("deleted"), true);
  assert.equal(m1.get("text"), "");
  assert.equal(m1.get("imageStoragePath"), null);
  assert.equal(m3.get("deleted"), true);
  assert.equal(m2.get("text"), "hi from B", "peer message must survive");
  assert.notEqual(m2.get("deleted"), true);
});

check("match preview cleared when the deleted user wrote last", async () => {
  assert.equal((await db.doc("matches/emuM1").get()).get("lastMessage"), "");
});

check("moderation reports retained and flagged", async () => {
  const [r1, r2] = await Promise.all([
    db.doc("reports/emuR1").get(),
    db.doc("reports/emuR2").get(),
  ]);
  assert.equal(r1.exists, true, "report against the deleted user must survive");
  assert.equal(r1.get("reportedUserDeleted"), true);
  assert.equal(r2.exists, true, "report filed by the deleted user must survive");
  assert.equal(r2.get("reporterDeleted"), true);
});

check("support attachments removed for the deleting user only", async () => {
  const [mine] = await bucket.getFiles({prefix: "support/emuT1/"});
  const [theirs] = await bucket.getFiles({prefix: "support/emuT9/"});
  assert.equal(mine.length, 0, "owner's attachments (recorded and unrecorded) removed");
  assert.equal(theirs.length, 1, "another user's attachment must survive");
});

check("uid-keyed remnants removed", async () => {
  assert.equal((await db.doc(`authRateLimits/spotify_${A}`).get()).exists, false);
});

check("verification passes against real Auth, Firestore and Storage", async (support) => {
  const result = await verifyAccountDeletion({uid: A, supportTicketIds: support.ticketIds}, db);
  assert.deepEqual(result.issues, [], `unexpected issues: ${result.issues.join(", ")}`);
  assert.equal(result.complete, true);
});

check("verification reports a real remnant", async () => {
  await db.doc(`users/${A}`).set({uid: A});
  const result = await verifyAccountDeletion({uid: A}, db);
  assert.equal(result.complete, false);
  assert.ok(result.issues.includes(`firestore_remnant:users/${A}`));
  await db.doc(`users/${A}`).delete();
});

async function main() {
  await seed();
  const support = await runDeletionPass();
  // Idempotency: the whole pass again over already-cleaned state.
  await runDeletionPass().catch((error) => {
    throw new Error(`second deletion pass threw: ${error}`);
  });

  let failures = 0;
  for (const [name, fn] of checks) {
    try {
      await fn(support);
      console.log(`  PASS  ${name}`);
    } catch (error) {
      failures += 1;
      console.error(`  FAIL  ${name}\n        ${error.message}`);
    }
  }
  console.log(`\n${checks.length - failures}/${checks.length} emulator checks passed`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
