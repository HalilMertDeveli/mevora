#!/usr/bin/env node
/**
 * Locks newly appended Humor Core entries into
 * functions/test/fixtures/humorCoreSequence.lock.json.
 *
 * The Humor Core sequence is frozen (see functions/src/humor/coreSequence.ts):
 * members are comparable only while a position keeps its clip, its category
 * and its humor vector. This tool therefore only ever APPENDS. It refuses to
 * run when an already locked position changed.
 *
 *   node tool/lockHumorCoreSequence.cjs             lock the positions added since the last lock
 *   node tool/lockHumorCoreSequence.cjs --redraft   rewrite the whole lock from the current
 *                                                   sequence — only while the sequence is a draft
 *                                                   (HUMOR_CORE_RELEASE.released === false)
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

// GIPHY GIFs and KLIPY clips: every curated entry the sequence may name.
const {CURATED_CATALOG} = compiled("humor/calibrationSeed.js");
const {HUMOR_CORE_RELEASE, HUMOR_CORE_SEQUENCE, humorCoreSequenceProblems} = compiled(
  "humor/coreSequence.js",
);
const {LOCK_PATH, readLock, structureOf, writeLock} = require(
  path.join(FUNCTIONS_DIR, "test", "helpers", "humorCoreLock.cjs"),
);

const argv = process.argv.slice(2);
const redraft = argv.includes("--redraft");
if (argv.length > (redraft ? 1 : 0)) {
  console.error("usage: node tool/lockHumorCoreSequence.cjs [--redraft]");
  process.exit(2);
}

function refuse(message) {
  console.error(`REFUSING: ${message}`);
  console.error(
    "A locked Humor Core entry never changes. For a different clip or a different meaning, " +
      "append a new entry with `supersedes` and retire the old one with active: false.",
  );
  process.exit(1);
}

const problems = humorCoreSequenceProblems();
if (problems.length > 0) {
  refuse(`the sequence is malformed:\n  ${problems.join("\n  ")}`);
}

const catalog = new Map(CURATED_CATALOG.map((item) => [item.contentId, item]));
function entryFor(id) {
  const item = catalog.get(id);
  if (!item) refuse(`${id} is in HUMOR_CORE_SEQUENCE but not in the curated catalogue`);
  return structureOf(item);
}

if (redraft) {
  if (HUMOR_CORE_RELEASE.released) {
    refuse("the sequence is released; --redraft is only for a draft sequence");
  }
  const next = HUMOR_CORE_SEQUENCE.map((entry) => entryFor(entry.id));
  fs.mkdirSync(path.dirname(LOCK_PATH), {recursive: true});
  writeLock(next);
  console.log(`redrafted: ${next.length} positions -> ${path.relative(process.cwd(), LOCK_PATH)}`);
  process.exit(0);
}

const lock = fs.existsSync(LOCK_PATH) ? readLock() : [];
const next = lock.map((entry, index) => {
  const current = HUMOR_CORE_SEQUENCE[index];
  if (!current || current.id !== entry.id) {
    refuse(`V${index + 1} is locked as ${entry.id} but the sequence has ${current?.id ?? "nothing"}`);
  }
  if (JSON.stringify(entryFor(entry.id)) !== JSON.stringify(entry)) {
    refuse(`${entry.id} changed its category or humor vector`);
  }
  return entry;
});

for (const entry of HUMOR_CORE_SEQUENCE.slice(lock.length)) {
  next.push(entryFor(entry.id));
  console.log(`locked V${next.length}: ${entry.id}`);
}

fs.mkdirSync(path.dirname(LOCK_PATH), {recursive: true});
writeLock(next);
console.log(
  `${next.length} positions locked (${next.length - lock.length} new) -> ` +
    path.relative(process.cwd(), LOCK_PATH),
);
