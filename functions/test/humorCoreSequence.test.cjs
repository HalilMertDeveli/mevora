/**
 * The Humor Core sequence itself: one explicit order, well-formed, curated
 * only, and frozen against fixtures/humorCoreSequence.lock.json.
 *
 * Members are only comparable if V7 is the same clip, measuring the same
 * thing, for everyone who ever rated it. These tests fail when an existing
 * position changes and pass when entries are appended (after
 * `node tool/lockHumorCoreSequence.cjs`, which only ever appends).
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {CURATED_GIPHY_CATALOG} = require("../lib/humor/calibrationSeed.js");
const {CALIBRATION_TOTAL, ANCHOR_SLOTS} = require("../lib/humor/calibration.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");
const {
  HUMOR_CORE,
  HUMOR_CORE_RELEASE,
  HUMOR_CORE_SEQUENCE,
  humorCorePosition,
  humorCoreSequenceProblems,
} = require("../lib/humor/coreSequence.js");
const {readLock, structureOf} = require("./helpers/humorCoreLock.cjs");

const HOW_TO_CHANGE =
  "A Humor Core entry that is already locked must not change. For a different clip or a " +
  "different meaning, append a new entry with `supersedes` and retire the old one with active: false.";

const catalog = new Map(CURATED_GIPHY_CATALOG.map((item) => [item.contentId, item]));
const ids = HUMOR_CORE_SEQUENCE.map((entry) => entry.id);

/** A catalogue item for sequence-validation cases. */
function item(contentId, overrides = {}) {
  return {
    contentId,
    category: "sarcasm",
    humorVector: {sarcasm: 0.8},
    sourceTrust: "curated",
    calibrationEligible: true,
    ...overrides,
  };
}

describe("Humor Core configuration", () => {
  it("is fifteen first, then five a day", () => {
    assert.deepEqual(HUMOR_CORE, {onboardingCount: 15, dailyCount: 5});
  });

  it("keeps the calibration milestone equal to the initial count", () => {
    assert.equal(CALIBRATION_TOTAL, HUMOR_CORE.onboardingCount);
  });

  it("has enough entries for the initial calibration and at least one daily set", () => {
    const live = HUMOR_CORE_SEQUENCE.filter((entry) => entry.active).length;
    assert.ok(live >= HUMOR_CORE.onboardingCount + HUMOR_CORE.dailyCount, `only ${live} live entries`);
  });
});

describe("Humor Core sequence", () => {
  it("is well-formed", () => {
    assert.deepEqual(humorCoreSequenceProblems(), []);
  });

  it("is an explicit order with stable positions", () => {
    assert.equal(humorCorePosition(ids[0]), 1);
    assert.equal(humorCorePosition(ids[15]), 16);
    assert.equal(humorCorePosition("hc_gif_not_in_the_sequence"), null);
    assert.equal(new Set(ids).size, ids.length, "an entry appears twice");
  });

  it("holds curated catalogue items only — never a provider-synced document", () => {
    for (const id of ids) {
      const entry = catalog.get(id);
      assert.ok(entry, `${id} is not in the curated catalogue`);
      assert.equal(entry.sourceTrust, "curated", id);
      assert.equal(entry.calibrationEligible, true, id);
      assert.ok(!id.startsWith("ext_"), `${id} looks like a provider-synced id`);
    }
  });

  it("opens with one clip per baseline slot, so the first six ratings cover the same ground for everyone", () => {
    const slots = ids.slice(0, ANCHOR_SLOTS.length).map((id) => catalog.get(id).slot);
    assert.deepEqual([...slots].sort(), ANCHOR_SLOTS.map((slot) => slot.id).sort());
  });

  it("measures every humor dimension within the initial fifteen", () => {
    const measured = new Set(
      ids.slice(0, HUMOR_CORE.onboardingCount).map((id) => catalog.get(id).category),
    );
    assert.deepEqual([...measured].sort(), [...HUMOR_CATEGORIES].sort());
  });

  it("never selects by Firestore query order: the module reads no database", () => {
    const source = fs.readFileSync(
      path.join(__dirname, "..", "src", "humor", "coreSequence.ts"),
      "utf8",
    );
    assert.ok(
      !/from "firebase-admin|\.collection\(|\.orderBy\(|\.where\(/.test(source),
      "coreSequence.ts must stay a plain ordered list",
    );
  });
});

