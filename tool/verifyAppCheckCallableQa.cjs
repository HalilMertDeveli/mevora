/**
 * Phase 7A.1 — verify App Check debug token exchange + authenticated callable.
 * Does not print secret values beyond pass/fail. No Spotify OAuth.
 *
 * Usage (from repo root, ADC optional for this script):
 *   node tool/verifyAppCheckCallableQa.cjs
 */
const fs = require("fs");
const path = require("path");
const https = require("https");

const PROJECT = "mevora-d6ed0";
const APP_ID = "1:821220262229:android:1a12a39a06a7516f702fdc";
const REGION = "europe-west1";
const DEBUG_TOKEN = fs
  .readFileSync(path.join(__dirname, "app_check_debug_token.local"), "utf8")
  .trim();
const QA_EMAIL = "sen@gmail.com";
const QA_PASSWORD =
  process.env.QA_E2E_PASSWORD || "MevoraQaE2e!2026";

function loadApiKey() {
  const cfg = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "..", "android", "app", "src", "development", "google-services.json"),
      "utf8",
    ),
  );
  const key = cfg.client?.[0]?.api_key?.[0]?.current_key;
  if (!key) throw new Error("api key missing from google-services.json");
  return key;
}

function postJson(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const payload = JSON.stringify(body);
    const req = https.request(
      {
        hostname: u.hostname,
        path: u.pathname + u.search,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
          ...headers,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk;
        });
        res.on("end", () => {
          let parsed = null;
          try {
            parsed = JSON.parse(data);
          } catch {
            parsed = {raw: data};
          }
          resolve({status: res.statusCode, body: parsed});
        });
      },
    );
    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}

async function main() {
  const apiKey = loadApiKey();

  const appCheck = await postJson(
    `https://firebaseappcheck.googleapis.com/v1/projects/${PROJECT}/apps/${APP_ID}:exchangeDebugToken?key=${apiKey}`,
    {debugToken: DEBUG_TOKEN},
  );

  const appCheckOk =
    appCheck.status === 200 &&
    typeof appCheck.body?.token === "string" &&
    appCheck.body.token.length > 20;

  const auth = await postJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
    {
      email: QA_EMAIL,
      password: QA_PASSWORD,
      returnSecureToken: true,
    },
  );

  const authOk =
    auth.status === 200 &&
    typeof auth.body?.idToken === "string" &&
    typeof auth.body?.localId === "string";

  let callable = {status: 0, body: null};
  let callableOk = false;
  let callableError = null;

  if (appCheckOk && authOk) {
    callable = await postJson(
      `https://${REGION}-${PROJECT}.cloudfunctions.net/getMusicAccount`,
      {data: {}},
      {
        Authorization: `Bearer ${auth.body.idToken}`,
        "X-Firebase-AppCheck": appCheck.body.token,
      },
    );
    // Callable success typically 200 with result; App Check / auth failures often 401/403.
    callableOk =
      callable.status === 200 &&
      callable.body?.error == null &&
      callable.body?.result != null;
    if (!callableOk) {
      callableError = {
        status: callable.status,
        code: callable.body?.error?.status || callable.body?.error?.message || null,
        // Do not dump full body with potential tokens.
      };
    }
  }

  console.log(
    JSON.stringify(
      {
        ok: appCheckOk && authOk && callableOk,
        project: PROJECT,
        appId: APP_ID,
        appCheckExchange: appCheckOk ? "PASS" : "FAIL",
        appCheckHttpStatus: appCheck.status,
        firebaseAuthSignIn: authOk ? "PASS" : "FAIL",
        authHttpStatus: auth.status,
        authUid: authOk ? auth.body.localId : null,
        getMusicAccountCallable: callableOk ? "PASS" : "FAIL",
        callableHttpStatus: callable.status,
        callableError,
        debugTokenRegisteredHint:
          "Token from tool/app_check_debug_token.local exchanged successfully iff appCheckExchange=PASS",
      },
      null,
      2,
    ),
  );

  process.exit(appCheckOk && authOk && callableOk ? 0 : 2);
}

main().catch((error) => {
  console.error(JSON.stringify({ok: false, error: String(error.message || error)}));
  process.exit(1);
});
