const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {routeFor, FcmTypes} = require("../lib/notifications.js");

describe("fcm route resolution", () => {
  it("routes an incoming like to the Likes You screen", () => {
    // FcmTypes.incomingLike and its copy already existed, but routeFor did not
    // handle it: the push and the stored notification document both carried a
    // null route, so tapping either went nowhere.
    assert.equal(routeFor(FcmTypes.incomingLike, {}), "/likes-you");
  });

  it("does not need the liker identity to route", () => {
    // Who liked you is premium-gated behind getIncomingLikes; the payload must
    // stay free of liker identity.
    assert.equal(routeFor(FcmTypes.incomingLike, {}), "/likes-you");
  });

  it("keeps the existing destinations", () => {
    assert.equal(
      routeFor(FcmTypes.incomingCall, {callId: "c1"}),
      "/call/incoming/c1",
    );
    assert.equal(routeFor(FcmTypes.boostActivated, {}), "/boost");
    assert.equal(routeFor(FcmTypes.boostExpired, {}), "/boost");
    assert.equal(routeFor(FcmTypes.newMessage, {matchId: "a_b"}), "/chat/a_b");
    assert.equal(routeFor(FcmTypes.newMatch, {matchId: "a_b"}), "/chat/a_b");
  });

  it("returns null when a chat route has no match id", () => {
    assert.equal(routeFor(FcmTypes.newMessage, {}), null);
  });
});
