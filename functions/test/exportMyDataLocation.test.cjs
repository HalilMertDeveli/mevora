const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {GeoPoint, Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * The personal data export promises, in the app ("Exact location ... excluded")
 * and in its own notice, that it holds no exact location.
 *
 * It did: `account` was the users/{uid} document, and the app mirrors the
 * member's position there as `location.latitude` / `location.longitude`. The
 * export is a JSON file the member saves and shares, so a coordinate in it is
 * a home address in a file that leaves the device.
 *
 * These run the real callable against the in-memory Firestore and scan the
 * whole result, so a coordinate cannot come back through another section.
 */

// backend.js registers a Storage trigger at load, which needs a bucket name.
process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-export-location",
  storageBucket: "demo-export-location.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-export-location";

// The callables bind getFirestore() / getAuth() at load, so the doubles go first.
const db = createFakeFirestore();
installFirebaseAdminStubs({db});
const {exportMyData} = require("../lib/backend.js");
const {withoutExactLocation} = require("../lib/privacy/exportLocation.js");

const UID = "uid-export";
// Distinctive on purpose: the scan below looks for these digits anywhere.
const LAT = 38.423734;
const LNG = 27.142826;
const GEOHASH = "swg7dp5k2x";
const SEEN_AT = Timestamp.fromMillis(1_790_000_000_000);

/** Every key, with its value, in a result — however deeply nested. */
function walk(value, visit) {
  if (value === null || typeof value !== "object") {
    return;
  }
  // Own properties, so a GeoPoint's `_latitude` is seen exactly as the
  // callable's encoder would send it.
  for (const [key, child] of Object.entries(value)) {
    visit(key, child);
    walk(child, visit);
  }
}

const EXACT_KEY = /^_?(lat|lng|lon|long|latitude|longitude|geohash|geopoint|coordinates|coords)$/i;

function assertNoExactLocation(result) {
  const leaks = [];
  walk(result, (key, value) => {
    if (EXACT_KEY.test(key)) leaks.push(`key ${key}`);
    if (value === LAT || value === LNG || value === GEOHASH) leaks.push(`value under ${key}`);
  });
  assert.deepEqual(leaks, []);
  const json = JSON.stringify(result);
  for (const needle of [String(LAT), String(LNG), GEOHASH]) {
    assert.equal(json.includes(needle), false, `export still contains ${needle}`);
  }
}

function seed(overrides = {}) {
  db.reset({
    [`users/${UID}`]: {
      uid: UID,
      displayName: "Ada",
      email: "ada@example.test",
      relationshipGoal: "long_term",
      location: {
        latitude: LAT,
        longitude: LNG,
        geohash: GEOHASH,
        city: "Izmir",
        country: "TR",
        updatedAt: SEEN_AT,
      },
    },
    [`profiles/${UID}`]: {uid: UID, displayName: "Ada", city: "Izmir"},
    [`userPreferences/${UID}`]: {maxDistanceKm: 50},
    [`userSettings/${UID}`]: {locationEnabled: true, lastLocationUpdate: SEEN_AT},
    [`userLocation/${UID}`]: {
      uid: UID,
      latitude: LAT,
      longitude: LNG,
      geohash: GEOHASH,
      updatedAt: SEEN_AT,
    },
    ...overrides,
  });
}

describe("exportMyData holds no exact location", () => {
  beforeEach(() => seed());

  it("drops the coordinates and geohash mirrored on the account document", async () => {
    const result = await callAs(exportMyData, UID);

    assertNoExactLocation(result);
  });

  it("keeps the coarse location the member already sees", async () => {
    const result = await callAs(exportMyData, UID);

    assert.equal(result.account.location.city, "Izmir");
    assert.equal(result.account.location.country, "TR");
    assert.equal(result.account.location.updatedAt.toMillis(), SEEN_AT.toMillis());
    assert.equal(result.profile.city, "Izmir");
    assert.deepEqual(result.location, {present: true, updatedAt: SEEN_AT, hasCoordinates: true});
  });

  it("leaves the rest of the export alone", async () => {
    const result = await callAs(exportMyData, UID);

    assert.equal(result.uid, UID);
    assert.equal(result.account.displayName, "Ada");
    assert.equal(result.account.email, "ada@example.test");
    // "relationshipGoal" contains "lat" and "lon"; only whole key names count.
    assert.equal(result.account.relationshipGoal, "long_term");
    assert.equal(result.preferences.maxDistanceKm, 50);
    assert.equal(result.settings.locationEnabled, true);
    assert.equal(result.settings.lastLocationUpdate.toMillis(), SEEN_AT.toMillis());
  });

  it("drops a GeoPoint, whatever the field is called", async () => {
    seed({
      [`users/${UID}`]: {
        uid: UID,
        location: {point: new GeoPoint(LAT, LNG), city: "Izmir"},
        lastKnownPosition: new GeoPoint(LAT, LNG),
      },
    });

    const result = await callAs(exportMyData, UID);

    assertNoExactLocation(result);
    assert.equal("lastKnownPosition" in result.account, false);
    assert.deepEqual(result.account.location, {city: "Izmir"});
  });

  it("drops coordinates nested in maps and lists, in any section", async () => {
    seed({
      [`users/${UID}`]: {
        uid: UID,
        location: {current: {coords: {lat: LAT, lng: LNG}, city: "Izmir"}},
        places: [{label: "home", latitude: LAT, longitude: LNG}, new GeoPoint(LAT, LNG)],
      },
      // Rules forbid these on a profile today; a legacy document may hold them.
      [`profiles/${UID}`]: {uid: UID, city: "Izmir", latitude: LAT, longitude: LNG, geohash: GEOHASH},
      [`userPreferences/${UID}`]: {origin: {geoHash: GEOHASH, Latitude: LAT, LONGITUDE: LNG}},
    });

    const result = await callAs(exportMyData, UID);

    assertNoExactLocation(result);
    assert.deepEqual(result.account.location, {current: {city: "Izmir"}});
    assert.deepEqual(result.account.places, [{label: "home"}]);
    assert.deepEqual(result.profile, {uid: UID, city: "Izmir"});
    assert.deepEqual(result.preferences, {origin: {}});
  });

  it("still answers for a member with no stored location", async () => {
    db.reset({[`users/${UID}`]: {uid: UID, displayName: "Ada"}});

    const result = await callAs(exportMyData, UID);

    assert.deepEqual(result.location, {present: false});
    assert.deepEqual(result.account, {uid: UID, displayName: "Ada"});
  });
});

describe("withoutExactLocation", () => {
  it("does not modify what it is given", () => {
    const input = {location: {latitude: LAT, longitude: LNG, city: "Izmir"}, tags: [{lat: LAT}]};
    const copy = JSON.parse(JSON.stringify(input));

    withoutExactLocation(input);

    assert.deepEqual(input, copy);
  });

  it("passes timestamps and scalars through untouched", () => {
    const output = withoutExactLocation({at: SEEN_AT, count: 3, name: "Ada", none: null, on: true});

    assert.equal(output.at, SEEN_AT);
    assert.deepEqual({...output, at: 0}, {at: 0, count: 3, name: "Ada", none: null, on: true});
  });

  it("matches whole key names only", () => {
    const input = {
      relationshipGoal: "long_term",
      translationLanguage: "tr",
      hasCoordinates: true,
      locationEnabled: true,
      lastLocationUpdate: 1,
      longTermIntent: true,
    };

    assert.deepEqual(withoutExactLocation(input), input);
  });

  it("returns null and undefined as they came", () => {
    assert.equal(withoutExactLocation(null), null);
    assert.equal(withoutExactLocation(undefined), undefined);
  });
});
