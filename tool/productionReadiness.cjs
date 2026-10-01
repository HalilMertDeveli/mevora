#!/usr/bin/env node
/* eslint-disable no-console */
// Production / Google Play release-readiness check for the Mevora repository.
//
//   node tool/productionReadiness.cjs            static checks, read-only
//   node tool/productionReadiness.cjs --online   also asks Google whether Cloud
//                                                Billing is open (read-only GET)
//   node tool/productionReadiness.cjs --json     machine-readable output
//   node tool/productionReadiness.cjs --strict   exit 1 on BLOCKED as well
//
// It reads files in this checkout and nothing else. It never writes, never
// deploys, never prints a secret value, and never touches a Firebase project
// (the optional --online check is a single read-only billing lookup).
//
// Results:
//   PASS          verified here
//   FAIL          wrong in the repository — fix it before a release
//   BLOCKED       correct in the repository, waiting on the owner (a key, a
//                 console setting, a decision)
//   NOT TESTABLE  cannot be decided from a checkout; the message says how to
//                 verify it by hand
//
// Exit code: 1 when anything FAILs (or is BLOCKED with --strict), else 0.

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..");
const args = new Set(process.argv.slice(2));
const results = [];

const read = (rel) => {
  const file = path.join(ROOT, rel);
  return fs.existsSync(file)
    ? fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n")
    : null;
};
const exists = (rel) => fs.existsSync(path.join(ROOT, rel));
const add = (status, area, name, detail) =>
  results.push({ status, area, name, detail: detail || "" });
const pass = (area, name, detail) => add("PASS", area, name, detail);
const fail = (area, name, detail) => add("FAIL", area, name, detail);
const blocked = (area, name, detail) => add("BLOCKED", area, name, detail);
const untestable = (area, name, detail) =>
  add("NOT TESTABLE", area, name, detail);
const check = (ok, area, name, detail, failDetail) =>
  ok ? pass(area, name, detail) : fail(area, name, failDetail || detail);

