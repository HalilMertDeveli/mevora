/**
 * The Core sequence lock: what is recorded about each position so that a
 * change to an existing question fails CI. Shared by the freeze test and by
 * tool/lockCoreSequence.cjs, so both describe a question the same way.
 */
const {createHash} = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const LOCK_PATH = path.join(__dirname, "..", "fixtures", "coreSequence.lock.json");

/** Wording only. A changed hash with an unchanged structure is a rewording. */
function textHash(question) {
  const texts = [question.prompt, ...question.options.map((option) => option.label)]
    .flatMap((text) => [text.tr, text.en]);
  return createHash("sha1").update(JSON.stringify(texts)).digest("hex").slice(0, 12);
}

/** Everything that decides what an answer means and how two answers compare. */
function structureOf(question) {
  return {
    id: question.id,
    version: question.version,
    comparison: question.comparison,
    dimension: question.dimension,
    options: question.options.map((option) => [option.id, option.value]),
    ...(question.matrix ? {matrix: question.matrix} : {}),
  };
}

function lockEntry(question) {
  return {...structureOf(question), textHash: textHash(question)};
}

function readLock() {
  return JSON.parse(fs.readFileSync(LOCK_PATH, "utf8"));
}

/** One position per line, so a diff of the lock reads as a list of questions. */
function writeLock(entries) {
  const body = entries.map((entry) => `  ${JSON.stringify(entry)}`).join(",\n");
  fs.writeFileSync(LOCK_PATH, `[\n${body}\n]\n`);
}

module.exports = {LOCK_PATH, lockEntry, readLock, structureOf, textHash, writeLock};
