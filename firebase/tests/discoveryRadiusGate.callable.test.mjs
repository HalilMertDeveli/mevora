/**
 * The discovery distance gate, driven through the callable that actually puts
 * people in front of a member: Mevora Picks (`getMevoraPicks`). The open-ended
 * deck callable (`getDiscoveryCandidates`) is retired; the last test pins that.
 *
 * Why this exists: distance used to be computed, ranked on and labelled, but it
 * never excluded anyone. A runtime probe showed a viewer in Istanbul was served
 * a candidate in Buenos Aires — 12,300 km — reported as `distanceKm: 100` and
 * "100+ km away", and a mutual like across that distance created a real match.
 * The disclosure bucket flattens everything at or beyond 100 km to exactly 100,
 * so a gate written against the *disclosed* figure would have looked correct in
 * every log line while excluding nobody. Unit tests pin the predicate; only this
 * suite proves the deployed callable drops the candidate.
 *
 * Fixtures sit at deliberate distances from the viewer and are otherwise
 * identical, so the only thing that can keep one of them out is distance:
 *   near ~3 km, mid ~40 km, far ~12,300 km (Buenos Aires)
 * Picks reach past the preferred radius (50 km) only up to the hard ceiling
 * (100 km), so near and mid are in, far is out.
 *
 * Needs auth + firestore + functions, and functions/lib must be built:
 *   npm --prefix functions run build
 *   npx firebase emulators:exec --only auth,firestore,functions \
 *     --project mevora-dev "npm --prefix firebase/tests run test:radius"
 */
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import {initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, setDoc, Timestamp} from "firebase/firestore";

const PROJECT_ID = "mevora-dev";
// emulators:exec exports the hosts it started; the defaults are the CI ports.
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? "127.0.0.1:9099";
const FUNCTIONS_HOST = process.env.MEVORA_FUNCTIONS_EMULATOR_HOST ?? "127.0.0.1:5001";
const [FIRESTORE_HOST, FIRESTORE_PORT] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");
const REGION = "europe-west1";

/** Viewer origin — the coordinates the QA seed uses. */
const ORIGIN = {city: "Istanbul", latitude: 41.0082, longitude: 28.9784};

/**
 * Offsets are pure latitude so the distance is just the meridian arc
 * (1 degree = 111.19 km) and the expected values stay obvious by inspection.
 */
const PLACES = {
  viewer: {...ORIGIN},
  near: {city: "Istanbul-near", latitude: 41.0352, longitude: 28.9784},
  mid: {city: "Istanbul-mid", latitude: 41.3682, longitude: 28.9784},
  far: {city: "Buenos Aires", latitude: -34.6037, longitude: -58.3816},
};

/** Independent of the backend implementation on purpose. */
function haversineKm(a, b) {
  const R = 6371;
  const dLat = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLng = ((b.longitude - a.longitude) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.latitude * Math.PI) / 180) *
      Math.cos((b.latitude * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

const stamp = Date.now();
const people = {
  viewer: {
    email: `radius_viewer_${stamp}@mevora.test`,
    displayName: `RADIUS_VIEWER_${stamp}`,
    gender: "male",
    interestedIn: "female",
    birthDate: new Date("1996-04-11T00:00:00Z"),
  },
  near: {
    email: `radius_near_${stamp}@mevora.test`,
    displayName: `RADIUS_NEAR_${stamp}`,
    gender: "female",
    interestedIn: "male",
    birthDate: new Date("1997-08-23T00:00:00Z"),
  },
  mid: {
    email: `radius_mid_${stamp}@mevora.test`,
    displayName: `RADIUS_MID_${stamp}`,
    gender: "female",
    interestedIn: "male",
    birthDate: new Date("1995-02-14T00:00:00Z"),
  },
  far: {
    email: `radius_far_${stamp}@mevora.test`,
    displayName: `RADIUS_FAR_${stamp}`,
    gender: "female",
    interestedIn: "male",
    birthDate: new Date("1994-11-02T00:00:00Z"),
  },
};

const PASSWORD = "RadiusGateTest2026";

let env;
const uids = {};
const tokens = {};

async function authRest(path, body) {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:${path}?key=fake-api-key`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify(body),
    },
  );
  const json = await res.json();
  if (!res.ok) {
    throw new Error(`auth ${path} failed: ${JSON.stringify(json)}`);
  }
  return json;
}

async function call(name, data = {}) {
  const res = await fetch(`http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${tokens.viewer}`,
    },
    body: JSON.stringify({data}),
  });
  const json = await res.json().catch(() => ({}));
  return {status: res.status, json};
}

/** Today's Picks for the viewer. The batch is stable for the day. */
async function picks() {
  const {status, json} = await call("getMevoraPicks");
  assert.equal(status, 200, `HTTP ${status}: ${JSON.stringify(json)}`);
  const result = json.result ?? {};
  const byUid = new Map((result.picks ?? []).map((item) => [item.uid, item]));
  return {result, byUid};
}

function photoRecords(uid) {
  return [0, 1, 2].map((i) => ({
    id: `rg_photo_${i + 1}`,
    downloadUrl: `https://qa.invalid/${uid}/rg_photo_${i + 1}.jpg`,
    thumbUrl: null,
    order: i,
    isPrimary: i === 0,
    moderationStatus: "approved",
  }));
}

