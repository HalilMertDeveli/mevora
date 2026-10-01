const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {discoverTestFiles, selectTestFiles} = require("./run.cjs");

/**
 * `npm test` runs test/run.cjs, which finds the suites itself: Node 20 — the
 * Cloud Functions runtime, and what CI pins — does not glob positional
 * `--test` arguments, and npm scripts run through cmd.exe on Windows where
 * the shell will not expand them either.
 *
 * The script used to list every file by name. That list silently rotted
 * (four suites once sat in this directory without ever running) and every
 * branch adding a suite conflicted on it. This test keeps the runner honest
 * and the list from coming back.
 */
describe("backend test suite coverage", () => {
  const testDir = __dirname;
  const packageJson = JSON.parse(
    fs.readFileSync(path.join(testDir, "..", "package.json"), "utf8"),
  );
  const script = packageJson.scripts.test;

  const onDisk = fs
    .readdirSync(testDir)
    .filter((name) => name.endsWith(".test.cjs"))
    .sort();

  it("finds at least the suites that exist today", () => {
    assert.ok(onDisk.length >= 22, `only found ${onDisk.length} suites`);
  });

  it("runs the suites through the runner", () => {
    assert.match(script, /node test\/run\.cjs\b/);
  });

  it("does not name individual test files in the npm test script", () => {
    const named = [...script.matchAll(/test\/([A-Za-z0-9_-]+\.test\.cjs)/g)].map((match) => match[1]);
    assert.deepEqual(named, [], "list no suite in package.json: the runner discovers them");
  });

  it("runs every test file present in functions/test", () => {
    const discovered = discoverTestFiles().map((file) => path.basename(file));
    assert.deepEqual(discovered, onDisk);
  });

  it("hands node paths relative to functions/", () => {
    for (const file of discoverTestFiles()) {
      assert.ok(fs.existsSync(path.join(testDir, "..", file)), `${file} does not resolve`);
    }
  });

  it("narrows to the named suites when filters are given", () => {
    const files = discoverTestFiles();
    assert.deepEqual(selectTestFiles(files, []), files);
    assert.deepEqual(selectTestFiles(files, ["testSuiteCoverage"]), ["test/testSuiteCoverage.test.cjs"]);
    assert.deepEqual(selectTestFiles(files, ["no-such-suite"]), []);
  });
});
