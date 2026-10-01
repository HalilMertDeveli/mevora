const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  startFaceAnchorVerification: start,
  submitFaceAnchorVerification: submit,
  sweepFaceAnchorSelfies: sweep,
} = require("../lib/faceAnchor/faceAnchorService.js");
const {
  ATTEMPT_TTL_MS,
  COOLDOWN_MS,
  MAX_ATTEMPTS_PER_WINDOW,
  PROCESSING_STALE_MS,
  SELFIE_MAX_AGE_MS,
} = require("../lib/faceAnchor/faceAnchorRecord.js");
const {
  CONSENT,
  JPEG,
  createFaceAnchorWorld,
  outage,
  publishedPath,
  refusal,
  rejectsWith,
  verdict,
} = require("./helpers/faceAnchorHarness.cjs");

/** start + upload, the way the app does it. */
async function openAttempt(w, photoId = "p1", selfie) {
  const opened = await start(w.deps, w.uid, {photoId, consentVersion: CONSENT});
  w.uploadSelfie(opened.attemptId, selfie);
  return opened;
}

async function verify(w, photoId = "p1") {
  const {attemptId} = await openAttempt(w, photoId);
  return submit(w.deps, w.uid, {attemptId});
}

describe("face anchor — a successful verification", () => {
  it("records the verdict on the ledger and projects it onto the profile", async () => {
    const w = createFaceAnchorWorld();
    const result = await verify(w, "p2");
    assert.deepEqual(result, {status: "verified", reason: null, photoId: "p2"});

    const entry = w.ledger("p2");
    assert.equal(entry.faceAnchor.status, "verified");
    assert.equal(entry.faceAnchor.storagePath, publishedPath(w.uid, "p2"));

    const profile = w.profile();
    assert.equal(profile.faceAnchorRequired, true);
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p2"]);
    // The verified photo is now the primary one, first in the array.
    assert.deepEqual(profile.photos.map((p) => p.id), ["p2", "p1", "p3"]);
    assert.deepEqual(profile.photos.map((p) => p.isPrimary), [true, false, false]);
    assert.deepEqual(profile.photos.map((p) => p.order), [0, 1, 2]);
    assert.equal(profile.photos[0].faceAnchorVerified, true);
    assert.equal("faceAnchorVerified" in profile.photos[1], false);
  });

  it("runs liveness first, and the face match only after it passes", async () => {
    const w = createFaceAnchorWorld();
    await verify(w);
    assert.deepEqual(w.provider.calls.map((c) => c.call), ["liveness", "match"]);
  });

  it("stores nothing biometric: no score, no payload, no selfie reference", async () => {
    const w = createFaceAnchorWorld();
    await verify(w);
    assert.deepEqual(
      Object.keys(w.ledger("p1").faceAnchor).sort(),
      ["attemptId", "provider", "status", "storagePath", "verifiedAt"],
    );
    const stored = JSON.stringify([w.state(), w.ledger("p1"), w.profile()]);
    for (const forbidden of ["score", "embedding", "landmark", "similarity", "request_id", "face-anchor/pending"]) {
      assert.equal(stored.includes(forbidden), false, `stored documents must not mention ${forbidden}`);
    }
  });

  it("deletes the selfie", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), true);
    await submit(w.deps, w.uid, {attemptId});
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });

  it("a second anchor can be verified, and the member's primary stays put", async () => {
    const w = createFaceAnchorWorld();
    await verify(w, "p1");
    w.advance(COOLDOWN_MS);
    await verify(w, "p3");
    const profile = w.profile();
    assert.deepEqual(profile.faceAnchorPhotoIds, ["p1", "p3"]);
    assert.equal(profile.photos[0].id, "p1");
    assert.equal(profile.photos.filter((p) => p.isPrimary).length, 1);
  });
});