/** Seeds exactly what the discovery engine checks — nothing more. */
async function seed(db, key) {
  const person = people[key];
  const place = PLACES[key];
  const uid = uids[key];
  const photos = photoRecords(uid);
  const now = Timestamp.now();

  // Ledger first: enforceProfilePhotoModeration treats it as the authority and
  // would otherwise revert the approved photos to pending.
  for (const photo of photos) {
    await setDoc(doc(db, `users/${uid}/photoModeration/${photo.id}`), {
      imageId: photo.id,
      status: "approved",
      reason: null,
      moderatedBy: "radius-gate-test",
      moderatedAt: now,
      storagePath: `users/${uid}/profile/photos/${photo.id}.jpg`,
      downloadUrl: photo.downloadUrl,
      thumbUrl: null,
      updatedAt: now,
    });
  }

  await setDoc(doc(db, `users/${uid}`), {
    uid,
    email: person.email,
    isSmokeTestUser: true,
    accountStatus: "active",
    isBanned: false,
    isSuspended: false,
    onboardingComplete: true,
    lastActiveAt: now,
    createdAt: now,
    updatedAt: now,
  });

  await setDoc(doc(db, `profiles/${uid}`), {
    uid,
    displayName: person.displayName,
    name: person.displayName,
    bio: "Radius gate acceptance fixture.",
    gender: person.gender,
    birthDate: Timestamp.fromDate(person.birthDate),
    city: place.city,
    photos,
    // Identical for everyone: the pair clears the Picks quality floor on
    // shared goal, interests and lifestyle, so only distance can differ.
    relationshipGoal: "longTerm",
    interests: ["hiking", "jazz", "cooking", "chess"],
    lifestyle: ["nonsmoker", "earlybird"],
    isDiscoverable: true,
    profileCompleted: true,
    profileModerationStatus: "approved",
    createdAt: now,
    updatedAt: now,
  });

  await setDoc(doc(db, `userPreferences/${uid}`), {
    uid,
    interestedIn: person.interestedIn,
    minAge: 18,
    maxAge: 60,
    updatedAt: now,
  });

  await setDoc(doc(db, `userLocation/${uid}`), {
    uid,
    latitude: place.latitude,
    longitude: place.longitude,
    city: place.city,
    updatedAt: now,
  });
}

async function priv(fn) {
  let out;
  await env.withSecurityRulesDisabled(async (ctx) => {
    out = await fn(ctx.firestore());
  });
  return out;
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {host: FIRESTORE_HOST, port: Number(FIRESTORE_PORT)},
  });

  for (const key of Object.keys(people)) {
    const signUp = await authRest("signUp", {
      email: people[key].email,
      password: PASSWORD,
      returnSecureToken: true,
    });
    uids[key] = signUp.localId;
    tokens[key] = signUp.idToken;
  }

  await priv(async (db) => {
    for (const key of Object.keys(people)) {
      await seed(db, key);
    }
  });
});

after(async () => {
  if (env) await env.cleanup();
});

describe("discovery hard distance gate, through the real callable", () => {
  it("places the fixtures where the matrix below assumes", () => {
    // If these drift, every expectation in this file is meaningless.
    const near = haversineKm(PLACES.viewer, PLACES.near);
    const mid = haversineKm(PLACES.viewer, PLACES.mid);
    const far = haversineKm(PLACES.viewer, PLACES.far);
    assert.ok(near > 2 && near < 4, `near is ${near.toFixed(1)} km`);
    assert.ok(mid > 38 && mid < 42, `mid is ${mid.toFixed(1)} km`);
    assert.ok(far > 12000, `far is ${far.toFixed(0)} km`);
  });

  it("returns both in-range candidates", async () => {
    // The control for the next test: same profile, same preferences, only
    // the location differs.
    const {byUid, result} = await picks();
    assert.equal(byUid.has(uids.near), true, `3 km candidate must be picked: ${JSON.stringify(result)}`);
    assert.equal(byUid.has(uids.mid), true, "40 km candidate must be picked");
  });

  it("excludes a candidate on the far side of the planet", async () => {
    // The whole reason this suite exists.
    const {byUid} = await picks();
    assert.equal(byUid.has(uids.far), false, "Buenos Aires must not be picked");
  });

  it("never discloses a distance past the ceiling for anyone it returns", async () => {
    // A returned item carrying distanceKm 100 used to be the tell that someone
    // arbitrarily far had been let in. Now 100 can only ever mean 95-100 km.
    const {result} = await picks();
    for (const item of result.picks ?? []) {
      if (item.distanceKm == null) continue;
      assert.ok(item.distanceKm <= 100, `${item.uid} disclosed ${item.distanceKm} km`);
    }
  });

  it("keeps the gate on under the Functions emulator", async () => {
    // relationshipMatch.ts disables its own 100 km rule whenever
    // FUNCTIONS_EMULATOR is set, which makes that gate invisible to exactly the
    // QA that would catch a regression. This suite runs under the emulator, so
    // a green run here is the assertion that discovery did not copy it.
    const {byUid} = await picks();
    assert.equal(byUid.has(uids.far), false);
  });

  it("offers no open-ended deck beside Picks", async () => {
    // The paged deck had no daily cap; it must refuse, not page.
    for (const name of ["getDiscoveryCandidates", "getDiscoveryFeed"]) {
      const {status, json} = await call(name, {radiusKm: 100, limit: 20, cursor: ""});
      assert.equal(status, 400, `${name}: HTTP ${status} ${JSON.stringify(json)}`);
      assert.equal(json.error?.status, "FAILED_PRECONDITION");
      assert.equal(json.error?.message, "discovery-deck-retired");
    }
  });
});
