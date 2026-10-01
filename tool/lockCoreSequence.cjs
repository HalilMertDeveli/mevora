#!/usr/bin/env node
/**
 * Locks newly appended Core questions into
 * functions/test/fixtures/coreSequence.lock.json.
 *
 * The Core sequence is frozen (see functions/src/relationshipLearning/
 * coreSequence.ts): members are comparable only while a position keeps its
 * question, its options and its comparison rule. This tool therefore only
 * ever APPENDS. It refuses to run when an already locked position changed.
 *
 *   node tool/lockCoreSequence.cjs                    lock the positions added since the last lock
 *   node tool/lockCoreSequence.cjs --reword <id>      accept a wording or typo fix that keeps the
 *                                                     meaning of one locked question
 *
 * Run after `npm --prefix functions run build`.
 */
const fs = require("node:fs");
const path = require("node:path");

const FUNCTIONS_DIR = path.join(__dirname, "..", "functions");
function compiled(relative) {
  const full = path.join(FUNCTIONS_DIR, "lib", relative);
  if (!fs.existsSync(full)) {
    console.error(`${relative} is not built — run: npm --prefix functions run build`);
    process.exit(2);
  }
  return require(full);
}

const catalog = compiled("relationshipLearning/catalog.js");
const {CORE_SEQUENCE} = compiled("relationshipLearning/coreSequence.js");
const {LOCK_PATH, lockEntry, readLock, structureOf, textHash, writeLock} = require(
  path.join(FUNCTIONS_DIR, "test", "helpers", "coreSequenceLock.cjs"),
);

const argv = process.argv.slice(2);
const rewordIndex = argv.indexOf("--reword");
const reword = rewordIndex >= 0 ? argv[rewordIndex + 1] : null;
if (argv.length > (rewordIndex >= 0 ? 2 : 0) || (rewordIndex >= 0 && !reword)) {
  console.error("usage: node tool/lockCoreSequence.cjs [--reword <questionId>]");
  process.exit(2);
}

function refuse(message) {
  console.error(`REFUSING: ${message}`);
  console.error(
    "A locked Core question never changes. For a new meaning or new options, add a new id " +
      "(next version), append it to CORE_SEQUENCE and retire the old one with active: false.",
  );
  process.exit(1);
}

const lock = fs.existsSync(LOCK_PATH) ? readLock() : [];
if (reword && !lock.some((entry) => entry.id === reword)) refuse(`${reword} is not a locked question`);

const next = lock.map((entry, index) => {
  if (CORE_SEQUENCE[index] !== entry.id) {
    refuse(`position ${index + 1} is locked as ${entry.id} but CORE_SEQUENCE has ${CORE_SEQUENCE[index] ?? "nothing"}`);
  }
  const question = catalog.learningQuestion(entry.id);
  if (!question) refuse(`${entry.id} is locked but no longer in the catalog`);
  const {textHash: lockedText, ...locked} = entry;
  if (JSON.stringify(structureOf(question)) !== JSON.stringify(locked)) {
    refuse(`${entry.id} changed its version, options or comparison rule`);
  }
  if (textHash(question) === lockedText) return entry;
  if (entry.id !== reword) refuse(`${entry.id} was reworded (pass --reword ${entry.id} if the meaning is unchanged)`);
  console.log(`reworded: ${entry.id}`);
  return lockEntry(question);
});

for (const id of CORE_SEQUENCE.slice(lock.length)) {
  const question = catalog.learningQuestion(id);
  if (!question) refuse(`${id} is in CORE_SEQUENCE but not in the catalog`);
  next.push(lockEntry(question));
  console.log(`locked Q${next.length}: ${id}`);
}

fs.mkdirSync(path.dirname(LOCK_PATH), {recursive: true});
writeLock(next);
console.log(`${next.length} positions locked (${next.length - lock.length} new) -> ${path.relative(process.cwd(), LOCK_PATH)}`);
