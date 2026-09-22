const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  DISTANCE_BUCKET_KM,
  coarseDistanceKm,
  coarseDistanceLabel,
  consumeDistanceQuota,
  distanceDisclosureDecision,
} = require("../lib/geo/coarseDistance.js");

const A = "user-a";
const B = "user-b";
const C = "user-c";

const activeMatchAB = {userIds: [A, B], isActive: true};

describe("getDistanceLabel authorization", () => {
  it("rejects an arbitrary unrelated target", async () => {
    const decision = await distanceDisclosureDecision({
      uid: A,
      otherUid: C,
      matchData: undefined,
      matchExists: false,
      blocked: false,
    });
    assert.equal(decision, "not-matched");
  });

  it("allows an active match", async () => {
    const decision = await distanceDisclosureDecision({
      uid: A,
      otherUid: B,
      matchData: activeMatchAB,
      matchExists: true,
      blocked: false,
    });
    assert.equal(decision, "allow");
  });

  it("rejects an unmatched (inactive) former match", async () => {
    const decision = await distanceDisclosureDecision({
      uid: A,
      otherUid: B,
      matchData: {userIds: [A, B], isActive: false},
      matchExists: true,
      blocked: false,
    });
    assert.equal(decision, "not-matched");
  });

  it("rejects a blocked relationship even when the match is active", async () => {
    const decision = await distanceDisclosureDecision({
      uid: A,
      otherUid: B,
      matchData: activeMatchAB,
      matchExists: true,
      blocked: true,
    });
    assert.equal(decision, "blocked");
  });

  it("rejects a match document the caller is not actually in", async () => {
    const decision = await distanceDisclosureDecision({
      uid: C,
      otherUid: B,
      matchData: activeMatchAB,
      matchExists: true,
      blocked: false,
    });
    assert.equal(decision, "not-matched");
  });

  it("rejects self-targeting and an empty target", async () => {
    assert.equal(
      await distanceDisclosureDecision({
        uid: A, otherUid: A, matchData: activeMatchAB, matchExists: true, blocked: false,
      }),
      "invalid-target",
    );
    assert.equal(
      await distanceDisclosureDecision({
        uid: A, otherUid: "", matchData: undefined, matchExists: false, blocked: false,
      }),
      "invalid-target",
    );
  });
});

describe("distance quantisation", () => {
  it("never discloses a value finer than the bucket width", () => {
    for (let km = 1; km < 100; km += 0.37) {
      const bucket = coarseDistanceKm(km);
      assert.equal(bucket % DISTANCE_BUCKET_KM, 0, `km=${km} produced ${bucket}`);
    }
  });

  it("collapses sub-kilometre distances to a single band", () => {
    assert.equal(coarseDistanceKm(0), 0);
    assert.equal(coarseDistanceKm(0.05), 0);
    assert.equal(coarseDistanceKm(0.99), 0);
    assert.equal(coarseDistanceLabel(0.4, "en").labelEn, "Less than 1 km away");
  });

  it("clamps far distances to one open-ended band", () => {
    assert.equal(coarseDistanceKm(100), 100);
    assert.equal(coarseDistanceKm(5000), 100);
    assert.equal(coarseDistanceLabel(4000, "en").labelEn, "100+ km away");
  });

  it("keeps the existing label shape in both languages", () => {
    assert.equal(coarseDistanceLabel(23.7, "en").label, "20 km away");
    assert.equal(coarseDistanceLabel(23.7, "tr").label, "20 km uzakta");
  });

  it("returns null for a missing or invalid distance", () => {
    assert.equal(coarseDistanceKm(null), null);
    assert.equal(coarseDistanceKm(undefined), null);
    assert.equal(coarseDistanceKm(NaN), null);
    assert.equal(coarseDistanceKm(-3), null);
    assert.equal(coarseDistanceLabel(null, "en").bucketKm, null);
  });

  it("discloses no coordinates, geohash or raw kilometres", () => {
    const payload = coarseDistanceLabel(42.123456, "en");
    const keys = Object.keys(payload).sort();
    assert.deepEqual(keys, ["bucketKm", "label", "labelEn"]);
    const serialized = JSON.stringify(payload);
    for (const leak of ["latitude", "longitude", "geohash", "42.12", "42.1"]) {
      assert.equal(serialized.includes(leak), false, `payload leaked ${leak}`);
    }
  });
});

