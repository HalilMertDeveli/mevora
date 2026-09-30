const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  MAX_DEVICE_TOKENS_PER_COLLECTION,
  isAlreadyExists,
  pushNotificationId,
} = require("../lib/pushIdempotency.js");

describe("push idempotency", () => {
  it("gives the same event the same notification id", () => {
    assert.equal(
      pushNotificationId("u1", "message_a_b_m1"),
      pushNotificationId("u1", "message_a_b_m1"),
    );
  });

  it("separates recipients and events", () => {
    const ids = new Set([
      pushNotificationId("u1", "newMatch_a_b"),
      pushNotificationId("u2", "newMatch_a_b"),
      pushNotificationId("u1", "message_a_b_m1"),
      pushNotificationId("u1", "message_a_b_m2"),
    ]);
    assert.equal(ids.size, 4);
  });

  it("does not let a key collide by shifting text between uid and key", () => {
    assert.notEqual(pushNotificationId("u1_x", "k"), pushNotificationId("u1", "x_k"));
  });

  it("is a valid, bounded document id whatever the key holds", () => {
    const id = pushNotificationId("u1", "a/b/../c with spaces".repeat(50));
    assert.match(id, /^push_[0-9a-f]{40}$/);
  });

  it("recognises ALREADY_EXISTS in the forms the Admin SDK reports", () => {
    assert.equal(isAlreadyExists({code: 6}), true);
    assert.equal(isAlreadyExists({code: "already-exists"}), true);
    assert.equal(isAlreadyExists({code: "ALREADY_EXISTS"}), true);
    assert.equal(isAlreadyExists({code: 5}), false);
    assert.equal(isAlreadyExists(new Error("boom")), false);
    assert.equal(isAlreadyExists(null), false);
  });

  it("caps device tokens per collection", () => {
    assert.equal(MAX_DEVICE_TOKENS_PER_COLLECTION, 20);
  });
});
