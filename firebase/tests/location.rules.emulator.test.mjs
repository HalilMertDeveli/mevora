/**
 * Firestore emulator rules for exact GPS isolation.
 * Run from the repo root (Windows):
 *   npx.cmd firebase emulators:exec --only firestore --project mevora-dev "npm --prefix firebase/tests test"
 */
import {readFileSync} from "node:fs";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const rules = readFileSync(resolve(root, "firestore.rules"), "utf8");

const gpsA = {
  uid: "user-a",
  latitude: 41.0082,
  longitude: 28.9784,
  geohash: "sxk9",
};

const gpsB = {
  uid: "user-b",
  latitude: 39.9334,
  longitude: 32.8597,
  geohash: "swdx",
};

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
  }

  const env = await initializeTestEnvironment({
    projectId: "mevora-rules-gps",
    firestore: {
      rules,
      host: "127.0.0.1",
      port: Number(String(process.env.FIRESTORE_EMULATOR_HOST).split(":")[1] || 8080),
    },
  });

  try {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("userLocation/user-a").set(gpsA);
      await context.firestore().doc("users/user-a").set({
        uid: "user-a",
        location: {
          latitude: gpsA.latitude,
          longitude: gpsA.longitude,
          updatedAt: "2026-08-18T00:00:00Z",
        },
      });
    });

    const a = env.authenticatedContext("user-a").firestore();
    const b = env.authenticatedContext("user-b").firestore();
    const anon = env.unauthenticatedContext().firestore();

    await assertSucceeds(a.doc("userLocation/user-a").get());
    await assertFails(b.doc("userLocation/user-a").get());
    await assertFails(anon.doc("userLocation/user-a").get());
    await assertFails(b.doc("users/user-a").get());
    await assertFails(anon.doc("users/user-a").get());

    await assertFails(
      b.doc("userLocation/user-a").set({
        ...gpsA,
        latitude: 1,
      }),
    );
    await assertFails(
      a.doc("userLocation/user-b").set(gpsB),
    );
    await assertFails(
      a.doc("userLocation/user-a").set({
        ...gpsA,
        uid: "user-b",
      }),
    );
    await assertFails(anon.doc("userLocation/user-a").set(gpsA));

    await assertSucceeds(
      a.doc("userLocation/user-a").set({
        ...gpsA,
        latitude: 41.01,
      }),
    );

    await assertFails(
      a.doc("profiles/user-a").set({
        uid: "user-a",
        displayName: "Ada",
        latitude: 41.0082,
        longitude: 28.9784,
      }),
    );
    await assertFails(
      a.doc("profiles/user-a").set({
        uid: "user-a",
        displayName: "Ada",
        location: {latitude: 41.0082, longitude: 28.9784},
      }),
    );
    await assertSucceeds(
      a.doc("profiles/user-a").set({
        uid: "user-a",
        displayName: "Ada",
        city: "Istanbul",
      }),
    );

    console.log("location.rules.emulator.ok");
  } finally {
    await env.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
