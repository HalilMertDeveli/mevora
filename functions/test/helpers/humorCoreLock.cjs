/**
 * The Humor Core sequence lock: what is recorded about each position so that a
 * change to an existing measurement fails CI. Shared by the freeze test and by
 * tool/lockHumorCoreSequence.cjs, so both describe an entry the same way.
 */
const fs = require("node:fs");
const path = require("node:path");

const LOCK_PATH = path.join(__dirname, "..", "fixtures", "humorCoreSequence.lock.json");

/**
 * Everything that decides what a rating of this entry means: which clip it is
 * (the id), what it is about (category) and how a rating moves the profile
 * (the vector). The media URLs are deliberately absent — a new rendition of
 * the same clip is not a new measurement.
 */
function structureOf(item) {
  return {
    id: item.contentId,
    category: item.category,
    vector: Object.entries(item.humorVector)
      .map(([dimension, weight]) => [dimension, weight])
      .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)),
  };
}

function readLock() {
  return JSON.parse(fs.readFileSync(LOCK_PATH, "utf8"));
}

/** One position per line, so a diff of the lock reads as a list of entries. */
function writeLock(entries) {
  const body = entries.map((entry) => `  ${JSON.stringify(entry)}`).join(",\n");
  fs.writeFileSync(LOCK_PATH, `[\n${body}\n]\n`);
}

module.exports = {LOCK_PATH, readLock, structureOf, writeLock};
