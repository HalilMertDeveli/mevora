const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  sortByBoostVisibility,
  capBoostedDensity,
  boostAdvantageApplies,
  computeDiscoveryRankScore,
  compareDiscoveryCandidates,
} = require("../lib/boost/ranking.js");
const {BOOST_STRENGTH} = require("../lib/boost/config.js");

const RADIUS = 25;

/** Discovery quantises distanceKm to 5 km buckets before ranking. */
function candidate(uid, compatibilityScore, distanceKm, extra = {}) {
  return {
    uid,
    compatibilityScore,
    distanceKm,
    relationshipAlignedCount: 0,
    musicRankingBonus: 0,
    musicCompatibilityScore: 0,
    ...extra,
  };
}

const order = (items, boostedUids, radius = RADIUS) =>
  sortByBoostVisibility(items, new Set(boostedUids), radius).map((i) => i.uid);

describe("boost advantage gating", () => {
  it("a candidate who did not buy Boost never gets the advantage", () => {
    const item = candidate("a", 90, 5);
    assert.equal(boostAdvantageApplies(item, new Set()), false);
  });

  it("a boosted candidate above the compatibility floor gets the advantage", () => {
    const item = candidate("a", BOOST_STRENGTH.minCompatibility, 5);
    assert.equal(boostAdvantageApplies(item, new Set(["a"])), true);
  });

  it("a boosted candidate below the compatibility floor gets nothing", () => {
    const item = candidate("a", BOOST_STRENGTH.minCompatibility - 1, 5);
    assert.equal(boostAdvantageApplies(item, new Set(["a"])), false);
  });

  it("the advantage is exactly priorityBonus points of score", () => {
    const item = candidate("a", 80, 5);
    const plain = computeDiscoveryRankScore(item, new Set(), RADIUS);
    const boosted = computeDiscoveryRankScore(item, new Set(["a"]), RADIUS);
    assert.equal(boosted - plain, BOOST_STRENGTH.priorityBonus);
  });
});

describe("boost gives a real but bounded ranking advantage", () => {
  it("1. similar compatibility: the boosted candidate ranks ahead", () => {
    const items = [candidate("normal", 72, 5), candidate("boosted", 70, 5)];
    assert.deepEqual(order(items, ["boosted"]), ["boosted", "normal"]);
  });

  it("3. same compatibility and distance: the boosted candidate ranks ahead", () => {
    const items = [candidate("normal", 70, 5), candidate("boosted", 70, 5)];
    assert.deepEqual(order(items, ["boosted"]), ["boosted", "normal"]);
  });

  it("2. a far better normal candidate stays ahead of a weak boosted one", () => {
    const items = [candidate("normal_95", 95, 5), candidate("boosted_50", 50, 5)];
    assert.deepEqual(order(items, ["boosted_50"]), ["normal_95", "boosted_50"]);
  });

  it("2b. paying cannot outrank a compatibility gap wider than the bonus", () => {
    const gapBeyondBonus = BOOST_STRENGTH.priorityBonus + 5;
    const items = [
      candidate("normal", 60 + gapBeyondBonus, 5),
      candidate("boosted", 60, 5),
    ];
    assert.deepEqual(order(items, ["boosted"]), ["normal", "boosted"]);
  });

  it("2c. inside the bonus band the boosted candidate does win", () => {
    const gapInsideBonus = BOOST_STRENGTH.priorityBonus - 5;
    const items = [
      candidate("normal", 60 + gapInsideBonus, 5),
      candidate("boosted", 60, 5),
    ];
    assert.deepEqual(order(items, ["boosted"]), ["boosted", "normal"]);
  });

  it("4. distance still outranks Boost: a nearer normal candidate wins", () => {
    // Boost's geographic lever is eligibility reach (effectiveRadiusKm), not a
    // discount that would let it jump an unbounded compatibility gap.
    const items = [candidate("near_normal", 50, 5), candidate("far_boosted", 50, 15)];
    assert.deepEqual(order(items, ["far_boosted"]), ["near_normal", "far_boosted"]);
  });

  it("boost never reorders across question-alignment tiers", () => {
    const items = [
      candidate("aligned_normal", 40, 5, {relationshipAlignedCount: 3}),
      candidate("unaligned_boosted", 95, 5, {relationshipAlignedCount: 0}),
    ];
    assert.deepEqual(order(items, ["unaligned_boosted"]), [
      "aligned_normal",
      "unaligned_boosted",
    ]);
  });
});