describe("face anchor — provider outcomes", () => {
  it("liveness failure: not verified, the face match is never run", async () => {
    const w = createFaceAnchorWorld();
    w.provider.liveness = "not_live";
    const {attemptId} = await openAttempt(w);
    const result = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(result, {status: "failed", reason: "liveness_failed", photoId: "p1"});
    assert.deepEqual(w.provider.calls.map((c) => c.call), ["liveness"]);
    assert.equal(w.ledger("p1").faceAnchor, undefined);
    assert.equal(w.profile().faceAnchorRequired, undefined);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });

  it("no face in the selfie is a liveness failure", async () => {
    const w = createFaceAnchorWorld();
    w.provider.liveness = "no_face";
    assert.equal((await verify(w)).reason, "liveness_failed");
  });

  it("face mismatch: not verified, selfie deleted", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "no_match";
    const {attemptId} = await openAttempt(w);
    const result = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(result, {status: "failed", reason: "face_mismatch", photoId: "p1"});
    assert.equal(w.ledger("p1").faceAnchor, undefined);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });

  it("a profile photo with no single clear face cannot be an anchor", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "reference_unusable";
    assert.deepEqual(await verify(w), {status: "failed", reason: "photo_face_unclear", photoId: "p1"});
  });

  it("an outage fails closed, deletes the selfie and gives the attempt back", async () => {
    const w = createFaceAnchorWorld();
    w.provider.failures.liveness.push(outage());
    const {attemptId} = await openAttempt(w);
    const result = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(result, {status: "error", reason: "technical_error", photoId: "p1"});
    assert.equal(w.ledger("p1").faceAnchor, undefined);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
    assert.equal(w.state().attemptCount, 0);
    assert.equal(w.state().refundCount, 1);
  });

  it("a non-retryable provider failure fails closed and is not refunded", async () => {
    const w = createFaceAnchorWorld();
    w.provider.failures.liveness.push(refusal());
    const result = await verify(w);
    assert.equal(result.status, "error");
    assert.equal(w.state().attemptCount, 1);
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });

  it("an answer outside the closed vocabulary is not a pass", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "Approved"; // not one of MEVORA's words
    const result = await verify(w);
    assert.equal(result.status, "failed");
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });

  it("retries the face match once after a blip instead of re-billing liveness", async () => {
    const w = createFaceAnchorWorld();
    w.provider.failures.match.push(outage());
    const result = await verify(w);
    assert.equal(result.status, "verified");
    assert.deepEqual(w.provider.calls.map((c) => c.call), ["liveness", "match", "match"]);
  });

  it("refuses to start or submit when no provider is configured", async () => {
    const w = createFaceAnchorWorld();
    w.activeProvider = null;
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "face-anchor-unavailable");
    w.activeProvider = w.provider;
    const {attemptId} = await openAttempt(w);
    w.activeProvider = null;
    await rejectsWith(submit(w.deps, w.uid, {attemptId}), "face-anchor-unavailable");
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });
});

