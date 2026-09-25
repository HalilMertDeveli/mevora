/**
 * Bootstrap Application Default Credentials from existing `firebase login`
 * for local QA scripts only. Does not print secrets. Does not commit files.
 *
 * Writes ADC under %APPDATA%/firebase/ (outside the repo) and prints the path.
 *
 * Usage:
 *   node tool/qaBootstrapAdcFromFirebaseLogin.cjs
 *   set GOOGLE_APPLICATION_CREDENTIALS=<printed path>
 *   node tool/discoverLikeQaE2e.cjs
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const FIREBASE_TOOLS_CFG = path.join(
  os.homedir(),
  ".config",
  "configstore",
  "firebase-tools.json",
);

/** Public installed-app OAuth client used by firebase-tools (not a private key). */
const CLIENT_ID =
  process.env.FIREBASE_CLIENT_ID ||
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const CLIENT_SECRET =
  process.env.FIREBASE_CLIENT_SECRET || "j9iVZfS8kkCEFUPaAeJV0sAi";

function main() {
  if (!fs.existsSync(FIREBASE_TOOLS_CFG)) {
    console.error(
      JSON.stringify({
        ok: false,
        error: "firebase-tools.json missing — run: firebase login",
      }),
    );
    process.exit(1);
  }
  const cfg = JSON.parse(fs.readFileSync(FIREBASE_TOOLS_CFG, "utf8"));
  const refresh = cfg.tokens && cfg.tokens.refresh_token;
  const email = (cfg.user && cfg.user.email) || "unknown";
  if (!refresh) {
    console.error(
      JSON.stringify({
        ok: false,
        error: "no refresh_token — run: firebase login",
        email,
      }),
    );
    process.exit(1);
  }

  const dir = path.join(process.env.APPDATA || os.tmpdir(), "firebase");
  fs.mkdirSync(dir, {recursive: true});
  const slug = String(email).replace(/[@.]/g, "_");
  const out = path.join(dir, `${slug}_application_default_credentials.json`);
  const payload = {
    client_id: CLIENT_ID,
    client_secret: CLIENT_SECRET,
    refresh_token: refresh,
    type: "authorized_user",
  };
  fs.writeFileSync(out, JSON.stringify(payload, null, 2), {
    encoding: "utf8",
    mode: 0o600,
  });
  console.log(
    JSON.stringify({
      ok: true,
      email,
      adcPath: out,
      hint: "Set GOOGLE_APPLICATION_CREDENTIALS to adcPath for Admin SDK QA scripts",
    }),
  );
}

main();
