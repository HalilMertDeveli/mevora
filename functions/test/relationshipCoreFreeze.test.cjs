const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const catalog = require("../lib/relationshipLearning/catalog.js");
const {CORE} = require("../lib/relationshipLearning/config.js");
const {CORE_SEQUENCE} = require("../lib/relationshipLearning/coreSequence.js");
const {readLock, structureOf, textHash} = require("./helpers/coreSequenceLock.cjs");

/**
 * The Core sequence is frozen: members are only comparable if Q7 is the same
 * question, with the same options, for everyone who ever answered it.
 *
 * fixtures/coreSequence.lock.json records every position. These tests fail
 * when an existing position changes, and pass when questions are appended
 * (after `node tool/lockCoreSequence.cjs`, which only ever appends).
 */
const HOW_TO_CHANGE =
  "A Core question that is already locked must not change. If its meaning or options need to change, " +
  "add a new id (next version), append it to CORE_SEQUENCE and retire the old one with active: false.";

describe("Core sequence freeze", () => {
  const lock = readLock();

  it("keeps every locked position where it was", () => {
    assert.deepEqual(
      CORE_SEQUENCE.slice(0, lock.length),
      lock.map((entry) => entry.id),
      `CORE_SEQUENCE was reordered, or a question was inserted or removed. Append only. ${HOW_TO_CHANGE}`,
    );
  });

  it("has a lock entry for every position", () => {
    assert.deepEqual(
      CORE_SEQUENCE.slice(lock.length),
      [],
      "new Core questions are not locked yet: run `node tool/lockCoreSequence.cjs` and commit the lock",
    );
  });

  it("keeps every locked question's version, options and comparison rule", () => {
    for (const entry of lock) {
      const question = catalog.learningQuestion(entry.id);
      assert.ok(question, `${entry.id} is locked but no longer in the catalog. Retire it instead of deleting it.`);
      const {textHash: _wording, ...locked} = entry;
      assert.deepEqual(structureOf(question), locked, `${entry.id} changed. ${HOW_TO_CHANGE}`);
    }
  });

  it("notices when a locked question is reworded", () => {
    for (const entry of lock) {
      const question = catalog.learningQuestion(entry.id);
      assert.equal(
        textHash(question),
        entry.textHash,
        `${entry.id} was reworded. A typo or wording fix that keeps the meaning: ` +
          `run \`node tool/lockCoreSequence.cjs --reword ${entry.id}\`. ${HOW_TO_CHANGE}`,
      );
    }
  });

  it("places every question of the bank exactly once", () => {
    assert.equal(new Set(CORE_SEQUENCE).size, CORE_SEQUENCE.length, "a question appears twice in CORE_SEQUENCE");
    assert.deepEqual(
      [...CORE_SEQUENCE].sort(),
      catalog.LEARNING_QUESTIONS.map((question) => question.id).sort(),
      "every catalog question, active or retired, has exactly one place in CORE_SEQUENCE",
    );
  });

  it("keeps onboarding comparable: Q1-Q15 hold no importance question", () => {
    for (const id of CORE_SEQUENCE.slice(0, CORE.onboardingCount)) {
      assert.equal(catalog.isImportanceQuestion(catalog.learningQuestion(id)), false, id);
    }
  });
});
