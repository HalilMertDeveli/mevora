/**
 * Contract tests for Discover Like / recordSwipe match payload.
 * Guards against regressions that previously caused INTERNAL on like
 * (Firestore transaction reads-after-writes) and Chat UI missing participant fields.
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const socialSrc = fs.readFileSync(
  path.join(__dirname, "../src/social.ts"),
  "utf8",
);
const backendSrc = fs.readFileSync(
  path.join(__dirname, "../src/backend.ts"),
  "utf8",
);
const notificationsSrc = fs.readFileSync(
  path.join(__dirname, "../src/notifications.ts"),
  "utf8",
);

describe("recordSwipe transaction contract", () => {
  it("reads all docs before writes inside the transaction", () => {
    const txBlock = socialSrc.slice(
      socialSrc.indexOf("db.runTransaction"),
      socialSrc.indexOf("Incoming-like push must stay outside"),
    );
    const firstWrite = txBlock.indexOf("tx.set");
    const lastGet = Math.max(
      txBlock.lastIndexOf("tx.get"),
      txBlock.lastIndexOf("Promise.all"),
    );
    assert.ok(firstWrite > 0, "expected tx.set in transaction");
    assert.ok(lastGet > 0, "expected tx.get / Promise.all reads");
    assert.ok(
      lastGet < firstWrite,
      "Firestore tx must complete reads before any write",
    );
  });

  it("creates mutual_like matches with Chat participant fields", () => {
    assert.match(socialSrc, /source:\s*"mutual_like"/);
    assert.match(socialSrc, /participantNames:/);
    assert.match(socialSrc, /participantPhotos:/);
    assert.match(socialSrc, /participantVerified:/);
  });

  it("does not call profilePreview inside the transaction", () => {
    const txBlock = socialSrc.slice(
      socialSrc.indexOf("db.runTransaction"),
      socialSrc.indexOf("Incoming-like push must stay outside"),
    );
    assert.equal(
      /profilePreview\(/.test(txBlock),
      false,
      "non-tx profile reads inside transaction caused INTERNAL",
    );
  });
});

describe("recordDiscoveryDecision contract", () => {
  it("soft-fails incoming like push and logs unexpected errors", () => {
    assert.match(backendSrc, /recordDiscoveryDecision incomingLike push failed/);
    assert.match(backendSrc, /recordDiscoveryDecision failed/);
    assert.match(backendSrc, /source:\s*"mutual_like"/);
    assert.match(backendSrc, /participantNames:/);
    assert.match(backendSrc, /participantVerified:/);
  });
});

describe("sendUserPush soft-fail", () => {
  it("wraps notifications inbox write in try/catch", () => {
    const addIdx = notificationsSrc.indexOf('db.collection("notifications").add');
    assert.ok(addIdx > 0);
    const before = notificationsSrc.slice(Math.max(0, addIdx - 120), addIdx);
    assert.match(before, /try\s*\{/);
  });
});
