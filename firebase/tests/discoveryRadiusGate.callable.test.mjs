/**
 * The discovery distance gate, driven through the callable the deck actually
 * uses (`getDiscoveryCandidates`).
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
 * Fixtures sit at deliberate distances from the viewer so one matrix covers
 * every rung of the ladder:
 *   near ~3 km, mid ~40 km, far ~12,300 km (Buenos Aires)
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
const AUTH_HOST = "127.0.0.1:9099";
const FUNCTIONS_HOST = "127.0.0.1:5001";
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

async function candidatesFor(radiusKm) {
  const res = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/getDiscoveryCandidates`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${tokens.viewer}`,
      },
      body: JSON.stringify({data: {radiusKm, limit: 20, includeDebug: true}}),
    },
  );
  const json = await res.json().catch(() => ({}));
  assert.equal(res.status, 200, `HTTP ${res.status}: ${JSON.stringify(json)}`);
  const result = json.result ?? {};
  const byUid = new Map((result.items ?? []).map((item) => [item.uid, item]));
  /** Which fixtures came back, in the order the deck would show them. */
  const names = (result.items ?? [])
    .map((item) => Object.keys(uids).find((key) => uids[key] === item.uid))
    .filter(Boolean);
  return {result, byUid, names, debug: result.debug ?? {}};
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
    firestore: {host: "127.0.0.1", port: 8080},
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

  it("excludes a candidate on the far side of the planet at the widest rung", async () => {
    // The whole reason this suite exists. 100 km is as wide as the gate opens,
    // so if Buenos Aires is absent here it is absent everywhere.
    const {byUid, debug} = await candidatesFor(100);
    assert.equal(byUid.has(uids.far), false, "Buenos Aires must not be in the deck");
    assert.equal(debug.gateKm, 100);
    assert.ok(
      (debug.rejectionReasons?.distance_over_radius ?? 0) >= 1,
      `expected a distance rejection, got ${JSON.stringify(debug.rejectionReasons)}`,
    );
  });

  it("returns both in-range candidates at the widest rung, nearest first", async () => {
    const {byUid, names} = await candidatesFor(100);
    assert.equal(byUid.has(uids.near), true, "3 km candidate must be in the deck");
    assert.equal(byUid.has(uids.mid), true, "40 km candidate must be in the deck");
    assert.deepEqual(
      names.filter((n) => n === "near" || n === "mid"),
      ["near", "mid"],
      "the closer candidate must be shown first",
    );
  });

  it("narrows the deck as the rung narrows, and widens it again", async () => {
    // "Start with the nearest, widen from there" — one fixture crossing the
    // boundary in both directions is what makes the gate progressive rather
    // than a single fixed cutoff.
    const tight = await candidatesFor(5);
    assert.equal(tight.byUid.has(uids.near), true, "3 km candidate at a 5 km gate");
    assert.equal(tight.byUid.has(uids.mid), false, "40 km candidate must be gated out at 5 km");
    assert.equal(tight.byUid.has(uids.far), false);
    assert.equal(tight.debug.gateKm, 5);

    const wider = await candidatesFor(50);
    assert.equal(wider.byUid.has(uids.near), true);
    assert.equal(wider.byUid.has(uids.mid), true, "40 km candidate must return at a 50 km gate");
    assert.equal(wider.byUid.has(uids.far), false);
    assert.equal(wider.debug.gateKm, 50);
  });

  it("never discloses a distance past the ceiling for anyone it returns", async () => {
    // A returned item carrying distanceKm 100 used to be the tell that someone
    // arbitrarily far had been let in. Now 100 can only ever mean 95-100 km.
    const {result} = await candidatesFor(100);
    for (const item of result.items ?? []) {
      if (item.distanceKm == null) continue;
      assert.ok(
        item.distanceKm <= 100,
        `${item.uid} disclosed ${item.distanceKm} km`,
      );
    }
  });

  it("keeps the gate on under the Functions emulator", async () => {
    // relationshipMatch.ts disables its own 100 km rule whenever
    // FUNCTIONS_EMULATOR is set, which makes that gate invisible to exactly the
    // QA that would catch a regression. This suite runs under the emulator, so
    // a green run here is the assertion that discovery did not copy it.
    const {byUid} = await candidatesFor(100);
    assert.equal(byUid.has(uids.far), false);
  });
});
