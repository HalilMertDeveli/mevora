/**
 * Runs the humor emulator flows (calibration, feed pagination, daily set) against a
 * throwaway Firestore emulator:
 *
 *   npm --prefix functions run test:emulator:humor
 *
 * No port is assumed. By default this writes a temporary config (in the OS
 * temp dir) from firebase.qa.json's Firestore block, with free ports picked at
 * run time, so it runs in CI and next to a local emulator suite that already
 * holds the default ports. Overrides:
 *
 *   HUMOR_EMULATOR_CONFIG   a firebase config to use as-is (path from the repo root)
 *   HUMOR_EMULATOR_PORTS    fixed ports for the generated config:
 *                           "firestore,websocket,hub,logging"
 *   HUMOR_EMULATOR_PROJECT  project id (default demo-humor-qa; keep a demo- id
 *                           so nothing can reach a real project)
 *   FIREBASE_CLI            CLI command (default "npx --yes firebase-tools@15",
 *                           the version CI pins)
 *
 * Each flow expects an empty database, so the emulator this script starts is
 * reset between flows. When FIRESTORE_EMULATOR_HOST is already set (you are
 * inside your own `emulators:exec`), the flows run directly against that
 * emulator and it is never reset — run one flow per fresh emulator there.
 */
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");

const FLOWS = ["humorCalibrationFlow.cjs", "humorFeedPaginationFlow.cjs", "humorDailyFlow.cjs"];
const repoRoot = path.resolve(__dirname, "..", "..", "..");

/** Only ever called on an emulator this script started itself. */
async function resetOwnedEmulator() {
  const project = process.env.GCLOUD_PROJECT;
  const url =
    `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/` +
    `${project}/databases/(default)/documents`;
  const response = await fetch(url, {method: "DELETE"});
  if (!response.ok) {
    throw new Error(`could not reset the emulator: HTTP ${response.status}`);
  }
}

async function runFlows() {
  const owned = process.env.HUMOR_EMULATOR_OWNED === "1";
  if (!owned) {
    console.warn("Using an emulator this script did not start: it is not reset between flows.");
  }
  let failed = 0;
  for (const flow of FLOWS) {
    if (owned) {
      await resetOwnedEmulator();
    }
    console.log(`\n=== ${flow} ===`);
    const result = spawnSync(process.execPath, [path.join(__dirname, flow)], {
      stdio: "inherit",
      env: process.env,
    });
    if (result.status !== 0) {
      failed += 1;
    }
  }
  console.log(`\n${FLOWS.length - failed}/${FLOWS.length} humor emulator flows passed`);
  return failed === 0 ? 0 : 1;
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const {port} = server.address();
      server.close(() => resolve(port));
    });
  });
}

async function writeGeneratedConfig() {
  const qa = JSON.parse(fs.readFileSync(path.join(repoRoot, "firebase.qa.json"), "utf8"));
  const fixed = (process.env.HUMOR_EMULATOR_PORTS ?? "")
    .split(",")
    .map((value) => Number(value.trim()))
    .filter((value) => Number.isInteger(value) && value > 0);
  const [firestore, websocket, hub, logging] =
    fixed.length === 4
      ? fixed
      : [await freePort(), await freePort(), await freePort(), await freePort()];
  const config = {
    firestore: {
      database: qa.firestore.database,
      location: qa.firestore.location,
      rules: path.join(repoRoot, qa.firestore.rules),
      indexes: path.join(repoRoot, qa.firestore.indexes),
    },
    emulators: {
      firestore: {port: firestore, host: "127.0.0.1", websocketPort: websocket},
      hub: {port: hub, host: "127.0.0.1"},
      logging: {port: logging, host: "127.0.0.1"},
      ui: {enabled: false},
      singleProjectMode: true,
    },
  };
  const file = path.join(os.tmpdir(), `mevora-humor-emulator-${process.pid}.json`);
  fs.writeFileSync(file, JSON.stringify(config, null, 2));
  return file;
}

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    return runFlows();
  }
  const explicit = process.env.HUMOR_EMULATOR_CONFIG;
  const config = explicit ? path.resolve(repoRoot, explicit) : await writeGeneratedConfig();
  const project = process.env.HUMOR_EMULATOR_PROJECT || "demo-humor-qa";
  const cli = process.env.FIREBASE_CLI || "npx --yes firebase-tools@15";
  const inner = "node functions/test/emulator/runHumorEmulatorFlows.cjs";
  try {
    const result = spawnSync(
      `${cli} emulators:exec --config "${config}" --project ${project} --only firestore "${inner}"`,
      {
        cwd: repoRoot,
        stdio: "inherit",
        shell: true,
        env: {...process.env, HUMOR_EMULATOR_OWNED: "1"},
      },
    );
    return result.status ?? 1;
  } finally {
    if (!explicit) {
      fs.rmSync(config, {force: true});
    }
  }
}

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
