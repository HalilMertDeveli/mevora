/**
 * A third identity must never reach an A<->B match: not its document, its
 * messages, or its chat media. Also pins the fields that must stay
 * server-authoritative (compatibility snapshot) and the encrypted-only rule for
 * chat uploads.
 *
 * Run from the repo root (Windows):
 *   npx.cmd firebase emulators:exec --only firestore,storage --project mevora-dev "npm --prefix firebase/tests test"
 */
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {deleteObject, getBytes, ref, uploadBytes} from "firebase/storage";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const firestoreRules = readFileSync(resolve(root, "firestore.rules"), "utf8");
const storageRules = readFileSync(resolve(root, "storage.rules"), "utf8");

const A = "user-a";
const B = "user-b";
const C = "user-c"; // never a participant
const MATCH = "user-a_user-b";

const MATCH_DOC = {
  id: MATCH,
  userIds: [A, B],
  isActive: true,
  createdAt: "2026-09-22T00:00:00Z",
  matchedAt: "2026-09-22T00:00:00Z",
  compatibilityScore: 87,
  compatibilityCalculatedAt: "2026-09-22T00:00:00Z",
  compatibilitySnapshots: {[A]: 87, [B]: 87},
};

const CIPHERTEXT = new Uint8Array([0xde, 0xad, 0xbe, 0xef]);

const MESSAGE_DOC = {
  senderId: A,
  receiverId: B,
  type: "text",
  ciphertext: "BASE64-CIPHERTEXT",
  createdAt: "2026-09-22T00:01:00Z",
};

function hostPort(envVar, fallback) {
  const raw = process.env[envVar] || fallback;
  const [host, port] = String(raw).split(":");
  return {host: host || "127.0.0.1", port: Number(port)};
}

