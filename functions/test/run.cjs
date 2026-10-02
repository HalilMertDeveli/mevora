/**
 * The backend test runner behind `npm test`.
 *
 * Node 20 — the Cloud Functions runtime, and what CI pins — does not glob
 * positional `--test` arguments, and npm scripts run through cmd.exe on
 * Windows where the shell will not expand them either. So the files are
 * found here instead of being listed in package.json, where every branch
 * that added a suite conflicted with every other one.
 *
 *   node test/run.cjs                     every *.test.cjs in this directory
 *   node test/run.cjs mevoraPicks boost   only suites whose name contains a filter
 */
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const TEST_DIR = __dirname;
const TEST_SUFFIX = ".test.cjs";

/** Every suite in functions/test, sorted, as paths relative to functions/. */
function discoverTestFiles(testDir = TEST_DIR) {
  return fs
    .readdirSync(testDir)
    .filter((name) => name.endsWith(TEST_SUFFIX))
    .sort()
    .map((name) => `test/${name}`);
}

/** Keeps the suites whose file name contains any of the filters (all when none is given). */
function selectTestFiles(files, filters) {
  if (filters.length === 0) return files;
  const wanted = filters.map((filter) => filter.toLowerCase());
  return files.filter((file) => wanted.some((filter) => path.basename(file).toLowerCase().includes(filter)));
}

function main(argv) {
  const files = selectTestFiles(discoverTestFiles(), argv);
  if (files.length === 0) {
    console.error(`no test suite matches: ${argv.join(" ")}`);
    return 1;
  }
  const result = spawnSync(process.execPath, ["--test", ...files], {
    cwd: path.join(TEST_DIR, ".."),
    stdio: "inherit",
  });
  if (result.error) throw result.error;
  return result.status ?? 1;
}

if (require.main === module) {
  process.exit(main(process.argv.slice(2)));
}

module.exports = {discoverTestFiles, selectTestFiles};