describe("face anchor — what the client cannot do", () => {
  it("a client-supplied bypass field changes nothing", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "no_match";
    const opened = await start(w.deps, w.uid, {
      photoId: "p1",
      consentVersion: CONSENT,
      testMode: true,
      fakeSuccess: true,
      skipFaceCheck: true,
      faceMatch: true,
    });
    w.uploadSelfie(opened.attemptId);
    const result = await submit(w.deps, w.uid, {
      attemptId: opened.attemptId,
      testMode: true,
      fakeSuccess: true,
      outcome: "verified",
    });
    assert.equal(result.status, "failed");
    assert.equal(w.provider.calls.length, 2);
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });

  it("cannot verify a photo that is not on their own profile", async () => {
    const a = createFaceAnchorWorld({uid: "user-a"});
    // user-b's photo id means nothing under user-a.
    await rejectsWith(start(a.deps, "user-a", {photoId: "b-photo", consentVersion: CONSENT}), "photo-not-found");
  });

  it("cannot submit another member's attempt", async () => {
    const w = createFaceAnchorWorld({uid: "user-a"});
    const {attemptId} = await openAttempt(w);
    await w.db.doc("users/user-b").set({uid: "user-b", accountStatus: "active"});
    await rejectsWith(submit(w.deps, "user-b", {attemptId}), "attempt-not-found");
    assert.equal(w.provider.calls.length, 0);
  });

  it("cannot use another member's selfie: the path is the caller's own", async () => {
    const w = createFaceAnchorWorld({uid: "user-a"});
    const opened = await start(w.deps, "user-a", {photoId: "p1", consentVersion: CONSENT});
    // A selfie sits under user-b's prefix with the same attempt id.
    w.bucket.put(`face-anchor/pending/user-b/${opened.attemptId}`, JPEG("b"));
    await rejectsWith(submit(w.deps, "user-a", {attemptId: opened.attemptId}), "selfie-missing");
    assert.equal(w.provider.calls.length, 0);
  });

  it("an attempt opened for photo A cannot verify photo B", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w, "p1");
    // The only input submit takes is the attempt id; the photo comes from the
    // server's own record of the attempt.
    const result = await submit(w.deps, w.uid, {attemptId, photoId: "p2"});
    assert.equal(result.photoId, "p1");
    assert.equal(w.ledger("p2").faceAnchor, undefined);
    assert.equal(w.ledger("p1").faceAnchor.status, "verified");
  });

  it("opening an attempt for another photo retires the earlier one", async () => {
    const w = createFaceAnchorWorld();
    const first = await openAttempt(w, "p1");
    const second = await start(w.deps, w.uid, {photoId: "p2", consentVersion: CONSENT});
    assert.equal(w.bucket.has(w.selfiePath(first.attemptId)), false);
    await rejectsWith(submit(w.deps, w.uid, {attemptId: first.attemptId}), "attempt-not-found");
    assert.notEqual(second.attemptId, first.attemptId);
  });

  it("the profile photo itself, sent back as the selfie, is refused unbilled", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w, "p1", JPEG("photo-p1"));
    const result = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(result, {status: "failed", reason: "selfie_invalid", photoId: "p1"});
    assert.equal(w.provider.calls.length, 0);
    assert.equal(w.state().attemptCount ?? 0, 0);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });

  it("bytes that are not an image are refused unbilled", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w, "p1", Buffer.from("this is not an image at all"));
    assert.equal((await submit(w.deps, w.uid, {attemptId})).reason, "selfie_invalid");
    assert.equal(w.provider.calls.length, 0);
  });

  it("an undecodable selfie is refused unbilled", async () => {
    const w = createFaceAnchorWorld();
    w.normalize = async (bytes) => {
      if (bytes.toString().includes("selfie")) throw new Error("unsupported image format");
      return bytes;
    };
    assert.equal((await verify(w)).reason, "selfie_invalid");
    assert.equal(w.provider.calls.length, 0);
  });

  it("requires consent to the current wording", async () => {
    const w = createFaceAnchorWorld();
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1"}), "consent-required");
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT + 1}), "consent-required");
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: String(CONSENT)}), "consent-required");
    await start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT});
    assert.equal(w.state().consentVersion, CONSENT);
    assert.ok(w.state().consentAt);
  });

  it("refuses a suspended account", async () => {
    const w = createFaceAnchorWorld();
    await w.db.doc(`users/${w.uid}`).set({isBanned: true}, {merge: true});
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "account-suspended");
  });

  it("rejects malformed ids", async () => {
    const w = createFaceAnchorWorld();
    await rejectsWith(start(w.deps, w.uid, {photoId: "../../etc", consentVersion: CONSENT}), "photo-id-required");
    await rejectsWith(submit(w.deps, w.uid, {attemptId: "a/b"}), "attempt-id-required");
    await rejectsWith(submit(w.deps, w.uid, {}), "attempt-id-required");
  });
});