async function main() {
  const fs = hostPort("FIRESTORE_EMULATOR_HOST", "127.0.0.1:8080");
  const st = hostPort("FIREBASE_STORAGE_EMULATOR_HOST", "127.0.0.1:9199");
  process.env.FIRESTORE_EMULATOR_HOST = `${fs.host}:${fs.port}`;
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = `${st.host}:${st.port}`;

  const env = await initializeTestEnvironment({
    // Must match the emulator's project: firebase.json runs the Storage
    // emulator in singleProjectMode, which rejects another project's bucket.
    projectId: process.env.GCLOUD_PROJECT || "mevora-dev",
    firestore: {rules: firestoreRules, host: fs.host, port: fs.port},
    storage: {rules: storageRules, host: st.host, port: st.port},
  });

  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await db.doc(`matches/${MATCH}`).set(MATCH_DOC);
      await db.doc(`matches/${MATCH}/messages/m1`).set(MESSAGE_DOC);
      for (const uid of [A, B, C]) {
        await db.doc(`users/${uid}`).set({uid, isActive: true});
        await db.doc(`profiles/${uid}`).set({uid, displayName: uid, city: "Ankara"});
      }
      // A chat blob owned by A, scoped to the A<->B match.
      await uploadBytes(
        ref(context.storage(), `users/${A}/chat/${MATCH}/blob1`),
        CIPHERTEXT,
        {contentType: "application/octet-stream"},
      );
    });

    const a = env.authenticatedContext(A);
    const b = env.authenticatedContext(B);
    const c = env.authenticatedContext(C);
    const anon = env.unauthenticatedContext();

    // --- Firestore: match document -------------------------------------
    await assertSucceeds(a.firestore().doc(`matches/${MATCH}`).get());
    await assertSucceeds(b.firestore().doc(`matches/${MATCH}`).get());
    await assertFails(c.firestore().doc(`matches/${MATCH}`).get());
    await assertFails(anon.firestore().doc(`matches/${MATCH}`).get());

    // --- Firestore: messages -------------------------------------------
    await assertSucceeds(a.firestore().collection(`matches/${MATCH}/messages`).get());
    await assertFails(c.firestore().collection(`matches/${MATCH}/messages`).get());
    await assertFails(c.firestore().doc(`matches/${MATCH}/messages/m1`).get());
    await assertFails(anon.firestore().doc(`matches/${MATCH}/messages/m1`).get());

    // A third identity cannot inject a message, even addressed to a participant.
    await assertFails(
      c.firestore().doc(`matches/${MATCH}/messages/injected`).set({
        ...MESSAGE_DOC,
        senderId: C,
        receiverId: B,
      }),
    );
    // ...nor by forging the sender id.
    await assertFails(
      c.firestore().doc(`matches/${MATCH}/messages/forged`).set(MESSAGE_DOC),
    );
    await assertFails(c.firestore().doc(`matches/${MATCH}/messages/m1`).update({ciphertext: "x"}));
    await assertFails(c.firestore().doc(`matches/${MATCH}/messages/m1`).delete());

    // --- Firestore: match mutation --------------------------------------
    await assertFails(c.firestore().doc(`matches/${MATCH}`).update({isActive: false}));
    await assertFails(
      c.firestore().doc(`matches/${MATCH}`).update({userIds: [A, C]}),
    );
    // No client may manufacture or destroy a match.
    await assertFails(
      a.firestore().doc(`matches/${A}_${C}`).set({userIds: [A, C], isActive: true}),
    );
    await assertFails(a.firestore().doc(`matches/${MATCH}`).delete());

    // --- Compatibility stays server-authoritative -----------------------
    await assertFails(
      c.firestore().doc(`matches/${MATCH}`).update({compatibilityScore: 99}),
    );
    // Even a participant cannot rewrite the frozen snapshot.
    await assertFails(
      a.firestore().doc(`matches/${MATCH}`).update({compatibilityScore: 99}),
    );
    await assertFails(
      a.firestore().doc(`matches/${MATCH}`).update({
        compatibilitySnapshots: {[A]: 99, [B]: 12},
      }),
    );
    await assertFails(
      a.firestore().doc(`matches/${MATCH}`).update({
        compatibilityCalculatedAt: "2030-01-01T00:00:00Z",
      }),
    );

    // --- Privileged profile fields --------------------------------------
    for (const field of [
      {subscriptionStatus: "active"},
      {isVerified: true},
      {isAdmin: true},
      {profileModerationStatus: "approved"},
      {isDiscoverable: true},
    ]) {
      await assertFails(c.firestore().doc(`profiles/${C}`).update(field));
    }

    // --- Storage: chat media -------------------------------------------
    const blob = (ctx) => ref(ctx.storage(), `users/${A}/chat/${MATCH}/blob1`);
    await assertSucceeds(getBytes(blob(a))); // owner + participant
    await assertSucceeds(getBytes(blob(b))); // participant
    await assertFails(getBytes(blob(c))); // third identity
    await assertFails(getBytes(blob(anon)));
    await assertFails(deleteObject(blob(c)));

    // A third identity cannot write into a match it is not part of.
    await assertFails(
      uploadBytes(
        ref(c.storage(), `users/${C}/chat/${MATCH}/evil`),
        CIPHERTEXT,
        {contentType: "application/octet-stream"},
      ),
    );

    // Chat uploads must be client-encrypted blobs: plaintext media is rejected
    // even for a legitimate participant, so E2EE cannot silently degrade.
    await assertFails(
      uploadBytes(
        ref(a.storage(), `users/${A}/chat/${MATCH}/plain.jpg`),
        CIPHERTEXT,
        {contentType: "image/jpeg"},
      ),
    );
    await assertSucceeds(
      uploadBytes(
        ref(a.storage(), `users/${A}/chat/${MATCH}/blob2`),
        CIPHERTEXT,
        {contentType: "application/octet-stream"},
      ),
    );

    console.log("thirdUser.isolation.ok");
  } finally {
    await env.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