describe("expired and inactive boosts", () => {
  // loadActiveBoostedUserIds only returns uids whose boost is status=active
  // AND expiresAt > now, so an expired boost simply is not in the set.
  it("10/11. a uid absent from the active set gets no advantage", () => {
    const items = [candidate("normal", 70, 5), candidate("expired", 70, 5)];
    assert.deepEqual(order(items, []), ["expired", "normal"]);
    const plain = computeDiscoveryRankScore(items[1], new Set(), RADIUS);
    const asIfBoosted = computeDiscoveryRankScore(items[1], new Set(["expired"]), RADIUS);
    assert.equal(asIfBoosted - plain, BOOST_STRENGTH.priorityBonus);
    assert.equal(boostAdvantageApplies(items[1], new Set()), false);
  });
});

describe("12. boosted profiles cannot monopolise a page", () => {
  it("honours the density cap when many boosted candidates compete", () => {
    const items = [];
    for (let i = 0; i < 6; i += 1) {
      items.push(candidate(`B${i}`, 70, 5));
    }
    for (let i = 0; i < 6; i += 1) {
      items.push(candidate(`N${i}`, 72, 5));
    }
    const boostedUids = items.filter((i) => i.uid.startsWith("B")).map((i) => i.uid);
    const result = order(items, boostedUids);

    // Every window of `densityWindow` consecutive results, across the part of
    // the page where normal candidates are still available, holds at most
    // `maxPerWindow` boosted profiles.
    const lastNormal = result.map((u) => u[0]).lastIndexOf("N");
    for (let i = 0; i + BOOST_STRENGTH.densityWindow <= lastNormal + 1; i += 1) {
      const window = result.slice(i, i + BOOST_STRENGTH.densityWindow);
      const count = window.filter((u) => u.startsWith("B")).length;
      assert.ok(
        count <= BOOST_STRENGTH.maxPerWindow,
        `window ${window.join(",")} holds ${count} boosted`,
      );
    }
  });

  it("a single boosted candidate is not pushed back by the cap", () => {
    const items = [candidate("N0", 60, 5), candidate("B0", 60, 5)];
    assert.deepEqual(order(items, ["B0"]), ["B0", "N0"]);
  });

  it("the cap only ever delays a boosted candidate, never promotes one", () => {
    const items = [candidate("N0", 90, 5), candidate("B0", 40, 5)];
    // B0 is below the floor, so it has no advantage and must stay last.
    assert.deepEqual(order(items, ["B0"]), ["N0", "B0"]);
  });
});

describe("13. non-boosted baseline ordering is unchanged", () => {
  it("with no active boosts the order is the plain ranking order", () => {
    const items = [
      candidate("c", 70, 10),
      candidate("a", 90, 5),
      candidate("b", 60, 5),
      candidate("d", 80, 15, {relationshipAlignedCount: 2}),
    ];
    const expected = [...items]
      .sort((x, y) => compareDiscoveryCandidates(x, y, new Set(), RADIUS))
      .map((i) => i.uid);
    assert.deepEqual(order(items, []), expected);
  });

  it("boosting one candidate does not reshuffle the others", () => {
    const items = [
      candidate("n1", 90, 5),
      candidate("n2", 80, 5),
      candidate("n3", 70, 5),
      candidate("b1", 60, 10),
    ];
    const withoutBoost = order(items, []).filter((u) => u !== "b1");
    const withBoost = order(items, ["b1"]).filter((u) => u !== "b1");
    assert.deepEqual(withBoost, withoutBoost);
  });
});

describe("14. compatibility stays truthful", () => {
  it("ranking never mutates the candidate payload", () => {
    const items = [candidate("boosted", 70, 5), candidate("normal", 72, 5)];
    const before = JSON.parse(JSON.stringify(items));
    sortByBoostVisibility(items, new Set(["boosted"]), RADIUS);
    assert.deepEqual(items, before);
  });

  it("the compatibility shown to the viewer is identical either way", () => {
    const item = candidate("a", 63, 5);
    const plain = sortByBoostVisibility([item], new Set(), RADIUS)[0];
    const boosted = sortByBoostVisibility([item], new Set(["a"]), RADIUS)[0];
    assert.equal(plain.compatibilityScore, 63);
    assert.equal(boosted.compatibilityScore, 63);
  });
});