describe("Humor Core sequence validation", () => {
  const known = [item("a"), item("b"), item("c")];
  const problems = (sequence, items = known) => humorCoreSequenceProblems(sequence, items);

  it("accepts a plain ordered list", () => {
    assert.deepEqual(
      problems([
        {id: "a", active: true},
        {id: "b", active: true},
      ]),
      [],
    );
  });

  it("rejects a duplicate", () => {
    const found = problems([
      {id: "a", active: true},
      {id: "a", active: true},
    ]);
    assert.equal(found.length, 1);
    assert.match(found[0], /duplicate of V1/);
  });

  it("rejects an unknown content id", () => {
    assert.match(problems([{id: "zzz", active: true}])[0], /not in the curated catalogue/);
  });

  it("rejects a malformed id before it can become a document path", () => {
    assert.match(problems([{id: "a/b", active: true}])[0], /malformed id/);
  });

  it("rejects provider content: a synced item is never curated", () => {
    const synced = [item("ext_giphy_1", {sourceTrust: "provider", calibrationEligible: false})];
    assert.match(problems([{id: "ext_giphy_1", active: true}], synced)[0], /not curated/);
    const verified = [item("ext_giphy_2", {sourceTrust: "verified_provider"})];
    assert.match(problems([{id: "ext_giphy_2", active: true}], verified)[0], /not curated/);
  });

  it("rejects curated content that was not approved for calibration", () => {
    const unapproved = [item("a", {calibrationEligible: false})];
    assert.match(problems([{id: "a", active: true}], unapproved)[0], /not curated/);
  });

  it("requires a reason to retire, and none on a live entry", () => {
    assert.match(problems([{id: "a", active: false}])[0], /retired without a reason/);
    assert.match(
      problems([{id: "a", active: true, retiredReason: "clip removed"}])[0],
      /active entry carries a retiredReason/,
    );
    assert.deepEqual(problems([{id: "a", active: false, retiredReason: "clip removed"}]), []);
  });

  it("accepts a versioned successor: the old entry keeps its place, the new one is appended", () => {
    assert.deepEqual(
      problems([
        {id: "a", active: false, retiredReason: "clip removed by provider"},
        {id: "b", active: true},
        {id: "c", active: true, supersedes: "a"},
      ]),
      [],
    );
  });

  it("rejects a successor that is not appended after what it replaces", () => {
    const found = problems([
      {id: "c", active: true, supersedes: "a"},
      {id: "a", active: false, retiredReason: "clip removed"},
    ]);
    assert.match(found[0], /not earlier in the sequence/);
  });

  it("rejects a successor of an entry that is still active — that would be two versions of one measurement", () => {
    const found = problems([
      {id: "a", active: true},
      {id: "c", active: true, supersedes: "a"},
    ]);
    assert.match(found[0], /still active/);
  });
});

describe("Humor Core sequence freeze", () => {
  const lock = readLock();

  it("keeps every locked position where it was", () => {
    assert.deepEqual(
      ids.slice(0, lock.length),
      lock.map((entry) => entry.id),
      `HUMOR_CORE_SEQUENCE was reordered, or an entry was inserted or removed. Append only. ${HOW_TO_CHANGE}`,
    );
  });

  it("has a lock entry for every position", () => {
    assert.deepEqual(
      ids.slice(lock.length),
      [],
      "new Humor Core entries are not locked yet: run `node tool/lockHumorCoreSequence.cjs` and commit the lock",
    );
  });

  it("keeps every locked entry's category and humor vector", () => {
    for (const entry of lock) {
      const current = catalog.get(entry.id);
      assert.ok(
        current,
        `${entry.id} is locked but no longer in the curated catalogue. Retire it instead of deleting it.`,
      );
      assert.deepEqual(structureOf(current), entry, `${entry.id} changed. ${HOW_TO_CHANGE}`);
    }
  });

  it("does not lock the media rendition: a new URL for the same clip is not a new measurement", () => {
    for (const entry of lock) {
      assert.deepEqual(Object.keys(entry).sort(), ["category", "id", "vector"]);
    }
  });

  it("is still a draft: the owner has not released the order", () => {
    // Flip this together with HUMOR_CORE_RELEASE when the owner releases the
    // sequence; from then on the lock tool refuses --redraft.
    assert.equal(HUMOR_CORE_RELEASE.released, false);
  });
});