describe("face anchor — moderation comes first", () => {
  it("a photo that is not approved cannot be verified", async () => {
    for (const status of ["manual_review", "rejected", "processing"]) {
      const w = createFaceAnchorWorld({ledger: {p1: {status}}});
      await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "photo-not-approved");
    }
  });

  it("a pending photo is moderated inline before the answer", async () => {
    const w = createFaceAnchorWorld({ledger: {p1: {status: "pending", storagePath: null}}});
    w.onModeratePending = async (uid, imageId) => {
      await w.db.doc(`users/${uid}/photoModeration/${imageId}`).set(
        {status: "approved", storagePath: publishedPath(uid, imageId)}, {merge: true});
    };
    const opened = await start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT});
    assert.deepEqual(w.moderated, ["p1"]);
    assert.equal(opened.status, "awaiting_selfie");
  });

  it("a photo that is still pending after that is not verifiable yet", async () => {
    const w = createFaceAnchorWorld({ledger: {p1: {status: "pending", storagePath: null}}});
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "photo-not-approved");
  });

  it("an already verified photo is not verified — or billed — again", async () => {
    const w = createFaceAnchorWorld();
    await verify(w);
    w.advance(COOLDOWN_MS);
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "already-verified");
  });

  it("a photo rejected while the verification runs is not verified", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const pending = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));
    await w.db.doc(`users/${w.uid}/photoModeration/p1`).set({status: "rejected"}, {merge: true});
    release();
    const result = await pending;
    assert.deepEqual(result, {status: "error", reason: "technical_error", photoId: "p1"});
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });

  it("a photo removed while the verification runs is not verified", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const pending = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));
    const profile = w.profile();
    await w.db.doc(`profiles/${w.uid}`).set(
      {photos: profile.photos.filter((p) => p.id !== "p1")}, {merge: true});
    release();
    assert.equal((await pending).status, "error");
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });

  it("a published object replaced while the verification runs is not verified", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const pending = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));
    w.bucket.put(publishedPath(w.uid, "p1"), JPEG("somebody-else"));
    release();
    assert.equal((await pending).status, "error");
    assert.equal(w.ledger("p1").faceAnchor, undefined);
  });
});

describe("face anchor — idempotency and restarts", () => {
  it("repeating a finished submit returns the same answer without calling the provider", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    const first = await submit(w.deps, w.uid, {attemptId});
    const calls = w.provider.calls.length;
    const second = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(second, first);
    assert.equal(w.provider.calls.length, calls);
    assert.equal(w.state().attemptCount, 1);
  });

  it("a double tap runs one verification", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    const results = await Promise.all([
      submit(w.deps, w.uid, {attemptId}),
      submit(w.deps, w.uid, {attemptId}),
    ]);
    assert.equal(w.provider.calls.filter((c) => c.call === "liveness").length, 1);
    assert.equal(w.state().attemptCount, 1);
    assert.ok(results.some((r) => r.status === "verified"));
    assert.equal(w.state().status, "verified");
  });

  it("a submit while one is running reports processing and does not re-run", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const running = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));
    assert.equal(w.state().status, "processing");
    const again = await submit(w.deps, w.uid, {attemptId});
    assert.equal(again.status, "processing");
    // A new attempt cannot be opened under a running verification either.
    await rejectsWith(start(w.deps, w.uid, {photoId: "p2", consentVersion: CONSENT}), "verification-in-progress");
    release();
    assert.equal((await running).status, "verified");
    assert.equal(w.provider.calls.filter((c) => c.call === "liveness").length, 1);
  });

  it("the state after a restart is whatever the server last recorded", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    // The app is killed before submit. On restart it reads the state document.
    assert.equal(w.state().status, "awaiting_selfie");
    assert.equal(w.state().attemptId, attemptId);
    // It can carry on with the same attempt; nothing was billed in between.
    assert.equal((await submit(w.deps, w.uid, {attemptId})).status, "verified");
    assert.equal(w.state().attemptCount, 1);
  });

  it("an invocation that died leaves a recoverable attempt, and its late result cannot land", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const zombie = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));

    w.advance(PROCESSING_STALE_MS + 1);
    const recovered = await submit(w.deps, w.uid, {attemptId});
    assert.deepEqual(recovered, {status: "error", reason: "technical_error", photoId: "p1"});

    // The member opens a new attempt for another photo …
    const next = await start(w.deps, w.uid, {photoId: "p2", consentVersion: CONSENT});
    // … and only then does the dead invocation finish with a "match".
    release();
    await zombie;
    assert.equal(w.ledger("p1").faceAnchor, undefined, "a stale result must not verify anything");
    assert.equal(w.state().attemptId, next.attemptId);
    assert.equal(w.state().status, "awaiting_selfie");
  });

  it("an expired attempt is closed without calling the provider", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    w.advance(ATTEMPT_TTL_MS);
    const result = await submit(w.deps, w.uid, {attemptId});
    assert.equal(result.status, "expired");
    assert.equal(w.provider.calls.length, 0);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });

  it("submitting before the selfie is uploaded changes nothing", async () => {
    const w = createFaceAnchorWorld();
    const opened = await start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT});
    await rejectsWith(submit(w.deps, w.uid, {attemptId: opened.attemptId}), "selfie-missing");
    assert.equal(w.state().status, "awaiting_selfie");
    assert.equal(w.provider.calls.length, 0);
  });

  it("a result arriving after the account was deleted re-creates nothing", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    let release;
    w.provider.gate = new Promise((resolve) => {
      release = resolve;
    });
    const pending = submit(w.deps, w.uid, {attemptId});
    await new Promise((resolve) => setImmediate(resolve));
    // deleteUserAccount ran in between.
    for (const path of w.db.paths()) {
      if (path.includes(w.uid)) await w.db.doc(path).delete();
    }
    release();
    await pending;
    assert.deepEqual(w.db.paths().filter((path) => path.includes(w.uid)), []);
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });
});

