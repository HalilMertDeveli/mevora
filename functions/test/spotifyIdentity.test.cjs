const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  resolveIndexOwnership,
  resolveSpotifyIdentity,
} = require("../lib/spotifyIdentity.js");

/**
 * Spotify's May 2026 Web API change added `account_id` — "a public, immutable,
 * pseudoanonymous identifier" — and states that the older `id` "should not be
 * used for account linking". Mevora's live index documents are keyed by that
 * legacy id, so the resolution has to serve both at once.
 */
describe("Spotify account identity", () => {
  it("prefers the immutable account_id for new links", () => {
    const identity = resolveSpotifyIdentity({
      id: "legacy-user",
      account_id: "immutable-account",
    });
    assert.equal(identity.accountId, "immutable-account");
    assert.equal(identity.userId, "legacy-user");
    assert.equal(identity.primaryKey, "immutable-account");
  });

  it("looks the account up under both keys, newest first", () => {
    const identity = resolveSpotifyIdentity({
      id: "legacy-user",
      account_id: "immutable-account",
    });
    assert.deepEqual(identity.lookupKeys, ["immutable-account", "legacy-user"]);
  });

  it("falls back to the legacy id when Spotify sends no account_id", () => {
    // A token issued before the field existed, or an API that has not rolled it
    // out, must still link rather than fail.
    const identity = resolveSpotifyIdentity({id: "legacy-user"});
    assert.equal(identity.accountId, null);
    assert.equal(identity.primaryKey, "legacy-user");
    assert.deepEqual(identity.lookupKeys, ["legacy-user"]);
  });

  it("copes with an account_id but no legacy id", () => {
    const identity = resolveSpotifyIdentity({account_id: "immutable-account"});
    assert.equal(identity.userId, "immutable-account");
    assert.deepEqual(identity.lookupKeys, ["immutable-account"]);
  });

  it("does not duplicate a key when both fields agree", () => {
    const identity = resolveSpotifyIdentity({id: "same", account_id: "same"});
    assert.deepEqual(identity.lookupKeys, ["same"]);
  });

  it("rejects a profile with no usable identifier", () => {
    for (const bad of [null, undefined, {}, {id: ""}, {id: "   "}, {id: 42}]) {
      assert.equal(resolveSpotifyIdentity(bad), null, JSON.stringify(bad));
    }
  });

  it("trims whitespace rather than creating a separate key", () => {
    const identity = resolveSpotifyIdentity({id: "  legacy-user  "});
    assert.equal(identity.primaryKey, "legacy-user");
  });
});

describe("index ownership across both keys", () => {
  it("reports an unclaimed account", () => {
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: false},
      {key: "legacy-user", exists: false},
    ]);
    assert.equal(result.ownerUid, null);
    assert.deepEqual(result.missingKeys, ["immutable-account", "legacy-user"]);
  });

  it("recognises an account linked before account_id existed", () => {
    // The migration case: only the legacy document exists. The account is owned,
    // and the account_id key is reported so it can be backfilled.
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: false},
      {key: "legacy-user", exists: true, uid: "uid-a"},
    ]);
    assert.equal(result.ownerUid, "uid-a");
    assert.deepEqual(result.missingKeys, ["immutable-account"]);
  });

  it("recognises an account already migrated to account_id", () => {
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: true, uid: "uid-a"},
      {key: "legacy-user", exists: false},
    ]);
    assert.equal(result.ownerUid, "uid-a");
    assert.deepEqual(result.missingKeys, ["legacy-user"]);
  });

  it("needs no backfill once both documents exist", () => {
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: true, uid: "uid-a"},
      {key: "legacy-user", exists: true, uid: "uid-a"},
    ]);
    assert.equal(result.ownerUid, "uid-a");
    assert.deepEqual(result.missingKeys, []);
  });

  it("never orphans an existing link by preferring the newer key", () => {
    // If the account_id document is somehow absent but the legacy one names a
    // uid, that uid still owns the account.
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: false},
      {key: "legacy-user", exists: true, uid: "uid-legacy"},
    ]);
    assert.equal(result.ownerUid, "uid-legacy");
  });

  it("treats a claimed document with an unusable uid as claimed", () => {
    // Taking it over silently would move ownership of a linked Spotify account.
    const result = resolveIndexOwnership([
      {key: "immutable-account", exists: true},
      {key: "legacy-user", exists: false},
    ]);
    assert.equal(result.ownerUid, "");
    assert.notEqual(result.ownerUid, null, "must not look unclaimed");
  });
});
