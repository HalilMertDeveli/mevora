const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {
  mergeRefreshedTokens,
  readTokenSet,
  resolveRefreshWrite,
} = require("../lib/spotifyMusic.js");

// syncSpotifyTaste checks the throttle by reading lastSyncedAt and only writes
// it at the end of the sync, so two concurrent calls for the same member both
// pass the throttle and both reach the token refresh. Spotify rotates the
// refresh token on a PKCE refresh grant, so only one of them ends up holding a
// live pair — and before this guard the loser could still overwrite the
// document with its superseded one, which looks to the member like Spotify
// disconnected itself.

const STORED = {
  accessToken: "at_0",
  refreshToken: "rt_0",
  expiresAt: 1_800_000_000_000,
  scope: "user-top-read",
  spotifyUserId: "spotify_user",
  spotifyAccountId: "account_immutable",
  indexKeys: ["spotify_user", "account_immutable"],
};

const REFRESHED_A = {
  accessToken: "at_a",
  refreshToken: "rt_a",
  expiresAt: 1_800_000_900_000,
};

function merged(refreshed, previous = readTokenSet(STORED)) {
  return mergeRefreshedTokens(previous, refreshed);
}

describe("resolveRefreshWrite", () => {
  it("stores the refreshed pair when nothing else has moved", () => {
    const outcome = resolveRefreshWrite(
      "rt_0",
      readTokenSet(STORED),
      merged(REFRESHED_A),
    );

    assert.equal(outcome.action, "store");
    assert.equal(outcome.tokens.accessToken, "at_a");
    assert.equal(outcome.tokens.refreshToken, "rt_a");
  });

  it("keeps the stored pair when another call already rotated the token", () => {
    // The race: this call refreshed rt_0, but the document now holds rt_a
    // because the other call got there first. Writing would put a superseded
    // pair back on file.
    const winner = {...STORED, accessToken: "at_a", refreshToken: "rt_a"};

    const outcome = resolveRefreshWrite(
      "rt_0",
      readTokenSet(winner),
      merged({
        accessToken: "at_b",
        refreshToken: "rt_b",
        expiresAt: 1_800_000_900_000,
      }),
    );

    assert.equal(outcome.action, "keep-stored");
    assert.equal(outcome.tokens.accessToken, "at_a");
    assert.equal(outcome.tokens.refreshToken, "rt_a");
  });

  it("returns a usable token set to the loser rather than an error", () => {
    // The losing call still has work to do; it must continue with the live
    // token instead of failing a healthy account.
    const winner = {...STORED, accessToken: "at_a", refreshToken: "rt_a"};

    const outcome = resolveRefreshWrite(
      "rt_0",
      readTokenSet(winner),
      merged(REFRESHED_A),
    );

    assert.equal(outcome.action, "keep-stored");
    assert.equal(typeof outcome.tokens.accessToken, "string");
    assert.ok(outcome.tokens.expiresAt > 0);
  });

  it("abandons the write when a disconnect removed the document", () => {
    // disconnectMusicAccount deletes spotifySecrets. A refresh landing after
    // it must not resurrect tokens for an account the member just unlinked.
    const outcome = resolveRefreshWrite("rt_0", null, merged(REFRESHED_A));

    assert.equal(outcome.action, "abandon");
    assert.equal(outcome.tokens, undefined);
  });

  it("stores when the document has no refresh token to compare against", () => {
    // Nothing to lose a race against: an account with an access token but no
    // refresh grant is not mid-rotation.
    const outcome = resolveRefreshWrite(
      "rt_0",
      readTokenSet({accessToken: "at_0", expiresAt: 1}),
      merged(REFRESHED_A),
    );

    assert.equal(outcome.action, "store");
  });

  it("stores when the stored token is still the one we refreshed from", () => {
    // A retry of the same call, not a race: the document is unchanged.
    const outcome = resolveRefreshWrite(
      "rt_0",
      readTokenSet(STORED),
      merged(REFRESHED_A),
    );

    assert.equal(outcome.action, "store");
  });

  it("carries the account identity into whichever set it returns", () => {
    const stored = resolveRefreshWrite(
      "rt_0",
      readTokenSet(STORED),
      merged(REFRESHED_A),
    );
    const kept = resolveRefreshWrite(
      "rt_0",
      readTokenSet({...STORED, refreshToken: "rt_a"}),
      merged(REFRESHED_A),
    );

    for (const outcome of [stored, kept]) {
      assert.equal(outcome.tokens.spotifyAccountId, "account_immutable");
      assert.deepEqual(outcome.tokens.indexKeys, [
        "spotify_user",
        "account_immutable",
      ]);
    }
  });
});

describe("two concurrent refreshes settle on one live token pair", () => {
  it("leaves the winner's pair on file and hands it to the loser", () => {
    // Interleaving, both starting from rt_0:
    //   A refreshes -> rt_a, A commits first
    //   B refreshes -> rt_b, B commits second and must not win
    const document = {value: {...STORED}};

    const commit = (sent, refreshed) => {
      const outcome = resolveRefreshWrite(
        sent,
        document.value ? readTokenSet(document.value) : null,
        mergeRefreshedTokens(readTokenSet(STORED), refreshed),
      );
      if (outcome.action === "store") {
        document.value = {
          ...document.value,
          accessToken: outcome.tokens.accessToken,
          refreshToken: outcome.tokens.refreshToken,
          expiresAt: outcome.tokens.expiresAt,
        };
      }
      return outcome;
    };

    const a = commit("rt_0", REFRESHED_A);
    const b = commit("rt_0", {
      accessToken: "at_b",
      refreshToken: "rt_b",
      expiresAt: 1_800_000_900_000,
    });

    assert.equal(a.action, "store");
    assert.equal(b.action, "keep-stored");
    assert.equal(document.value.refreshToken, "rt_a");
    assert.equal(document.value.accessToken, "at_a");
    // Both callers walk away with the same live pair.
    assert.equal(a.tokens.accessToken, "at_a");
    assert.equal(b.tokens.accessToken, "at_a");
  });

  it("does not recreate the document when a disconnect wins the race", () => {
    const document = {value: null};

    const outcome = resolveRefreshWrite(
      "rt_0",
      document.value,
      mergeRefreshedTokens(readTokenSet(STORED), REFRESHED_A),
    );

    assert.equal(outcome.action, "abandon");
    assert.equal(document.value, null);
  });
});