function git(...gitArgs) {
  try {
    return execFileSync("git", ["-C", ROOT, ...gitArgs], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch (_) {
    return null;
  }
}

const PRODUCTION_PACKAGE = "com.mevora.app";
const MIN_TARGET_SDK = 36; // Google Play, new apps and updates, since 2026-08-31.

// ---------------------------------------------------------------- Android --

function androidChecks() {
  const area = "android";
  const gradle = read("android/app/build.gradle.kts");
  if (!gradle) {
    fail(area, "build script", "android/app/build.gradle.kts is missing");
    return;
  }

  const applicationId = /applicationId\s*=\s*"([^"]+)"/.exec(gradle)?.[1];
  check(
    applicationId === PRODUCTION_PACKAGE,
    area,
    "application id",
    `applicationId = ${applicationId}`,
  );

  const productionFlavor = /create\("production"\)\s*\{([^}]*)\}/.exec(gradle);
  check(
    !!productionFlavor && !/applicationIdSuffix/.test(productionFlavor[1]),
    area,
    "production flavor",
    "production flavor exists and adds no applicationId suffix",
  );

  const targetSdk = Number(/targetSdk\s*=\s*(\d+)/.exec(gradle)?.[1]);
  if (!targetSdk) {
    untestable(
      area,
      "target SDK",
      "targetSdk is not a literal in build.gradle.kts; check the merged manifest of a release build",
    );
  } else {
    check(
      targetSdk >= MIN_TARGET_SDK,
      area,
      "target SDK",
      `targetSdk = ${targetSdk} (Google Play requires ${MIN_TARGET_SDK}+)`,
    );
  }

  const pubspec = read("pubspec.yaml") || "";
  const version = /^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$/m.exec(pubspec);
  check(
    !!version && Number(version[2]) > 0,
    area,
    "version",
    version
      ? `versionName ${version[1]}, versionCode ${version[2]} — the versionCode must be higher than any build already uploaded to Play`
      : "",
    "pubspec.yaml version is not in the form x.y.z+N",
  );

  check(
    /if \(releaseSigning == null\) \{/.test(gradle) &&
      gradle.includes("bundleProductionRelease") &&
      gradle.includes(
        "Refusing to sign a production release with the debug keystore.",
      ),
    area,
    "debug-signing guard",
    "productionRelease fails when signing material is missing",
  );

  const flavor = (name) =>
    new RegExp(`create\\("${name}"\\)\\s*\\{([^}]*)\\}`).exec(gradle)?.[1] ||
    "";
  const releaseBuildType =
    /buildTypes\s*\{\s*release\s*\{([^}]*)\}/.exec(gradle)?.[1] || "";
  check(
    /signingConfig\s*=\s*productionKeystore/.test(flavor("production")) &&
      /signingConfig\s*=\s*debugKeystore/.test(flavor("development")) &&
      /signingConfig\s*=\s*debugKeystore/.test(flavor("staging")) &&
      !/signingConfigs\.getByName/.test(releaseBuildType),
    area,
    "release key scope",
    "only the production flavor is signed with the release keystore",
  );

  check(
    gradle.includes('val productionEntrypoint = "lib/main_production.dart"') &&
      gradle.includes("flutterTarget.endsWith(productionEntrypoint)") &&
      (read("lib/main_production.dart") || "").includes(
        "bootstrap(AppEnvironment.production)",
      ),
    area,
    "production entrypoint guard",
    "productionRelease fails unless built with -t lib/main_production.dart",
  );

  // Signing material: presence only, values are never read out.
  const keyProperties = read("android/key.properties");
  const fromFile = (key) =>
    !!keyProperties && new RegExp(`^${key}\\s*=\\s*\\S`, "m").test(keyProperties);
  const signingKeys = [
    ["storeFile", "MEVORA_ANDROID_KEYSTORE_PATH"],
    ["storePassword", "MEVORA_ANDROID_KEYSTORE_PASSWORD"],
    ["keyAlias", "MEVORA_ANDROID_KEY_ALIAS"],
    ["keyPassword", "MEVORA_ANDROID_KEY_PASSWORD"],
  ];
  const missing = signingKeys
    .filter(([key, env]) => !fromFile(key) && !process.env[env])
    .map(([key, env]) => `${key}/${env}`);
  if (missing.length === 0) {
    pass(area, "release signing material", "all four values are configured");
  } else {
    blocked(
      area,
      "release signing material",
      `owner upload key not configured (missing: ${missing.join(", ")}) — docs/ANDROID_RELEASE_SIGNING.md`,
    );
  }

  const trackedKeys = git(
    "ls-files",
    "*.jks",
    "*.keystore",
    "*.p12",
    "key.properties",
  );
  if (trackedKeys === null) {
    untestable(area, "no keystore tracked", "git is not available");
  } else {
    check(
      trackedKeys.trim() === "",
      area,
      "no keystore tracked",
      "no keystore or key.properties is committed",
      `tracked signing material: ${trackedKeys.trim().split("\n").join(", ")}`,
    );
  }

  const manifest = read("android/app/src/main/AndroidManifest.xml") || "";
  const forbidden = [
    "android.permission.READ_MEDIA_IMAGES",
    "android.permission.READ_MEDIA_VIDEO",
    "android.permission.READ_MEDIA_VISUAL_USER_SELECTED",
    "android.permission.READ_EXTERNAL_STORAGE",
    "android.permission.WRITE_EXTERNAL_STORAGE",
    "android.permission.MANAGE_EXTERNAL_STORAGE",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.READ_CONTACTS",
    "android.permission.QUERY_ALL_PACKAGES",
  ].filter((permission) => manifest.includes(`"${permission}"`));
  check(
    forbidden.length === 0,
    area,
    "restricted permissions",
    "no broad media, storage, background-location, contacts or package-visibility permission",
    `declared: ${forbidden.join(", ")}`,
  );
  const adPermissions = [
    "com.google.android.gms.permission.AD_ID",
    "android.permission.ACCESS_ADSERVICES_AD_ID",
    "android.permission.ACCESS_ADSERVICES_ATTRIBUTION",
  ].filter(
    (permission) => !manifest.includes(`"${permission}" tools:node="remove"`),
  );
  check(
    adPermissions.length === 0,
    area,
    "advertising ID",
    "advertising-ID permissions are removed (no ads; declare 'no advertising ID' in Play Console)",
    `still merged into the release manifest: ${adPermissions.join(", ")}`,
  );
  check(
    /android:allowBackup="false"/.test(manifest),
    area,
    "backups",
    "allowBackup is false",
  );
  check(
    !/usesCleartextTraffic="true"/.test(manifest),
    area,
    "cleartext traffic",
    "the main manifest does not allow cleartext traffic",
  );

  const services = read("android/app/src/production/google-services.json");
  if (!services) {
    fail(
      area,
      "production google-services.json",
      "android/app/src/production/google-services.json is missing",
    );
    return;
  }
  let json;
  try {
    json = JSON.parse(services);
  } catch (_) {
    fail(area, "production google-services.json", "not valid JSON");
    return;
  }
  const client = (json.client || []).find(
    (entry) =>
      entry?.client_info?.android_client_info?.package_name ===
      PRODUCTION_PACKAGE,
  );
  check(
    !!client,
    area,
    "production Firebase app",
    `${PRODUCTION_PACKAGE} is registered in ${json.project_info?.project_id}`,
    `${PRODUCTION_PACKAGE} is not registered in the production google-services.json`,
  );
  const androidOauth = (client?.oauth_client || []).filter(
    (entry) => entry.client_type === 1 && entry.android_info?.certificate_hash,
  );
  if (androidOauth.length > 0) {
    pass(
      area,
      "signing certificate in Firebase",
      `${androidOauth.length} Android OAuth client(s) with a certificate hash — confirm one is the Play app signing key`,
    );
  } else {
    blocked(
      area,
      "signing certificate in Firebase",
      "the production google-services.json has no Android OAuth client: register the Play app signing SHA-1/SHA-256 (and the upload key) on the Firebase Android app, then re-download the file",
    );
  }
  return json.project_info?.project_id;
}

