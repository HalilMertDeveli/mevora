const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {
  mergeRefreshedTokens,
  readTokenSet,
} = require("../lib/spotifyMusic.js");

// A Spotify refresh grant returns a token pair and nothing about the account.
// The account's identity — its immutable account id and every index key it is
// reachable under — therefore has to survive the refresh by being carried over.
//
// It did not. loadSecrets never read the two fields, so the refresh rebuilt the
// token set without them and saveSecrets, which writes the whole document,
// stored both as null. About an hour after linking, the first music callable to
// refresh wiped them. disconnectMusicAccount builds its delete plan from
// spotifySecrets.indexKeys, so from that point on disconnecting removed fewer
// musicSpotifyIndex documents than the account was reachable under.

const STORED = {
  accessToken: "at_old",
  refreshToken: "rt_old",
  expiresAt: 1_800_000_000_000,
  scope: "user-top-read user-read-recently-played",
  spotifyUserId: "spotify_user",
  spotifyAccountId: "account_immutable",
  indexKeys: ["spotify_user", "account_immutable", "legacy_profile"],
};

describe("readTokenSet", () => {
  it("reads the identity fields a read-modify-write must not drop", () => {
    const tokens = readTokenSet(STORED);

    assert.equal(tokens.spotifyAccountId, "account_immutable");
    assert.deepEqual(tokens.indexKeys, [
      "spotify_user",
      "account_immutable",
      "legacy_profile",
    ]);
  });

  it("reads the token grant", () => {
    const tokens = readTokenSet(STORED);

    assert.equal(tokens.accessToken, "at_old");
    assert.equal(tokens.refreshToken, "rt_old");
    assert.equal(tokens.expiresAt, 1_800_000_000_000);
    assert.equal(tokens.scope, "user-top-read user-read-recently-played");
    assert.equal(tokens.spotifyUserId, "spotify_user");
  });

  it("returns null when there is no access token to work with", () => {
    assert.equal(readTokenSet(undefined), null);
    assert.equal(readTokenSet({}), null);
    assert.equal(readTokenSet({accessToken: 42}), null);
  });

  it("treats a nulled identity field as absent rather than as a value", () => {
    // This is what the document looked like after the bug had run once.
    const tokens = readTokenSet({
      ...STORED,
      spotifyAccountId: null,
      indexKeys: null,
    });

    assert.equal(tokens.spotifyAccountId, undefined);
    assert.equal(tokens.indexKeys, undefined);
  });

  it("drops non-string entries from indexKeys instead of trusting them", () => {
    // Every key becomes a document path, so a number or an object in the array
    // would build a path Firestore rejects.
    const tokens = readTokenSet({
      ...STORED,
      indexKeys: ["good", 7, null, {a: 1}, "also_good"],
    });

    assert.deepEqual(tokens.indexKeys, ["good", "also_good"]);
  });

  it("falls back to 0 for a missing expiry so the token counts as stale", () => {
    const tokens = readTokenSet({accessToken: "at", refreshToken: "rt"});

    assert.equal(tokens.expiresAt, 0);
  });
});

describe("mergeRefreshedTokens", () => {
  const refreshed = {
    accessToken: "at_new",
    refreshToken: "rt_new",
    expiresAt: 1_800_000_900_000,
    scope: "user-top-read user-read-recently-played",
  };

  it("keeps the immutable account id across a refresh", () => {
    const next = mergeRefreshedTokens(readTokenSet(STORED), refreshed);

    assert.equal(next.spotifyAccountId, "account_immutable");
  });

  it("keeps every index key across a refresh", () => {
    // The regression this test exists for: losing these strands
    // musicSpotifyIndex documents when the member later disconnects.
    const next = mergeRefreshedTokens(readTokenSet(STORED), refreshed);

    assert.deepEqual(next.indexKeys, [
      "spotify_user",
      "account_immutable",
      "legacy_profile",
    ]);
  });

  it("keeps the Spotify user id across a refresh", () => {
    const next = mergeRefreshedTokens(readTokenSet(STORED), refreshed);

    assert.equal(next.spotifyUserId, "spotify_user");
  });

  it("takes the new access token and expiry", () => {
    const next = mergeRefreshedTokens(readTokenSet(STORED), refreshed);

    assert.equal(next.accessToken, "at_new");
    assert.equal(next.expiresAt, 1_800_000_900_000);
  });

  it("takes a rotated refresh token", () => {
    const next = mergeRefreshedTokens(readTokenSet(STORED), refreshed);

    assert.equal(next.refreshToken, "rt_new");
  });

  it("keeps the old refresh token when Spotify does not rotate it", () => {
    // Spotify may answer without a refresh_token; dropping it would leave the
    // account unable to refresh again and look like a revoked grant.
    const next = mergeRefreshedTokens(readTokenSet(STORED), {
      ...refreshed,
      refreshToken: undefined,
    });

    assert.equal(next.refreshToken, "rt_old");
  });

  it("keeps the previous scope when the refresh response omits it", () => {
    const next = mergeRefreshedTokens(readTokenSet(STORED), {
      ...refreshed,
      scope: undefined,
    });

    assert.equal(next.scope, "user-top-read user-read-recently-played");
  });

  it("does not invent identity for an account that never had any", () => {
    const next = mergeRefreshedTokens(
      readTokenSet({accessToken: "at", refreshToken: "rt", expiresAt: 1}),
      refreshed,
    );

    assert.equal(next.spotifyAccountId, undefined);
    assert.equal(next.indexKeys, undefined);
  });

  it("survives a second refresh without decaying", () => {
    // The bug only showed up after a refresh, so chaining two proves the
    // identity is carried rather than merely present on the first pass.
    const once = mergeRefreshedTokens(readTokenSet(STORED), refreshed);
    const twice = mergeRefreshedTokens(once, {
      accessToken: "at_third",
      refreshToken: "rt_third",
      expiresAt: 1_800_001_800_000,
    });

    assert.equal(twice.spotifyAccountId, "account_immutable");
    assert.deepEqual(twice.indexKeys, [
      "spotify_user",
      "account_immutable",
      "legacy_profile",
    ]);
    assert.equal(twice.accessToken, "at_third");
  });
});
