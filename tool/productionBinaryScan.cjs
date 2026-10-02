#!/usr/bin/env node
/* eslint-disable no-console */
// Looks inside a compiled release build for test, QA, demo and emulator code.
//
// The production leak scan in tool/productionReadiness.cjs reads source. This
// reads what the compiler actually produced: a release build must not merely
// keep the demo deck, the QA login and the design gallery switched off, it
// must not contain them.
//
//   node tool/productionBinaryScan.cjs <libapp.so | app.so | app.apk>
//
// Compiling just the Dart code in release mode needs no keystore and builds no
// APK:
//
//   flutter assemble --output=.tmp/aot_release -dTargetPlatform=android-arm64 \
//     -dBuildMode=release -dTargetFile=lib/main_production.dart \
//     -dFlavor=production -dTreeShakeIcons=false \
//     android_aot_bundle_release_android-arm64
//   node tool/productionBinaryScan.cjs .tmp/aot_release/arm64-v8a/app.so
//
// Given an APK it scans lib/arm64-v8a/libapp.so and the asset list as well.
// A debug or profile build is the wrong input: only release mode removes the
// code, and the scan says so when it sees debug-only strings.
//
// It reads one file and writes nothing. Exit code 1 when anything that must be
// absent is present, or when a control string is missing (the scan would then
// prove nothing).

"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const input = process.argv[2];
if (!input || input.startsWith("-") || !fs.existsSync(input)) {
  console.error("usage: node tool/productionBinaryScan.cjs <libapp.so | app.so | app.apk>");
  process.exit(2);
}

// Strings that are in every real build. If one is missing the file is not a
// Mevora snapshot, or strings are stored in a way this scan cannot read.
const CONTROLS = ["Continue with Google", "getDiscoveryCandidates", "europe-west1"];

// Must not be in a release build, with what each one would mean.
const MUST_BE_ABSENT = {
  "demo deck and demo matches": [
    "mock-01",
    "mock-10",
    "mock://",
    "assets/images/portraits",
    "MockDiscoveryRepository",
    "MockDiscoveryProfile",
    "HybridDiscoveryRepository",
    "DemoSocialHub",
    "InMemorySocialGraph",
    "Restart demo",
    "Demoyu yeniden başlat",
  ],
  "mock and in-memory data sources": [
    "MockMusicDataSource",
    "MockHumorDataSource",
    "MockRelationshipDataSource",
    "MockVideoCallProvider",
    "MockIncomingLikesRepository",
    "FakeLocationRepository",
    "InMemoryDiscoveryRepository",
    "FakeChatAudioPlayer",
    "FakeProfilePhotoPicker",
  ],
  "emulator test stores": ["EmulatorPremiumBillingRepository", "EmulatorStorePurchaseDataSource"],
  "QA login": ["QaLoginPage", "EmulatorQaLoginPanel", "QA_TOKEN_SIGNIN_FAILED", "@mevora.test"],
  "developer gallery": ["DesignSystemPage"],
  "emulator addresses": ["10.0.2.2", "127.0.0.1"],
  "debug log tags": ["[RELATIONSHIP_DEBUG]", "[COMPAT_DEBUG]", "[TAB]", "[DISCOVER]", "[HUMOR-MEDIA]"],
  "developer wording in copy": [
    "Firebase billing (Blaze)",
    "for this Firebase project yet",
    "configured in this build yet",
    "try on a physical device",
    "Server-side filtering arrives",
    "This part of Mevora is not ready yet",
  ],
};

// Present by design. Listed so nobody finds them later and wonders.
const EXPECTED = {
  "/qa-login": "route constant; the redirector uses it to send the path away",
  "/debug/design-system": "route constant; the redirector uses it to send the path away",
  USE_EMULATORS: "name of a development-only define, used to refuse a build that was given it",
  QA_PASSWORD: "name of a development-only define, used to refuse a build that was given it",
  "[PHONE_AUTH]": "argument of a debug-only log helper; never printed in a release build",
};

// Only a debug or profile build has these: the wrong thing to scan.
const NOT_RELEASE = ["The Dart VM service is listening on", "kernel_blob.bin"];

