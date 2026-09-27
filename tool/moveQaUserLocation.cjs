/**
 * Moves a QA user's `userLocation/{uid}` document in the Firebase Emulator
 * Suite so the discovery distance gate can be exercised by hand.
 *
 * Refuses to run unless the Firestore emulator host is set, so it can never
 * reach a cloud project. `userLocation` is the ONLY coordinate source discovery
 * reads — the `users/{uid}.location` mirror and the client-written `geohash`
 * are not consulted by the backend, so writing them here would prove nothing.
 *
 * usage:
 *   node tool/moveQaUserLocation.cjs <email|uid> <preset|lat,lng>
 *   node tool/moveQaUserLocation.cjs qa_core_b_123@mevora.test ankara
 *   node tool/moveQaUserLocation.cjs qa_core_b_123@mevora.test 41.05,29.02
 *
 * env: FIRESTORE_EMULATOR_HOST (required), FIREBASE_AUTH_EMULATOR_HOST
 *      (required to resolve an email), QA_PROJECT (default mevora-d6ed0)
 */
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("refusing to run: set FIRESTORE_EMULATOR_HOST");
  process.exit(2);
}

/** firebase-admin lives in functions/node_modules, not at the repo root. */
function requireAdmin() {
  const {createRequire} = require("node:module");
  const path = require("node:path");
  const fromFunctions = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  try {
    return fromFunctions("firebase-admin");
  } catch (_) {
    try {
      return require("firebase-admin");
    } catch (_err) {
      console.error(
        "firebase-admin not found — run: npm --prefix functions ci",
      );
      process.exit(2);
    }
  }
}
const admin = requireAdmin();

const PROJECT = process.env.QA_PROJECT || "mevora-d6ed0";

/** Reference point the seed uses, so the printed distance is meaningful. */
const ORIGIN = {city: "Istanbul", latitude: 41.0082, longitude: 28.9784};

const PRESETS = {
  istanbul: ORIGIN,
  kadikoy: {city: "Kadikoy", latitude: 40.9833, longitude: 29.0333},
  gebze: {city: "Gebze", latitude: 40.8028, longitude: 29.4307},
  bursa: {city: "Bursa", latitude: 40.1826, longitude: 29.0665},
  ankara: {city: "Ankara", latitude: 39.9334, longitude: 32.8597},
  izmir: {city: "Izmir", latitude: 38.4237, longitude: 27.1428},
  london: {city: "London", latitude: 51.5072, longitude: -0.1276},
  tokyo: {city: "Tokyo", latitude: 35.6762, longitude: 139.6503},
  buenosaires: {city: "Buenos Aires", latitude: -34.6037, longitude: -58.3816},
};

/** Same formula the backend uses (functions/src/backend.ts haversineKm). */
function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return 2 * R * Math.asin(Math.sqrt(a));
}

function parseTarget(raw) {
  const key = String(raw ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
  if (PRESETS[key]) {
    return PRESETS[key];
  }
  const parts = String(raw ?? "").split(",");
  if (parts.length === 2) {
    const latitude = Number(parts[0]);
    const longitude = Number(parts[1]);
    if (
      Number.isFinite(latitude) &&
      Number.isFinite(longitude) &&
      Math.abs(latitude) <= 90 &&
      Math.abs(longitude) <= 180
    ) {
      return {city: `${latitude},${longitude}`, latitude, longitude};
    }
  }
  return null;
}

async function resolveUid(auth, who) {
  if (!who.includes("@")) {
    return who;
  }
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    console.error(
      "refusing to resolve an email without FIREBASE_AUTH_EMULATOR_HOST",
    );
    process.exit(2);
  }
  const user = await auth.getUserByEmail(who);
  return user.uid;
}

(async () => {
  const [who, target] = process.argv.slice(2);
  if (!who || !target) {
    console.error(
      "usage: node tool/moveQaUserLocation.cjs <email|uid> <preset|lat,lng>",
    );
    console.error(`presets: ${Object.keys(PRESETS).join(", ")}`);
    process.exit(2);
  }
  const place = parseTarget(target);
  if (!place) {
    console.error(`unknown target: ${target}`);
    console.error(`presets: ${Object.keys(PRESETS).join(", ")}`);
    process.exit(2);
  }

  admin.initializeApp({projectId: PROJECT});
  const db = admin.firestore();
  const uid = await resolveUid(admin.auth(), who);

  await db.doc(`userLocation/${uid}`).set(
    {
      uid,
      latitude: place.latitude,
      longitude: place.longitude,
      city: place.city,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  const km = haversineKm(
    ORIGIN.latitude,
    ORIGIN.longitude,
    place.latitude,
    place.longitude,
  );
  console.log(`moved ${uid} -> ${place.city} (${place.latitude}, ${place.longitude})`);
  console.log(`distance from ${ORIGIN.city}: ${km.toFixed(1)} km`);
  process.exit(0);
})().catch((error) => {
  console.error(error && error.message ? error.message : error);
  process.exit(1);
});
