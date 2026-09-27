const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {spotifyIndexDeletionPaths} = require("../lib/deleteAccount.js");

// Account deletion must leave nothing Spotify-shaped behind. Two failures are
// worth guarding separately:
//
//   1. a missed ownership-index key, which keeps a deleted member discoverable
//      and lets the next sign-in collide with them. That computation is real
//      logic, so it is exercised directly.
//   2. a deletion target quietly dropped from the callable's list. The callable
//      needs live Firestore, so its Spotify targets are asserted against the
//      source, the way test/security/production_compliance_test.dart does.

describe("Spotify ownership index erasure", () => {
  it("deletes the current login index key", () => {
    assert.deepEqual(spotifyIndexDeletionPaths({spotifyId: "spot_a"}), [
      "spotifyIndex/spot_a",
    ]);
  });

  it("also deletes legacy login keys the account was reachable under", () => {
    // Spotify's May 2026 move to account_id means an older member can hold a
    // previous key. Deleting only the current one leaves the old one dangling.
    const paths = spotifyIndexDeletionPaths({
      spotifyId: "account_new",
      spotifyIndexKeys: ["profile_old", "profile_older"],
    });

    assert.deepEqual(paths, [
      "spotifyIndex/account_new",
      "spotifyIndex/profile_old",
      "spotifyIndex/profile_older",
    ]);
  });

  it("collapses a key that is both the current and a legacy key", () => {
    const paths = spotifyIndexDeletionPaths({
      spotifyId: "same",
      spotifyIndexKeys: ["same"],
    });

    assert.deepEqual(paths, ["spotifyIndex/same"]);
  });

  it("deletes both music index keys, which are different fields", () => {
    // spotifyUserId and spotifyAccountId are written independently; covering
    // only one of them leaves the music account reachable.
    const paths = spotifyIndexDeletionPaths({
      musicSpotifyId: "music_user",
      musicSpotifyAccountId: "music_account",
    });

    assert.deepEqual(paths, [
      "musicSpotifyIndex/music_user",
      "musicSpotifyIndex/music_account",
    ]);
  });

  it("covers login and music indexes together", () => {
    const paths = spotifyIndexDeletionPaths({
      spotifyId: "login",
      spotifyIndexKeys: ["legacy"],
      musicSpotifyId: "music_user",
      musicSpotifyAccountId: "music_account",
    });

    assert.deepEqual(paths, [
      "spotifyIndex/login",
      "spotifyIndex/legacy",
      "musicSpotifyIndex/music_user",
      "musicSpotifyIndex/music_account",
    ]);
  });

  it("returns nothing for a member who never connected Spotify", () => {
    assert.deepEqual(spotifyIndexDeletionPaths({}), []);
    assert.deepEqual(spotifyIndexDeletionPaths({spotifyIndexKeys: []}), []);
  });

  it("ignores blank and whitespace-only keys", () => {
    // `spotifyIndex/` with an empty key is not a document path Firestore will
    // accept; a blank field must not turn into a delete call at all.
    const paths = spotifyIndexDeletionPaths({
      spotifyId: "",
      spotifyIndexKeys: ["   ", "real"],
      musicSpotifyId: undefined,
      musicSpotifyAccountId: "  ",
    });

    assert.deepEqual(paths, ["spotifyIndex/real"]);
  });

  it("trims a key rather than building a path around the padding", () => {
    assert.deepEqual(spotifyIndexDeletionPaths({spotifyId: " padded "}), [
      "spotifyIndex/padded",
    ]);
  });
});

describe("Spotify deletion targets in deleteUserAccount", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "src", "deleteAccount.ts"),
    "utf8",
  );

  it("deletes the server-side Spotify token store", () => {
    // The tokens are the one artifact that stays useful to an attacker after
    // the account is gone.
    assert.match(source, /db\.doc\(`spotifySecrets\/\$\{uid\}`\)/);
  });

  it("deletes the imported private music summary", () => {
    assert.match(source, /db\.doc\(`users\/\$\{uid\}\/music\/summary`\)/);
  });

  it("deletes the whole music subcollection, not just the summary", () => {
    assert.match(source, /deleteCollectionDocs\(`users\/\$\{uid\}\/music`\)/);
  });

  it("deletes the profile document that carries the public music card", () => {
    // publicMusic lives on profiles/{uid}; deleting the document is what stops
    // another member seeing a deleted member's Music Taste.
    assert.match(source, /db\.doc\(`profiles\/\$\{uid\}`\)/);
  });

  it("walks the computed index paths instead of an inline key list", () => {
    assert.match(source, /for \(const path of spotifyIndexDeletionPaths\(\{/);
  });
});