describe("15. deterministic ordering", () => {
  it("identical inputs produce an identical page", () => {
    const build = () => [
      candidate("a", 70, 5),
      candidate("b", 70, 5),
      candidate("c", 70, 5),
      candidate("d", 70, 5),
    ];
    const first = order(build(), ["b", "d"]);
    const second = order(build(), ["b", "d"]);
    assert.deepEqual(first, second);
  });

  it("input order does not change the result", () => {
    const base = [
      candidate("a", 70, 5),
      candidate("b", 75, 5),
      candidate("c", 70, 10),
    ];
    const reversed = [...base].reverse();
    assert.deepEqual(order(base, ["a"]), order(reversed, ["a"]));
  });
});

describe("5-9. eligibility safety", () => {
  const src = (name) =>
    fs.readFileSync(path.join(__dirname, "..", "src", name), "utf8");

  it("ranking can only reorder candidates it is given, never add them", () => {
    const items = [candidate("a", 70, 5), candidate("b", 70, 5)];
    const result = sortByBoostVisibility(items, new Set(["ghost", "a"]), RADIUS);
    assert.equal(result.length, 2);
    assert.deepEqual(result.map((i) => i.uid).sort(), ["a", "b"]);
  });

  it("the density cap preserves the candidate set exactly", () => {
    const items = [];
    for (let i = 0; i < 10; i += 1) {
      items.push(candidate(`u${i}`, 70, 5));
    }
    const boostedUids = ["u0", "u1", "u2", "u3"];
    const result = capBoostedDensity(items, new Set(boostedUids));
    assert.equal(result.length, items.length);
    assert.deepEqual(
      result.map((i) => i.uid).sort(),
      items.map((i) => i.uid).sort(),
    );
  });

  it("Boost is applied only after Discover has filtered candidates", () => {
    const backend = src("backend.ts");
    const boostAt = backend.indexOf("isBoostedCandidate(doc.id, boosted)");
    assert.ok(boostAt > -1, "boost must be resolved in the candidate loop");
    const before = backend.slice(0, boostAt);
    // Every eligibility gate must already have run by the time Boost appears.
    for (const gate of [
      "passesGenderPreferences",
      "bumpReject(\"gender_preference\")",
      "resolveProfileAge",
      "bumpReject(\"age_unresolved\")",
      "profileReject",
    ]) {
      assert.ok(
        before.includes(gate),
        `${gate} must run before Boost is applied`,
      );
    }
  });

  it("blocked, liked, passed and matched users are excluded before ranking", () => {
    const backend = src("backend.ts");
    for (const exclusion of ["blocked", "likesSnap", "passedSnap", "activeMatches"]) {
      assert.ok(backend.includes(exclusion), `${exclusion} exclusion missing`);
    }
  });

  it("the ranking module never touches compatibility or eligibility fields", () => {
    const ranking = src("boost/ranking.ts");
    for (const forbidden of [
      "compatibilityScore =",
      "compatibilityScore:",
      "isBanned",
      "isSuspended",
      "blocked",
    ]) {
      assert.equal(
        ranking.includes(forbidden),
        false,
        `ranking.ts must not reference ${forbidden}`,
      );
    }
  });
});

describe("6/7. one source of boost strength", () => {
  it("every ranking lever lives in BOOST_STRENGTH", () => {
    for (const key of [
      "priorityBonus",
      "radiusExtensionRatio",
      "minCompatibility",
      "densityWindow",
      "maxPerWindow",
    ]) {
      assert.ok(key in BOOST_STRENGTH, `${key} missing from BOOST_STRENGTH`);
    }
  });

  it("no second boost bonus constant survives", () => {
    const config = fs.readFileSync(
      path.join(__dirname, "..", "src", "boost", "config.ts"),
      "utf8",
    );
    assert.equal(config.includes("BOOST_RANK_BONUS"), false);
    const ranking = fs.readFileSync(
      path.join(__dirname, "..", "src", "boost", "ranking.ts"),
      "utf8",
    );
    assert.equal(ranking.includes("BOOST_PRIORITY_BONUS ="), false);
    assert.equal(ranking.includes("diversifyBoostedResults"), false);
  });
});
