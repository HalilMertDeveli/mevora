const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  disconnectPlan,
  refreshFailureKind,
  revokedGrantPlan,
} = require("../lib/spotifyMusic.js");

describe("telling a revoked grant from our own misconfiguration", () => {
  it("reads invalid_grant as the member taking access away", () => {
    assert.equal(refreshFailureKind(400, "invalid_grant"), "revoked");
  });

  it("does not disconnect anyone over a bad client secret", () => {
    // A 400 invalid_client or a 401 is Mevora being wrong, not the member.
    // Treating it as a revocation would disconnect every member at once.
    assert.equal(refreshFailureKind(400, "invalid_client"), "misconfigured");
    assert.equal(refreshFailureKind(401, "invalid_client"), "misconfigured");
    assert.equal(refreshFailureKind(401, null), "misconfigured");
  });

  it("keeps the grant when Spotify is merely unwell", () => {
    for (const status of [429, 500, 502, 503]) {
      assert.equal(
        refreshFailureKind(status, null),
        "transient",
        `status ${status} must not end the connection`,
      );
    }
  });

  it("does not guess a revocation from a status alone", () => {
    assert.equal(refreshFailureKind(400, null), "misconfigured");
    assert.equal(refreshFailureKind(400, undefined), "misconfigured");
    assert.equal(refreshFailureKind(400, "invalid_request"), "misconfigured");
  });
});

describe("what a revoked grant leaves behind", () => {
  const plan = revokedGrantPlan("uid-1");

  it("drops the dead tokens", () => {
    assert.deepEqual(plan.deletes, ["spotifySecrets/uid-1"]);
  });

  it("stops both flags that keep stale taste in circulation", () => {
    // getSameTasteProfiles and the compatibility read both gate on these.
    assert.equal(plan.summaryData.spotifyConnected, false);
    assert.equal(plan.profileData.spotifyConnected, false);
  });

  it("takes the public card down", () => {
    assert.deepEqual(plan.profileData.publicMusic, {
      enabled: false,
      artists: [],
      tracks: [],
      genres: [],
    });
  });

  it("keeps the imported taste, unlike a disconnect the member asked for", () => {
    // Reconnecting after an accidental revocation should not cost them their
    // library; a deliberate disconnect still erases everything.
    assert.ok(
      !plan.deletes.includes("users/uid-1/music/summary"),
      "a revocation must not erase the member's own data",
    );
    assert.ok(
      disconnectPlan("uid-1").deletes.includes("users/uid-1/music/summary"),
      "a deliberate disconnect still erases it",
    );
  });

  it("leaves the music ownership index alone", () => {
    // The account is still theirs; only the grant died.
    assert.ok(!plan.deletes.some((path) => path.startsWith("musicSpotifyIndex/")));
  });
});