// --------------------------------------------------------------- Firebase --

function firebaseChecks(nativeProjectId) {
  const area = "firebase";
  const resolver =
    read("lib/core/config/firebase/firebase_options_resolver.dart") || "";
  const productionBlock =
    /_androidProduction\s*=\s*FirebaseOptions\(([\s\S]*?)\);/.exec(
      resolver,
    )?.[1] || "";
  const dartProjectId = /projectId:\s*'([^']+)'/.exec(productionBlock)?.[1];
  const appConfig = read("lib/core/config/app_config.dart") || "";
  const configProjectId =
    /AppEnvironment\.production\s*=>\s*'([a-z0-9-]+)',\s*\n\s*\};\s*\n\s*\n\s*bool get showDebugBanner/.exec(
      appConfig,
    )?.[1];
  let rc = {};
  try {
    rc = JSON.parse(read(".firebaserc") || "{}");
  } catch (_) {
    rc = {};
  }
  const aliasProjectId = rc.projects?.production;

  const ids = {
    "Dart options": dartProjectId,
    "google-services.json": nativeProjectId,
    AppConfig: configProjectId,
    ".firebaserc production": aliasProjectId,
  };
  const distinct = [...new Set(Object.values(ids).filter(Boolean))];
  check(
    distinct.length === 1 && Object.values(ids).every(Boolean),
    area,
    "production project is consistent",
    `every production reference points at ${distinct[0]}`,
    `production references disagree: ${JSON.stringify(ids)}`,
  );
  const productionProject = distinct.length === 1 ? distinct[0] : dartProjectId;

  if (rc.projects?.default && rc.projects.default !== productionProject) {
    blocked(
      area,
      "backend deployed to the production project",
      `the production flavor talks to ${productionProject}; the default deploy target is ${rc.projects.default}. Rules, indexes, functions, secrets and hosting must exist on ${productionProject} (or the owner repoints production) — see docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md, "Which project is production"`,
    );
  }

  check(
    /bool get useEmulators \{\s*if \(!environment\.isDevelopment\) \{\s*return false;/.test(
      appConfig,
    ),
    area,
    "emulator routing",
    "emulators are reachable from the development environment only",
  );

  const bootstrap = read("lib/bootstrap.dart") || "";
  check(
    bootstrap.includes("flavorEnvironmentMismatch(") &&
      bootstrap.indexOf("flavorEnvironmentMismatch(") <
        bootstrap.indexOf("FirebaseBootstrap("),
    area,
    "flavor / environment guard",
    "bootstrap refuses a flavor started from another environment's entrypoint",
  );

  const firebaseBootstrap =
    read("lib/core/services/firebase/firebase_bootstrap.dart") || "";
  check(
    /config\.environment\.isProduction\s*\?\s*const AndroidPlayIntegrityProvider\(\)/.test(
      firebaseBootstrap,
    ) && !/AndroidDebugProvider\(debugToken:\s*'/.test(firebaseBootstrap),
    area,
    "App Check provider",
    "production uses Play Integrity; no debug token is hardcoded",
  );

  // Every USE_MOCK_* define must be gated to development, non-release builds.
  const di = path.join(ROOT, "lib/core/di");
  const ungated = fs.existsSync(di)
    ? fs
        .readdirSync(di)
        .filter((file) => file.endsWith(".dart"))
        .filter((file) => {
          const source = fs.readFileSync(path.join(di, file), "utf8");
          return (
            /fromEnvironment\(\s*'USE_MOCK_[A-Z_]+'/.test(source) &&
            !/mockDataSourceAllowed\(|resolveUseMockHumor\(/.test(source)
          );
        })
    : [];
  check(
    ungated.length === 0,
    area,
    "mock data defines",
    "every USE_MOCK_* define is ignored outside development debug builds",
    `ungated USE_MOCK_* define in: ${ungated.join(", ")}`,
  );

  // Callables must enforce App Check outside the emulator; admin commands are
  // the documented exception (BFF secret + MFA + RBAC instead).
  const hardOff = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith(".ts")) {
        const source = fs.readFileSync(full, "utf8");
        if (/enforceAppCheck:\s*false/.test(source)) {
          hardOff.push(path.relative(ROOT, full).replace(/\\/g, "/"));
        }
      }
    }
  };
  const functionsSrc = path.join(ROOT, "functions/src");
  if (fs.existsSync(functionsSrc)) walk(functionsSrc);
  const unexpected = hardOff.filter(
    (file) => !file.startsWith("functions/src/admin/"),
  );
  check(
    unexpected.length === 0,
    area,
    "App Check enforcement",
    "no member-facing callable switches App Check off",
    `enforceAppCheck: false in ${unexpected.join(", ")}`,
  );

  untestable(
    area,
    "console state",
    `App Check (Play Integrity) registration, enabled sign-in providers, deployed rules/indexes/functions and secrets on ${productionProject} live in the Firebase console — checklist in docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md`,
  );
  return productionProject;
}

// ---------------------------------------------------------------- Billing --

function billingChecks() {
  const area = "billing";
  const catalog =
    read("lib/features/boost/domain/config/boost_pack_catalog.dart") || "";
  const boostIds = ["week", "month", "year"]
    .map(
      (name) =>
        new RegExp(`static const String ${name} = '([^']+)'`).exec(catalog)?.[1],
    )
    .filter(Boolean);
  check(
    boostIds.length === 3 && boostIds.every((id) => /^[a-z0-9_.]+$/.test(id)),
    area,
    "Boost product IDs",
    `one-time products expected in Play Console: ${boostIds.join(", ")}`,
    "Boost product IDs could not be read from boost_pack_catalog.dart",
  );
  blocked(
    area,
    "Boost products in Play Console",
    `create the consumable one-time products ${boostIds.join(", ")} for ${PRODUCTION_PACKAGE} and activate them`,
  );

  const envExample = read("functions/.env.example") || "";
  const required = [
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
    "PREMIUM_ANDROID_PACKAGE_NAME",
    "PREMIUM_ANDROID_PRODUCT_IDS",
  ];
  const undocumented = required.filter((name) => !envExample.includes(name));
  check(
    undocumented.length === 0,
    area,
    "Play configuration is documented",
    "functions/.env.example names every Play billing variable",
    `functions/.env.example does not mention: ${undocumented.join(", ")}`,
  );

  const catalogTs = read("functions/src/subscription/productCatalog.ts") || "";
  const hardcodedPremium =
    /PREMIUM_ANDROID_PRODUCT_IDS\s*\?\?\s*"[^"]+"/.test(catalogTs);
  check(
    !hardcodedPremium,
    area,
    "Premium catalogue has no placeholder",
    "Premium product IDs come from configuration only; nothing is granted until they are set",
  );
  blocked(
    area,
    "Premium products in Play Console",
    "no Premium subscription exists yet: create it with its base plans, then set PREMIUM_ANDROID_PRODUCT_IDS (functions env and --dart-define) and build with --dart-define=PREMIUM_ENABLED=true",
  );
  untestable(
    area,
    "real purchases",
    "purchase, renewal, cancellation, refund and RTDN need a Play-distributed build and a license tester account",
  );
}

// ------------------------------------------------------------ Legal pages --

function legalChecks() {
  const area = "legal pages";
  const pages = {
    privacy: "privacy.html",
    terms: "terms.html",
    guidelines: "guidelines.html",
    help: "help.html",
    "delete-account": "delete-account.html",
    "child-safety": "child-safety.html",
  };
  let firebaseJson = {};
  try {
    firebaseJson = JSON.parse(read("firebase.json") || "{}");
  } catch (_) {
    fail(area, "firebase.json", "not valid JSON");
  }
  const rewrites = firebaseJson.hosting?.rewrites || [];
  const publicDir = firebaseJson.hosting?.public || "hosting/public";

  for (const [route, file] of Object.entries(pages)) {
    const html = read(`${publicDir}/${file}`);
    if (!html) {
      fail(area, `/${route}`, `${publicDir}/${file} is missing`);
      continue;
    }
    const problems = [];
    if (
      !rewrites.some(
        (rewrite) =>
          rewrite.source === `/${route}` && rewrite.destination === `/${file}`,
      )
    ) {
      problems.push("no hosting rewrite");
    }
    if (!/lang="tr"/.test(html) || !/lang="en"/.test(html)) {
      problems.push("needs both a Turkish and an English section");
    }
    if (!/Mevora/.test(html)) problems.push("does not name the app");
    if (/lorem ipsum|TODO|FIXME|example\.com|XXXX/i.test(html)) {
      problems.push("contains placeholder text");
    }
    if (!/mailto:/.test(html)) problems.push("no contact address");
    for (const [, href] of html.matchAll(/href="\/([a-z-]+)(?:#[a-z]+)?"/g)) {
      if (!(href in pages) && href !== "site.css") {
        problems.push(`broken internal link /${href}`);
      }
    }
    check(
      problems.length === 0,
      area,
      `/${route}`,
      `${file}: Turkish + English, linked, routed`,
      `${file}: ${[...new Set(problems)].join("; ")}`,
    );
  }

  const deletion = read(`${publicDir}/delete-account.html`) || "";
  check(
    /Settings/.test(deletion) &&
      /What is deleted/.test(deletion) &&
      /What may be kept/.test(deletion),
    area,
    "account deletion page content",
    "explains the in-app path, what is deleted and what is kept",
  );
  const childSafety = read(`${publicDir}/child-safety.html`) || "";
  check(
    /CSAE/.test(childSafety) &&
      /How to report/.test(childSafety) &&
      /Point of contact/.test(childSafety),
    area,
    "child safety standards content",
    "prohibits CSAE, explains how to report, names a contact point",
  );

  const contacts = new Set();
  for (const file of Object.values(pages)) {
    const html = read(`${publicDir}/${file}`) || "";
    for (const [, address] of html.matchAll(/mailto:([^"?]+)/g)) {
      contacts.add(address);
    }
  }
  if ([...contacts].some((address) => /@(gmail|outlook|hotmail)\./.test(address))) {
    blocked(
      area,
      "contact address",
      `the public pages use a personal mailbox (${[...contacts].join(", ")}): the owner should confirm it or replace it with a dedicated support address everywhere`,
    );
  } else {
    pass(area, "contact address", [...contacts].join(", "));
  }
  blocked(
    area,
    "legal review and publication",
    "the policy texts are engineering drafts: owner/counsel approval, the data controller's legal identity, and a hosting deploy to the production site are required",
  );
}

// ------------------------------------------------------------- Humor Core --

function humorChecks() {
  const area = "humor core";
  const sequence = read("functions/src/humor/coreSequence.ts");
  if (!sequence) {
    untestable(area, "sequence", "functions/src/humor/coreSequence.ts not found");
    return;
  }
  const released = /released:\s*(true|false)/.exec(sequence)?.[1];
  let locked = null;
  try {
    const lock = JSON.parse(
      read("functions/test/fixtures/humorCoreSequence.lock.json") || "null",
    );
    locked = Array.isArray(lock) ? lock.length : lock?.entries?.length ?? null;
  } catch (_) {
    locked = null;
  }
  const size = locked === null ? "unknown" : String(locked);
  if (released === "true") {
    pass(area, "sequence released", `released, ${size} locked entries`);
  } else {
    blocked(
      area,
      "sequence released",
      `the Humor Core sequence is still a draft (released=false, ${size} locked entries): the owner chooses the final clips and order — docs/PUBLISH_BLOCKERS.md item 2`,
    );
  }
  const bootstrap = read("lib/bootstrap.dart") || "";
  if (/HUMOR_LAB_ENABLED/.test(bootstrap)) {
    untestable(
      area,
      "humor shipped in this build",
      "Humor is off in release builds unless built with --dart-define=HUMOR_LAB_ENABLED=true: an owner decision per release",
    );
  }
}

// ---------------------------------------------------------------- Secrets --

function secretChecks() {
  const area = "secrets";
  const tracked = git("ls-files");
  if (tracked === null) {
    untestable(area, "tracked files", "git is not available");
    return;
  }
  const files = tracked.split("\n").filter(Boolean);
  const suspicious = files.filter(
    (file) =>
      /(^|\/)\.env(\.[^/]*)?$/.test(file) && !/\.example$/.test(file)
        ? true
        : /firebase-adminsdk.*\.json$|service-?account.*\.json$|\.pem$|\.p8$|\.p12$/i.test(
            file,
          ),
  );
  check(
    suspicious.length === 0,
    area,
    "credential files",
    "no .env, service-account, .pem, .p8 or .p12 file is committed",
    `tracked credential-looking files: ${suspicious.join(", ")}`,
  );

  const textLike = /\.(dart|ts|js|cjs|mjs|json|yaml|yml|kts|gradle|xml|properties|md|html|ps1|cmd|sh|cs|cshtml|resx)$/;
  const hits = [];
  for (const file of files) {
    if (!textLike.test(file)) continue;
    const full = path.join(ROOT, file);
    let stat;
    try {
      stat = fs.statSync(full);
    } catch (_) {
      continue;
    }
    if (stat.size > 1_500_000) continue;
    const source = fs.readFileSync(full, "utf8");
    if (
      /-----BEGIN (RSA |EC |)PRIVATE KEY-----[A-Za-z0-9+/=\s]{200,}/.test(
        source,
      ) ||
      /"private_key"\s*:\s*"-----BEGIN/.test(source)
    ) {
      hits.push(file);
    }
  }
  check(
    hits.length === 0,
    area,
    "private keys in source",
    "no private key material in tracked files",
    `private key material in: ${hits.join(", ")} — rotate the credential, removing the file is not enough`,
  );
}

// ---------------------------------------------------- Cloud Billing state --

function cloudBilling(projectId) {
  const area = "cloud billing";
  const how =
    `GET https://cloudbilling.googleapis.com/v1/projects/${projectId}/billingInfo ` +
    "must show billingEnabled=true, and the billing account itself must be open — docs/PUBLISH_BLOCKERS.md item 1";
  if (!args.has("--online")) {
    untestable(area, `billing on ${projectId}`, `run with --online, or check by hand: ${how}`);
    return;
  }
  let token;
  try {
    const gcloud = process.platform === "win32" ? "gcloud.cmd" : "gcloud";
    token = execFileSync(gcloud, ["auth", "print-access-token"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      shell: process.platform === "win32",
    }).trim();
  } catch (_) {
    untestable(area, `billing on ${projectId}`, `gcloud is not signed in. ${how}`);
    return;
  }
  const get = (url) =>
    JSON.parse(
      execFileSync(
        process.execPath,
        [
          "-e",
          "fetch(process.argv[1],{headers:{Authorization:'Bearer '+process.env.T}})" +
            ".then(r=>r.text()).then(t=>process.stdout.write(t))",
          url,
        ],
        { encoding: "utf8", env: { ...process.env, T: token } },
      ),
    );
  try {
    const info = get(
      `https://cloudbilling.googleapis.com/v1/projects/${projectId}/billingInfo`,
    );
    if (info.error) {
      untestable(area, `billing on ${projectId}`, `Google answered ${info.error.status || info.error.code}. ${how}`);
      return;
    }
    if (!info.billingEnabled || !info.billingAccountName) {
      blocked(area, `billing on ${projectId}`, "no open billing account is linked: Cloud Functions and phone SMS will not work. Owner action.");
      return;
    }
    const account = get(
      `https://cloudbilling.googleapis.com/v1/${info.billingAccountName}`,
    );
    if (account.open === true) {
      pass(area, `billing on ${projectId}`, "the linked billing account is open");
    } else if (account.open === false) {
      blocked(area, `billing on ${projectId}`, "the project is linked to a billing account that is CLOSED: Cloud Functions and phone SMS will not work. Owner action.");
    } else {
      untestable(area, `billing on ${projectId}`, `the billing account could not be read. ${how}`);
    }
  } catch (_) {
    untestable(area, `billing on ${projectId}`, `the lookup failed. ${how}`);
  }
}

// ------------------------------------------------------------------- main --

const nativeProjectId = androidChecks();
const productionProject = firebaseChecks(nativeProjectId);
billingChecks();
legalChecks();
humorChecks();
secretChecks();
if (productionProject) cloudBilling(productionProject);

const counts = { PASS: 0, FAIL: 0, BLOCKED: 0, "NOT TESTABLE": 0 };
for (const result of results) counts[result.status] += 1;

if (args.has("--json")) {
  console.log(JSON.stringify({ counts, results }, null, 2));
} else {
  let area = "";
  for (const result of results) {
    if (result.area !== area) {
      area = result.area;
      console.log(`\n${area.toUpperCase()}`);
    }
    const tag = `[${result.status}]`.padEnd(15);
    console.log(`  ${tag}${result.name}${result.detail ? ` — ${result.detail}` : ""}`);
  }
  console.log(
    `\n${counts.PASS} PASS · ${counts.FAIL} FAIL · ${counts.BLOCKED} BLOCKED · ${counts["NOT TESTABLE"]} NOT TESTABLE`,
  );
  if (counts.FAIL === 0 && counts.BLOCKED > 0) {
    console.log(
      "The repository side is ready; the BLOCKED items wait on the owner (docs/GOOGLE_PLAY_PRODUCTION_LAUNCH.md).",
    );
  }
}

process.exit(counts.FAIL > 0 || (args.has("--strict") && counts.BLOCKED > 0) ? 1 : 0);