describe("face anchor — budget", () => {
  it("enforces a cooldown between billed attempts", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "no_match";
    await verify(w);
    const {attemptId} = await openAttempt(w);
    const error = await rejectsWith(submit(w.deps, w.uid, {attemptId}), "face-anchor-cooldown");
    assert.equal(error.code, "resource-exhausted");
    assert.ok(error.details.retryAfterSeconds > 0);
    assert.equal(w.provider.calls.length, 2, "the refused attempt never reached the provider");
    // The same attempt goes through once the cooldown has passed.
    w.advance(COOLDOWN_MS);
    assert.equal((await submit(w.deps, w.uid, {attemptId})).status, "failed");
  });

  it("stops after the daily number of billed attempts", async () => {
    const w = createFaceAnchorWorld();
    w.provider.match = "no_match";
    for (let i = 0; i < MAX_ATTEMPTS_PER_WINDOW; i += 1) {
      assert.equal((await verify(w)).status, "failed");
      w.advance(COOLDOWN_MS);
    }
    const {attemptId} = await openAttempt(w);
    await rejectsWith(submit(w.deps, w.uid, {attemptId}), "face-anchor-attempt-limit");
    assert.equal(w.provider.calls.filter((c) => c.call === "liveness").length, MAX_ATTEMPTS_PER_WINDOW);
    // A new day, a new budget.
    w.advance(24 * 60 * 60 * 1000);
    const fresh = await openAttempt(w);
    assert.equal((await submit(w.deps, w.uid, {attemptId: fresh.attemptId})).status, "failed");
  });

  it("opening attempts without submitting costs nothing", async () => {
    const w = createFaceAnchorWorld();
    for (let i = 0; i < 8; i += 1) {
      await start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT});
    }
    assert.equal(w.state().attemptCount ?? 0, 0);
    assert.equal((await verify(w)).status, "verified");
  });

  it("but opening them is itself rate limited", async () => {
    const w = createFaceAnchorWorld();
    for (let i = 0; i < 20; i += 1) {
      await start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT});
    }
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "too-many-requests");
  });

  it("outage refunds are capped, so an outage is not an unlimited budget", async () => {
    const w = createFaceAnchorWorld();
    for (let i = 0; i < 4; i += 1) {
      w.provider.failures.liveness.push(outage());
      await verify(w);
      w.advance(COOLDOWN_MS);
    }
    // Four attempts, two of them refunded.
    assert.equal(w.state().attemptCount, 2);
    assert.equal(w.state().refundCount, 2);
  });

  it("the global daily cap stops verification for everyone", async () => {
    const w = createFaceAnchorWorld();
    w.cap = 1;
    w.provider.match = "no_match";
    await verify(w);
    w.advance(COOLDOWN_MS);
    const {attemptId} = await openAttempt(w);
    await rejectsWith(submit(w.deps, w.uid, {attemptId}), "face-anchor-unavailable");
    assert.equal(w.provider.calls.filter((c) => c.call === "liveness").length, 1);
  });
});

