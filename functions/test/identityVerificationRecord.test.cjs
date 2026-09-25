const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  IDENTITY_COOLDOWN_MS,
  IDENTITY_MAX_ATTEMPTS_PER_DAY,
  IDENTITY_VERIFICATION_SCHEMA_VERSION,
  canStartIdentitySession,
  parseIdentityVerificationDoc,
  shouldApplyEvent,
  grantsVerifiedBadge,
} = require("../lib/identity/index.js");

const NOW = Date.UTC(2026, 8, 23, 12, 0, 0);
const ts = (ms) => ({toMillis: () => ms});
const doc = (over = {}) => parseIdentityVerificationDoc({
  schemaVersion: IDENTITY_VERIFICATION_SCHEMA_VERSION,
  provider: "didit",
  status: "not_started",
  attemptCount: 0,
  ...over,
});

describe("identity verification document parsing", () => {
  it("treats a missing document as a fresh, unverified user", () => {
    const parsed = parseIdentityVerificationDoc(undefined);
    assert.equal(parsed.status, "not_started");
    assert.equal(parsed.attemptCount, 0);
    assert.equal(grantsVerifiedBadge(parsed.status), false);
  });

  it("marks a document with no schemaVersion as legacy", () => {
    assert.equal(parseIdentityVerificationDoc({status: "verified"}).schemaVersion, 0);
  });

  it("drops a provider reason it does not recognise", () => {
    assert.equal(doc({reason: "manual_review"}).reason, "manual_review");
    assert.equal(doc({reason: "FORGERY_SUSPECTED_MRZ"}).reason, undefined);
    assert.equal(doc({reason: 42}).reason, undefined);
  });

  it("never parses an unknown status into a verified one", () => {
    for (const raw of ["Approved", "approved", true, 1, {}, []]) {
      assert.equal(grantsVerifiedBadge(doc({status: raw}).status), false);
    }
  });
});

describe("starting a session", () => {
  it("allows a first attempt", () => {
    assert.deepEqual(canStartIdentitySession(doc(), NOW), {allowed: true});
  });

  it("refuses a verified user", () => {
    const gate = canStartIdentitySession(doc({status: "verified"}), NOW);
    assert.equal(gate.allowed, false);
    assert.equal(gate.reason, "already_verified");
  });

  it("refuses a second session while one is in flight", () => {
    for (const status of ["pending", "in_progress", "in_review"]) {
      const gate = canStartIdentitySession(doc({status}), NOW);
      assert.equal(gate.allowed, false, `status=${status}`);
      assert.equal(gate.reason, "in_flight", `status=${status}`);
    }
  });

  it("enforces the cooldown and reports how long is left", () => {
    const gate = canStartIdentitySession(
      doc({status: "declined", attemptCount: 1, lastAttemptAt: ts(NOW - 3 * 60 * 1000)}),
      NOW,
    );
    assert.equal(gate.allowed, false);
    assert.equal(gate.reason, "cooldown");
    assert.equal(gate.retryAfterSeconds, Math.ceil((IDENTITY_COOLDOWN_MS - 3 * 60 * 1000) / 1000));
  });

  it("allows a retry once the cooldown has lifted and budget remains", () => {
    const gate = canStartIdentitySession(
      doc({status: "declined", attemptCount: 2, lastAttemptAt: ts(NOW - 20 * 60 * 1000)}),
      NOW,
    );
    assert.equal(gate.allowed, true);
  });

  it("enforces the daily attempt budget", () => {
    const gate = canStartIdentitySession(
      doc({
        status: "declined",
        attemptCount: IDENTITY_MAX_ATTEMPTS_PER_DAY,
        lastAttemptAt: ts(NOW - 2 * 60 * 60 * 1000),
      }),
      NOW,
    );
    assert.equal(gate.allowed, false);
    assert.equal(gate.reason, "attempt_limit");
  });

  it("resets the budget a day after the last attempt", () => {
    const gate = canStartIdentitySession(
      doc({
        status: "declined",
        attemptCount: IDENTITY_MAX_ATTEMPTS_PER_DAY,
        lastAttemptAt: ts(NOW - 25 * 60 * 60 * 1000),
      }),
      NOW,
    );
    assert.equal(gate.allowed, true);
  });
});

describe("applying provider events", () => {
  it("applies the first event", () => {
    assert.deepEqual(shouldApplyEvent(doc(), {eventId: "e1", occurredAtMs: NOW}), {apply: true});
  });

  it("ignores a redelivery of the event it already applied", () => {
    const result = shouldApplyEvent(
      doc({lastEventId: "e1", lastEventAtMs: NOW}),
      {eventId: "e1", occurredAtMs: NOW},
    );
    assert.equal(result.apply, false);
    assert.equal(result.skipReason, "duplicate");
  });

  it("refuses to let a stale event walk back a newer state", () => {
    const verified = doc({status: "verified", lastEventId: "e2", lastEventAtMs: NOW});
    const result = shouldApplyEvent(verified, {eventId: "e1", occurredAtMs: NOW - 60_000});
    assert.equal(result.apply, false);
    assert.equal(result.skipReason, "stale");
  });

  it("applies a genuinely newer event", () => {
    const result = shouldApplyEvent(
      doc({status: "in_progress", lastEventId: "e1", lastEventAtMs: NOW - 60_000}),
      {eventId: "e2", occurredAtMs: NOW},
    );
    assert.equal(result.apply, true);
  });

  it("applies an event with the same timestamp but a new id", () => {
    const result = shouldApplyEvent(
      doc({lastEventId: "e1", lastEventAtMs: NOW}),
      {eventId: "e2", occurredAtMs: NOW},
    );
    assert.equal(result.apply, true);
  });

  it("refuses an undateable event once a dated one has been applied", () => {
    const result = shouldApplyEvent(
      doc({status: "verified", lastEventId: "e1", lastEventAtMs: NOW}),
      {eventId: "e2"},
    );
    assert.equal(result.apply, false);
    assert.equal(result.skipReason, "stale");
  });
});
