/**
 * Two-device mutual match, driven through the callable the app actually uses.
 *
 * `mutualLike.pipeline.test.mjs` proves the transaction *shape* by
 * re-implementing it. It never calls `recordDiscoveryDecision`, which is what
 * the Connect button invokes — a device run showed `recordSwipe` is not called
 * at all. So the function that decides whether two real users ever match had
 * no coverage: a regression in its reciprocity check, its gender gate or its
 * match write would have shipped with every suite green.
 *
 * This drives the deployed callable end to end against the emulators:
 * an opposite-sex pair, one like each, exactly one active match.
 *
 * Needs auth + firestore + functions, and functions/lib must be built:
 *   npm --prefix functions run build
 *   npx firebase emulators:exec --only auth,firestore,storage,functions \
 *     --project mevora-dev "npm --prefix firebase/tests test"
 */
import {after, before, describe, it} from "node:test";
import assert from "node:assert/strict";
import {initializeTestEnvironment} from "@firebase/rules-unit-testing";
import {doc, getDoc, setDoc, Timestamp} from "firebase/firestore";

const PROJECT_ID = "mevora-dev";
const AUTH_HOST = "127.0.0.1:9099";
const FUNCTIONS_HOST = "127.0.0.1:5001";
const REGION = "europe-west1";

// Same coordinates so the pair lands in the nearby tier, as the QA seed does.
const CITY = "Istanbul";
const LAT = 41.0082;
const LNG = 28.9784;

const stamp = Date.now();
const people = {
  a: {
    email: `mutual_a_${stamp}@mevora.test`,
    displayName: `MUTUAL_A_${stamp}`,
    gender: "male",
    interestedIn: "female",
    birthDate: new Date("1996-04-11T00:00:00Z"),
  },
  b: {
    email: `mutual_b_${stamp}@mevora.test`,
    displayName: `MUTUAL_B_${stamp}`,
    gender: "female",
    interestedIn: "male",
    birthDate: new Date("1997-08-23T00:00:00Z"),
  },
  // Wants women, is a man: B must not be reachable from here in either
  // direction, so the gender gate has a negative case with real documents.
  c: {
    email: `mutual_c_${stamp}@mevora.test`,
    displayName: `MUTUAL_C_${stamp}`,
    gender: "male",
    interestedIn: "female",
    birthDate: new Date("1995-01-05T00:00:00Z"),
  },
};

const PASSWORD = "MutualMatchTest2026";

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

/** Calls a callable on the Functions emulator as the given user. */
async function callAs(key, name, data) {
  const res = await fetch(
    `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${tokens[key]}`,
      },
      body: JSON.stringify({data}),
    },
  );
  const json = await res.json().catch(() => ({}));
  return {status: res.status, body: json};
}

function photoRecords(uid) {
  return [0, 1, 2].map((i) => ({
    id: `mm_photo_${i + 1}`,
    downloadUrl: `https://qa.invalid/${uid}/mm_photo_${i + 1}.jpg`,
    thumbUrl: null,
    order: i,
    isPrimary: i === 0,
    moderationStatus: "approved",
  }));
}

/** Seeds exactly what the discovery engine checks — nothing more. */
async function seed(db, key) {
  const person = people[key];
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
      moderatedBy: "mutual-match-test",
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
    bio: "Mutual match acceptance fixture.",
    gender: person.gender,
    birthDate: Timestamp.fromDate(person.birthDate),
    city: CITY,
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
    maxDistanceKm: 200,
    updatedAt: now,
  });

  await setDoc(doc(db, `userLocation/${uid}`), {
    uid,
    latitude: LAT,
    longitude: LNG,
    city: CITY,
    updatedAt: now,
  });
}

/** Runs `fn` against a Firestore client with rules disabled. */
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

const matchIdFor = (x, y) => [x, y].sort().join("_");

describe("two-device mutual match (recordDiscoveryDecision)", () => {
  it("the first like commits without creating a match", async () => {
    const res = await callAs("a", "recordDiscoveryDecision", {
      candidateUid: uids.b,
      action: "like",
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body?.result?.matched, false);

    const like = await priv((db) =>
      getDoc(doc(db, `likes/${uids.a}_${uids.b}`)),
    );
    assert.ok(like.exists(), "the like must be persisted");
    assert.equal(like.data().action, "like");

    const match = await priv((db) =>
      getDoc(doc(db, `matches/${matchIdFor(uids.a, uids.b)}`)),
    );
    assert.equal(match.exists(), false, "one-sided like must not match");
  });

  it("the reciprocal like creates exactly one active match", async () => {
    const res = await callAs("b", "recordDiscoveryDecision", {
      candidateUid: uids.a,
      action: "like",
    });

    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body?.result?.matched, true, "reciprocal like must match");

    const matchId = matchIdFor(uids.a, uids.b);
    assert.equal(
      res.body.result.matchId,
      matchId,
      "match id must be the canonical sorted pair",
    );

    const match = await priv((db) => getDoc(doc(db, `matches/${matchId}`)));
    assert.ok(match.exists(), "the match document must exist");
    assert.equal(match.data().isActive, true);
    assert.deepEqual(
      [...match.data().userIds].sort(),
      [uids.a, uids.b].sort(),
      "both users must be on the match",
    );
  });

  it("replaying the like leaves the single match intact", async () => {
    const before = await priv((db) =>
      getDoc(doc(db, `matches/${matchIdFor(uids.a, uids.b)}`)),
    );

    const res = await callAs("b", "recordDiscoveryDecision", {
      candidateUid: uids.a,
      action: "like",
    });
    // Already matched is a refusal, not a second match.
    assert.ok(
      res.status !== 200 || res.body?.result?.matched === true,
      JSON.stringify(res.body),
    );

    const after = await priv((db) =>
      getDoc(doc(db, `matches/${matchIdFor(uids.a, uids.b)}`)),
    );
    assert.equal(after.exists(), true);
    assert.equal(
      after.data().createdAt?.toMillis?.(),
      before.data().createdAt?.toMillis?.(),
      "the original match must not be replaced",
    );
  });

  it("refuses a like that fails the mutual gender gate", async () => {
    // C is a man who wants women; A is a man. Neither side's preference is
    // satisfied, so the like must be refused rather than silently stored.
    const res = await callAs("c", "recordDiscoveryDecision", {
      candidateUid: uids.a,
      action: "like",
    });

    assert.notEqual(res.status, 200, JSON.stringify(res.body));
    assert.match(
      JSON.stringify(res.body),
      /preference-mismatch/,
      "the gender gate must be the stated reason",
    );

    const like = await priv((db) =>
      getDoc(doc(db, `likes/${uids.c}_${uids.a}`)),
    );
    assert.equal(like.exists(), false, "a refused like must not be stored");
  });
});
