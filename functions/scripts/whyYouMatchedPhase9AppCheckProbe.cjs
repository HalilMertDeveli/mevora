/**
 * Phase 9 — App Check valid / invalid / missing probe against getWhyYouMatched.
 * Uses authenticated QA user so UNAUTHENTICATED is not confused with App Check denial.
 */
const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const PROJECT = process.env.WYM_E2E_PROJECT || "mevora-d6ed0";
const REGION = "europe-west1";
const BOOTSTRAP = path.join(__dirname, "..", "..", "tool", "qaBootstrapAdcFromFirebaseLogin.cjs");
const TOKEN_FILE = path.join(__dirname, "..", "..", "tool", "app_check_debug_token.local");
const OUT_FILE = path.join(__dirname, "..", "..", "tool", "whyYouMatchedPhase9AppCheckEvidence.json");

const PROJECT_CONFIG = {
  "mevora-d6ed0": {
    androidAppId: "1:821220262229:android:1a12a39a06a7516f702fdc",
    apiKey: "AIzaSyCZsTpmLcAwQwdZ3cZ7mnP-sG4N3MKbYPw",
  },
};

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok || !parsed.adcPath) {
    throw new Error(`ADC bootstrap failed: ${line || boot.stderr}`);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
}

async function exchangeAppCheckToken(debugToken) {
  const cfg = PROJECT_CONFIG[PROJECT];
  const url =
    "https://firebaseappcheck.googleapis.com/v1/projects/" +
    PROJECT +
    "/apps/" +
    cfg.androidAppId +
    ":exchangeDebugToken?key=" +
    cfg.apiKey;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({debugToken}),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.token) {
    throw new Error("appcheck-exchange-failed " + JSON.stringify(body));
  }
  return body.token;
}

async function ensureQaUserAndSignIn() {
  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const email = "test_wym_a@mevora-qa.test";
  const password = "TestWym_A_2026!";
  const auth = admin.auth();
  try {
    const user = await auth.getUserByEmail(email);
    await auth.updateUser(user.uid, {
      password,
      emailVerified: true,
    });
  } catch {
    await auth.createUser({
      email,
      password,
      emailVerified: true,
      displayName: "TEST_WYM_USER_A",
    });
  }

  const cfg = PROJECT_CONFIG[PROJECT];
  const url =
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" +
    cfg.apiKey;
  const resp = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({
      email,
      password,
      returnSecureToken: true,
    }),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.idToken) {
    throw new Error("signIn-failed " + JSON.stringify(body));
  }
  return body.idToken;
}

async function call(idToken, appCheckMode) {
  const headers = {"Content-Type": "application/json"};
  if (idToken) headers.Authorization = "Bearer " + idToken;
  if (appCheckMode === "valid") {
    // filled by caller
  } else if (appCheckMode === "invalid") {
    headers["X-Firebase-AppCheck"] = "invalid-token-phase9-probe";
  } else if (appCheckMode === "missing") {
    // omit header
  }
  const resp = await fetch(
    "https://" + REGION + "-" + PROJECT + ".cloudfunctions.net/getWhyYouMatched",
    {
      method: "POST",
      headers,
      body: JSON.stringify({data: {matchId: "phase9-appcheck-probe-no-match"}}),
    },
  );
  const body = await resp.json().catch(() => ({}));
  const err = body.error || {};
  return {
    httpStatus: resp.status,
    status: err.status || null,
    code: err.code || null,
    message: (err.message || "").slice(0, 300),
    hasResult: Boolean(body.result || (body.available !== undefined)),
  };
}