describe("trilateration abuse probe", () => {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const haversineKm = (lat1, lng1, lat2, lng2) => {
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const h =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
  };

  // The attacker's own userLocation is writable, so they can query from any
  // vantage point they like. This is the exact attack B-03 describes.
  const target = {lat: 41.0082, lng: 28.9784};
  const vantages = [
    {lat: 41.05, lng: 28.90},
    {lat: 40.96, lng: 29.05},
    {lat: 41.02, lng: 29.12},
  ];

  /** Grid search for every point consistent with the observed readings. */
  function candidateArea(readings, quantise) {
    let consistent = 0;
    let total = 0;
    for (let lat = 40.90; lat <= 41.12; lat += 0.004) {
      for (let lng = 28.85; lng <= 29.15; lng += 0.004) {
        total += 1;
        const ok = readings.every(({from, value}) =>
          quantise(haversineKm(from.lat, from.lng, lat, lng)) === value);
        if (ok) consistent += 1;
      }
    }
    return {consistent, total};
  }

  const oldQuantise = (km) => (km < 1 ? 0 : km >= 100 ? 100 : Math.round(km));
  const newQuantise = (km) => coarseDistanceKm(km);

  it("the old 1 km disclosure pinned the target to a tiny area", () => {
    const readings = vantages.map((from) => ({
      from,
      value: oldQuantise(haversineKm(from.lat, from.lng, target.lat, target.lng)),
    }));
    const {consistent} = candidateArea(readings, oldQuantise);
    assert.ok(consistent > 0, "sanity: the true point must be consistent");
    assert.ok(consistent < 40, `old disclosure left only ${consistent} candidate cells`);
  });

  it("the quantised disclosure leaves a materially larger candidate area", () => {
    const oldReadings = vantages.map((from) => ({
      from,
      value: oldQuantise(haversineKm(from.lat, from.lng, target.lat, target.lng)),
    }));
    const newReadings = vantages.map((from) => ({
      from,
      value: newQuantise(haversineKm(from.lat, from.lng, target.lat, target.lng)),
    }));
    const before = candidateArea(oldReadings, oldQuantise).consistent;
    const after = candidateArea(newReadings, newQuantise).consistent;
    assert.ok(after > before * 10, `expected a far larger area, got ${before} -> ${after}`);
  });

  it("doubling the probe count does not recover the old precision", () => {
    const many = [
      ...vantages,
      {lat: 41.10, lng: 28.95},
      {lat: 40.93, lng: 28.88},
      {lat: 41.07, lng: 29.10},
    ];
    const reading = (quantise) => (from) => ({
      from,
      value: quantise(haversineKm(from.lat, from.lng, target.lat, target.lng)),
    });
    const three = candidateArea(vantages.map(reading(newQuantise)), newQuantise).consistent;
    const six = candidateArea(many.map(reading(newQuantise)), newQuantise).consistent;
    const preciseThree = candidateArea(vantages.map(reading(oldQuantise)), oldQuantise).consistent;

    assert.ok(six <= three, "sanity: more constraints cannot enlarge the area");
    // Six quantised probes are still worse for the attacker than three precise
    // ones were: extra sampling cannot buy back resolution that is not emitted.
    assert.ok(
      six > preciseThree,
      `six quantised probes (${six} cells) should stay coarser than three precise ones (${preciseThree})`,
    );
  });
});

describe("distance rate limit", () => {
  function fakeDb(initial) {
    let stored = initial;
    return {
      writes: [],
      doc(path) {
        assert.match(path, /^users\/[^/]+\/rateLimits\/distanceLabel$/);
        return {path};
      },
      async runTransaction(fn) {
        const self = this;
        return fn({
          async get() {
            return {data: () => stored};
          },
          set(_ref, data) {
            stored = data;
            self.writes.push(data);
          },
        });
      },
    };
  }

  it("starts a fresh window on the first call", async () => {
    const db = fakeDb(undefined);
    await consumeDistanceQuota(db, A, 1000);
    assert.equal(db.writes[0].count, 1);
  });

  it("increments within the window", async () => {
    const db = fakeDb({windowStart: 1000, count: 5});
    await consumeDistanceQuota(db, A, 2000);
    assert.equal(db.writes[0].count, 6);
  });

  it("reports rate-limited once the window budget is spent, and records nothing", async () => {
    const db = fakeDb({windowStart: 1000, count: 60});
    assert.equal(await consumeDistanceQuota(db, A, 2000), "rate-limited");
    assert.equal(db.writes.length, 0);
  });

  it("resets after the window elapses", async () => {
    const db = fakeDb({windowStart: 1000, count: 60});
    await consumeDistanceQuota(db, A, 1000 + 60 * 60 * 1000 + 1);
    assert.equal(db.writes[0].count, 1);
  });
});
