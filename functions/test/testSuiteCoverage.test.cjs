const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

/**
 * `npm test` lists its test files explicitly: Node 20 — the Cloud Functions
 * runtime, and what CI pins — does not glob positional `--test` arguments,
 * and npm scripts run through cmd.exe on Windows where the shell will not
 * expand them either.
 *
 * An explicit list silently rots: four suites (incomingLikesGate, logHygiene,
 * musicCompatibility, questionPriorityRanking) sat in this directory without
 * ever running. This test fails the moment that happens again.
 */
describe("backend test suite coverage", () => {
  const testDir = __dirname;
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(testDir, "..", "package.json"), "utf8"),
  );

  const onDisk = fs
    .readdirSync(testDir)
    .filter((name) => name.endsWith(".test.cjs"))
    .sort();

  const script = packageJson.scripts.test;
  const listed = [...script.matchAll(/test\/([A-Za-z0-9_-]+\.test\.cjs)/g)]
    .map((match) => match[1])
    .sort();

  it("finds at least the suites that exist today", () => {
    assert.ok(onDisk.length >= 22, `only found ${onDisk.length} suites`);
  });

  it("runs every test file present in functions/test", () => {
    const missing = onDisk.filter((name) => !listed.includes(name));
    assert.deepEqual(
      missing,
      [],
      `these suites exist but are not in the npm test script: ${missing.join(", ")}`,
    );
  });

  it("does not list a test file that no longer exists", () => {
    const stale = listed.filter((name) => !onDisk.includes(name));
    assert.deepEqual(
      stale,
      [],
      `these suites are listed but missing from disk: ${stale.join(", ")}`,
    );
  });
});