function classify(res, expectDeny) {
  // Firebase callable App Check failures typically surface as UNAUTHENTICATED
  // with message mentioning App Check, or FAILED_PRECONDITION / PERMISSION_DENIED.
  const msg = (res.message || "").toLowerCase();
  const mentionsAppCheck =
    msg.includes("app check") ||
    msg.includes("appcheck") ||
    msg.includes("firebase-app-check");
  if (!expectDeny) {
    // Valid pair should not fail solely due to App Check; no_match / available:false is OK.
    if (res.httpStatus === 200 || res.hasResult) return "PASS";
    if (res.status === "NOT_FOUND" || (res.message || "").includes("no_match")) return "PASS";
    // Callable may return 200 with result {available:false} — already covered.
    // If we get a business error after App Check passed, still PASS for App Check gate.
    if (res.status && res.status !== "UNAUTHENTICATED") return "PASS";
    return "FAIL";
  }
  // Expect deny
  if (res.httpStatus === 200 && res.hasResult) return "FAIL";
  if (mentionsAppCheck) return "PASS";
  if (res.status === "UNAUTHENTICATED" || res.status === "FAILED_PRECONDITION") {
    return "INCONCLUSIVE";
  }
  if (res.httpStatus >= 400) return "INCONCLUSIVE";
  return "FAIL";
}

(async () => {
  ensureAdc();
  if (!fs.existsSync(TOKEN_FILE)) {
    throw new Error("missing App Check debug token file: " + TOKEN_FILE);
  }
  const debugToken = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  const validAc = await exchangeAppCheckToken(debugToken);
  const idToken = await ensureQaUserAndSignIn();

  async function callWithValidAc(id) {
    const headers = {
      "Content-Type": "application/json",
      Authorization: "Bearer " + id,
      "X-Firebase-AppCheck": validAc,
    };
    const resp = await fetch(
      "https://" + REGION + "-" + PROJECT + ".cloudfunctions.net/getWhyYouMatched",
      {
        method: "POST",
        headers,
        body: JSON.stringify({data: {matchId: "phase9-appcheck-probe-no-match"}}),
      },
    );
    const body = await resp.json().catch(() => ({}));
    const err = body.error || {};
    return {
      httpStatus: resp.status,
      status: err.status || null,
      code: err.code || null,
      message: (err.message || "").slice(0, 300),
      hasResult: Boolean(body.result) || body.result === null || typeof body.result === "object",
      rawKeys: Object.keys(body),
    };
  }

  const validPair = await callWithValidAc(idToken);
  // For valid App Check, success means request reached the function (not blocked at App Check).
  // no_match / available:false is expected for nonexistent matchId.
  const validOk =
    validPair.httpStatus === 200 ||
    (validPair.hasResult && validPair.status == null) ||
    (validPair.status && validPair.status !== "UNAUTHENTICATED");

  const missing = await call(idToken, "missing");
  const invalid = await call(idToken, "invalid");

  const evidence = {
    phase: "wym-phase9-appcheck",
    project: PROJECT,
    startedAt: new Date().toISOString(),
    enforceAppCheckNote:
      "getWhyYouMatched uses enforceAppCheck=true when not FUNCTIONS_EMULATOR",
    cases: {
      valid_auth_valid_appcheck: {
        ...validPair,
        verdict: validOk ? "PASS" : "FAIL",
        note: "Auth+AppCheck accepted; business response may be no_match",
      },
      valid_auth_missing_appcheck: {
        ...missing,
        verdict: classify(missing, true),
        note: "Expect deny; UNAUTHENTICATED without App Check mention = INCONCLUSIVE",
      },
      valid_auth_invalid_appcheck: {
        ...invalid,
        verdict: classify(invalid, true),
        note: "Expect deny; UNAUTHENTICATED without App Check mention = INCONCLUSIVE",
      },
    },
  };

  const verdicts = Object.values(evidence.cases).map((c) => c.verdict);
  evidence.final = verdicts.includes("FAIL")
    ? "FAIL"
    : verdicts.includes("INCONCLUSIVE")
      ? "INCONCLUSIVE"
      : "PASS";

  fs.writeFileSync(OUT_FILE, JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify(evidence, null, 2));
  console.log(JSON.stringify({final: evidence.final, evidenceFile: OUT_FILE}));
})().catch((e) => {
  console.error(String(e && e.stack ? e.stack : e));
  process.exit(1);
});