function loadTargets(file) {
  const data = fs.readFileSync(file);
  if (path.extname(file).toLowerCase() !== ".apk") {
    return { snapshot: data, entries: null };
  }
  // Minimal ZIP reader: central directory, stored or deflated entries.
  const eocd = data.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (eocd < 0) throw new Error("not a zip file");
  const count = data.readUInt16LE(eocd + 10);
  let at = data.readUInt32LE(eocd + 16);
  const entries = [];
  let snapshot = null;
  for (let i = 0; i < count; i++) {
    const method = data.readUInt16LE(at + 10);
    const size = data.readUInt32LE(at + 20);
    const nameLength = data.readUInt16LE(at + 28);
    const extraLength = data.readUInt16LE(at + 30);
    const commentLength = data.readUInt16LE(at + 32);
    const local = data.readUInt32LE(at + 42);
    const name = data.toString("utf8", at + 46, at + 46 + nameLength);
    entries.push(name);
    if (name === "lib/arm64-v8a/libapp.so") {
      const start = local + 30 + data.readUInt16LE(local + 26) + data.readUInt16LE(local + 28);
      const raw = data.subarray(start, start + size);
      snapshot = method === 0 ? raw : zlib.inflateRawSync(raw);
    }
    at += 46 + nameLength + extraLength + commentLength;
  }
  return { snapshot, entries };
}

function counter(buffer) {
  return (needle) => {
    let total = 0;
    // Dart keeps one-byte strings as Latin-1 and the rest as UTF-16.
    for (const encoding of ["latin1", "utf16le"]) {
      const bytes = Buffer.from(needle, encoding);
      for (let at = buffer.indexOf(bytes); at >= 0; at = buffer.indexOf(bytes, at + bytes.length)) {
        total += 1;
      }
    }
    return total;
  };
}

let targets;
try {
  targets = loadTargets(input);
} catch (error) {
  console.error(`cannot read ${input}: ${error.message}`);
  process.exit(2);
}

let problems = 0;
console.log(`scanning ${input}`);

if (targets.entries) {
  const demoAssets = targets.entries.filter((name) => /portraits\/|\/mock-\d+\./i.test(name));
  const debugAssets = targets.entries.filter((name) => name.endsWith("kernel_blob.bin"));
  if (demoAssets.length) {
    problems += 1;
    console.log(`  [PRESENT] demo assets in the package: ${demoAssets.slice(0, 5).join(", ")}`);
  } else {
    console.log("  [absent]  demo assets in the package");
  }
  if (debugAssets.length) {
    problems += 1;
    console.log("  [WRONG INPUT] this is a debug build (kernel_blob.bin): scan a release build");
  }
}

if (!targets.snapshot) {
  console.log("  [WRONG INPUT] no lib/arm64-v8a/libapp.so in the package: scan a release build");
  process.exit(1);
}

const count = counter(targets.snapshot);
console.log(`  snapshot ${(targets.snapshot.length / 1e6).toFixed(1)} MB`);

for (const control of CONTROLS) {
  if (count(control) === 0) {
    problems += 1;
    console.log(`  [CONTROL MISSING] "${control}" — this scan cannot read the file, so it proves nothing`);
  }
}
for (const marker of NOT_RELEASE) {
  if (count(marker) > 0) {
    problems += 1;
    console.log(`  [WRONG INPUT] "${marker}" — not a release build; only release mode removes the code`);
  }
}

let checked = 0;
for (const [group, needles] of Object.entries(MUST_BE_ABSENT)) {
  const present = needles.filter((needle) => count(needle) > 0);
  checked += needles.length;
  if (present.length) {
    problems += 1;
    console.log(`  [PRESENT] ${group}: ${present.join(", ")}`);
  } else {
    console.log(`  [absent]  ${group} (${needles.length} strings)`);
  }
}

console.log("  expected, and why:");
for (const [needle, why] of Object.entries(EXPECTED)) {
  console.log(`    ${String(count(needle)).padStart(2)} × ${needle} — ${why}`);
}

console.log(
  problems === 0
    ? `\nCLEAN: none of ${checked} test, QA, demo or emulator strings is in the build.`
    : `\n${problems} problem(s): see above.`,
);
process.exit(problems ? 1 : 0);