describe("face anchor — the selfie never outlives its attempt", () => {
  it("is deleted on every terminal result", async () => {
    const outcomes = [
      (w) => { /* success */ },
      (w) => {
        w.provider.liveness = "not_live";
      },
      (w) => {
        w.provider.match = "no_match";
      },
      (w) => {
        w.provider.failures.liveness.push(outage());
      },
      (w) => {
        w.provider.failures.liveness.push(refusal());
      },
    ];
    for (const arrange of outcomes) {
      const w = createFaceAnchorWorld();
      arrange(w);
      const {attemptId} = await openAttempt(w);
      await submit(w.deps, w.uid, {attemptId});
      assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
      assert.equal([...w.bucket.files.keys()].some((k) => k.startsWith("face-anchor/")), false);
    }
  });

  it("the sweep removes an abandoned selfie and closes its attempt", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    // The app was closed after the upload; nothing ever calls submit.
    w.advance(SELFIE_MAX_AGE_MS - 1000);
    assert.deepEqual(await sweep(w.deps), {scanned: 1, deleted: 0});
    w.advance(2000);
    assert.deepEqual(await sweep(w.deps), {scanned: 1, deleted: 1});
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
    assert.equal(w.state().status, "expired");
  });

  it("the sweep removes a selfie no attempt knows about", async () => {
    const w = createFaceAnchorWorld();
    w.bucket.put("face-anchor/pending/ghost-user/orphan", JPEG("orphan"));
    w.advance(SELFIE_MAX_AGE_MS + 1);
    assert.equal((await sweep(w.deps)).deleted, 1);
    assert.equal(w.bucket.has("face-anchor/pending/ghost-user/orphan"), false);
    // No state document was invented for a user that has none.
    assert.equal(w.db.has("users/ghost-user/faceAnchor/state"), false);
  });

  it("the sweep pages through a large backlog", async () => {
    const w = createFaceAnchorWorld();
    for (let i = 0; i < 25; i += 1) {
      w.bucket.put(`face-anchor/pending/u${i}/a`, JPEG(String(i)));
    }
    w.advance(SELFIE_MAX_AGE_MS + 1);
    const result = await sweep(w.deps, {pageSize: 10});
    assert.equal(result.deleted, 25);
  });

  it("the sweep leaves profile photos alone", async () => {
    const w = createFaceAnchorWorld();
    w.advance(SELFIE_MAX_AGE_MS * 10);
    await sweep(w.deps);
    for (const id of ["p1", "p2", "p3"]) {
      assert.equal(w.bucket.has(publishedPath(w.uid, id)), true);
    }
  });

  it("closes an attempt whose invocation died, when its selfie is swept", async () => {
    const w = createFaceAnchorWorld();
    const {attemptId} = await openAttempt(w);
    await w.db.doc(`users/${w.uid}/faceAnchor/state`).update({
      status: "processing",
      processingStartedAtMs: w.now,
      attemptCount: 1,
    });
    w.advance(SELFIE_MAX_AGE_MS + 1);
    await sweep(w.deps);
    assert.equal(w.state().status, "error");
    assert.equal(w.bucket.has(w.selfiePath(attemptId)), false);
  });
});

describe("face anchor — a verified profile keeps its seed helper honest", () => {
  it("verdict() seeds a ledger entry the service treats as verified", async () => {
    const w = createFaceAnchorWorld({ledger: {p1: {faceAnchor: verdict("member-1", "p1")}}});
    await rejectsWith(start(w.deps, w.uid, {photoId: "p1", consentVersion: CONSENT}), "already-verified");
  });
});
