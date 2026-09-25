const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  buildPublicMusicProfile,
  derivePublicGenres,
  emptyPublicMusicProfile,
  MAX_PUBLIC_ARTISTS,
  MAX_PUBLIC_GENRES,
  MAX_PUBLIC_TRACKS,
  normalizeSelectionIds,
  PublicMusicValidationError,
  reconcilePublicMusicProfile,
  selectableArtists,
  selectableTracks,
  toPublicMusicCard,
} = require("../lib/spotifyMusicProfile.js");
const {disconnectPlan} = require("../lib/spotifyMusic.js");

/** A realistic imported summary: rich, private, and the only trusted source. */
function summary(overrides = {}) {
  return {
    spotifyConnected: true,
    spotifyUserId: "spotify-user-1",
    topArtists: [
      {id: "a1", name: "Arctic Monkeys", image: "https://img/a1.jpg", genres: ["indie", "alternative"]},
      {id: "a2", name: "The Weeknd", image: "https://img/a2.jpg", genres: ["r&b", "alternative"]},
      {id: "a3", name: "Lana Del Rey", image: "https://img/a3.jpg", genres: ["indie"]},
      {id: "a4", name: "Radiohead", image: null, genres: ["alternative"]},
    ],
    topTracks: [
      {id: "t1", name: "505", artist: "Arctic Monkeys", image: "https://img/t1.jpg"},
      {id: "t2", name: "After Hours", artist: "The Weeknd", image: "https://img/t2.jpg"},
      {id: "t3", name: "Do I Wanna Know?", artist: "Arctic Monkeys", image: null},
      {id: "t4", name: "Creep", artist: "Radiohead", image: null},
    ],
    // Private signals. None of these may ever reach a public card.
    recentlyPlayed: [
      {id: "r1", name: "Secret Song", artist: "Someone", playedAt: "2026-09-22T03:14:00Z"},
    ],
    playlists: [{id: "p1", name: "3am thoughts (private)", trackCount: 40}],
    musicProfile: {
      genres: [{name: "alternative", percent: 40}, {name: "indie", percent: 35}],
      playlistTrackIds: ["pt1", "pt2"],
      recentTrackIds: ["r1"],
      musicFingerprint: {version: 2, trackIds: ["t1"], artistIds: ["a1"]},
    },
    ...overrides,
  };
}

describe("selection input normalization", () => {
  it("accepts an empty or absent selection", () => {
    assert.deepEqual(normalizeSelectionIds(undefined, 3, "artists"), []);
    assert.deepEqual(normalizeSelectionIds(null, 3, "artists"), []);
    assert.deepEqual(normalizeSelectionIds([], 3, "artists"), []);
  });

  it("accepts one, two and three items", () => {
    assert.equal(normalizeSelectionIds(["a1"], 3, "artists").length, 1);
    assert.equal(normalizeSelectionIds(["a1", "a2"], 3, "artists").length, 2);
    assert.equal(normalizeSelectionIds(["a1", "a2", "a3"], 3, "artists").length, 3);
  });

  it("rejects a fourth item", () => {
    assert.throws(
      () => normalizeSelectionIds(["a1", "a2", "a3", "a4"], 3, "artists"),
      (error) => error instanceof PublicMusicValidationError && error.reason === "artists-limit",
    );
  });

  it("collapses duplicates instead of spending the limit on them", () => {
    assert.deepEqual(
      normalizeSelectionIds(["a1", "a1", "a2", "a3"], 3, "artists"),
      ["a1", "a2", "a3"],
    );
  });

  it("rejects malformed identifiers", () => {
    for (const bad of [["" ], ["   "], [42], [{id: "a1"}], [null], "a1", 7]) {
      assert.throws(
        () => normalizeSelectionIds(bad, 3, "artists"),
        PublicMusicValidationError,
        `expected ${JSON.stringify(bad)} to be rejected`,
      );
    }
  });
});

describe("selectable library", () => {
  it("offers top artists and top tracks", () => {
    assert.deepEqual([...selectableArtists(summary()).keys()], ["a1", "a2", "a3", "a4"]);
    assert.deepEqual([...selectableTracks(summary()).keys()], ["t1", "t2", "t3", "t4"]);
  });

  it("never offers recently played as publishable", () => {
    // Recently played is listening activity, not a chosen favourite. Publishing
    // from it would leak what somebody happened to play.
    assert.equal(selectableTracks(summary()).has("r1"), false);
  });

  it("tolerates a summary with no imported data", () => {
    assert.equal(selectableArtists(undefined).size, 0);
    assert.equal(selectableTracks({}).size, 0);
    assert.equal(selectableArtists({topArtists: "nope"}).size, 0);
  });
});

describe("building the public profile", () => {
  it("publishes three artists and three tracks with server-resolved metadata", () => {
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1", "a2", "a3"],
      trackIds: ["t1", "t2", "t3"],
      summary: summary(),
    });
    assert.equal(profile.enabled, true);
    assert.deepEqual(profile.artists.map((a) => a.name), [
      "Arctic Monkeys",
      "The Weeknd",
      "Lana Del Rey",
    ]);
    assert.deepEqual(profile.tracks.map((t) => t.name), [
      "505",
      "After Hours",
      "Do I Wanna Know?",
    ]);
    assert.equal(profile.artists[0].imageUrl, "https://img/a1.jpg");
    assert.equal(profile.tracks[0].artist, "Arctic Monkeys");
  });

  it("builds Spotify links from trusted ids, never from client input", () => {
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1"],
      trackIds: ["t1"],
      summary: summary(),
    });
    assert.equal(profile.artists[0].spotifyUrl, "https://open.spotify.com/artist/a1");
    assert.equal(profile.tracks[0].spotifyUrl, "https://open.spotify.com/track/t1");
  });

  it("rejects an artist the member never imported", () => {
    // The spoofing case: a client naming a popular artist it does not own.
    assert.throws(
      () =>
        buildPublicMusicProfile({
          enabled: true,
          artistIds: ["taylor-swift-real-spotify-id"],
          trackIds: [],
          summary: summary(),
        }),
      (error) => error.reason === "artist-not-in-library",
    );
  });

  it("rejects a track the member never imported", () => {
    assert.throws(
      () =>
        buildPublicMusicProfile({
          enabled: true,
          artistIds: [],
          trackIds: ["someone-elses-track"],
          summary: summary(),
        }),
      (error) => error.reason === "track-not-in-library",
    );
  });

  it("ignores client-supplied names, artwork and links entirely", () => {
    // buildPublicMusicProfile only ever receives ids; even if a caller sent a
    // decorated object, nothing but the id can survive into the result.
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1"],
      trackIds: [],
      summary: summary(),
    });
    assert.equal(profile.artists[0].name, "Arctic Monkeys");
    assert.notEqual(profile.artists[0].name, "HALIL HACKED SPOTIFY");
    assert.ok(profile.artists[0].spotifyUrl.startsWith("https://open.spotify.com/"));
    assert.ok(
      profile.artists[0].imageUrl === null ||
        profile.artists[0].imageUrl.startsWith("https://img/"),
    );
  });

  it("refuses to enable an empty card", () => {
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: [],
      trackIds: [],
      summary: summary(),
    });
    assert.equal(profile.enabled, false);
    assert.deepEqual(profile.genres, []);
  });

  it("keeps the selection but hides it when disabled", () => {
    const profile = buildPublicMusicProfile({
      enabled: false,
      artistIds: ["a1"],
      trackIds: ["t1"],
      summary: summary(),
    });
    assert.equal(profile.enabled, false);
    assert.equal(profile.artists.length, 1);
    assert.deepEqual(profile.genres, [], "no genre line while hidden");
  });

  it("works with a partial selection", () => {
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1"],
      trackIds: [],
      summary: summary(),
    });
    assert.equal(profile.enabled, true);
    assert.equal(profile.artists.length, 1);
    assert.equal(profile.tracks.length, 0);
  });
});

describe("public genres", () => {
  it("describes the artists actually on the card", () => {
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1", "a2"],
      trackIds: [],
      summary: summary(),
    });
    assert.ok(profile.genres.includes("alternative"));
    assert.ok(profile.genres.length <= MAX_PUBLIC_GENRES);
  });

  it("caps the public genre line", () => {
    const many = summary({
      topArtists: [
        {
          id: "a1",
          name: "Polyglot",
          genres: ["g1", "g2", "g3", "g4", "g5", "g6"],
        },
      ],
    });
    const profile = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["a1"],
      trackIds: [],
      summary: many,
    });
    assert.equal(profile.genres.length, MAX_PUBLIC_GENRES);
  });

  it("falls back to ranked summary genres when artists carry none", () => {
    const noGenres = summary({
      topArtists: [{id: "a1", name: "Mystery", genres: []}],
    });
    const genres = derivePublicGenres(
      [{id: "a1", name: "Mystery", imageUrl: null, spotifyUrl: ""}],
      selectableArtists(noGenres),
      noGenres,
    );
    assert.deepEqual(genres, ["alternative", "indie"]);
  });

  it("returns nothing when there is no genre data at all", () => {
    const bare = {topArtists: [{id: "a1", name: "X"}], topTracks: []};
    assert.deepEqual(
      derivePublicGenres(
        [{id: "a1", name: "X", imageUrl: null, spotifyUrl: ""}],
        selectableArtists(bare),
        bare,
      ),
      [],
    );
  });
});

describe("public card projection", () => {
  const stored = buildPublicMusicProfile({
    enabled: true,
    artistIds: ["a1", "a2", "a3"],
    trackIds: ["t1", "t2", "t3"],
    summary: summary(),
  });

  it("hides the card entirely when disabled", () => {
    assert.equal(toPublicMusicCard({...stored, enabled: false}), null);
    assert.equal(toPublicMusicCard(undefined), null);
    assert.equal(toPublicMusicCard(emptyPublicMusicProfile()), null);
  });

  it("hides the card when nothing is selected", () => {
    assert.equal(
      toPublicMusicCard({enabled: true, artists: [], tracks: [], genres: []}),
      null,
      "an empty Music Taste section must not render",
    );
  });

  it("exposes exactly the chosen artists, tracks and genres", () => {
    const card = toPublicMusicCard(stored);
    assert.equal(card.artists.length, 3);
    assert.equal(card.tracks.length, 3);
    assert.ok(card.genres.length <= MAX_PUBLIC_GENRES);
    assert.deepEqual(Object.keys(card).sort(), ["artists", "enabled", "genres", "tracks"]);
  });

  it("enforces the display limits even on a tampered stored document", () => {
    const card = toPublicMusicCard({
      enabled: true,
      artists: Array.from({length: 9}, (_, i) => ({id: `x${i}`, name: `X${i}`})),
      tracks: Array.from({length: 9}, (_, i) => ({id: `y${i}`, name: `Y${i}`})),
      genres: ["g1", "g2", "g3", "g4", "g5", "g6"],
    });
    assert.equal(card.artists.length, MAX_PUBLIC_ARTISTS);
    assert.equal(card.tracks.length, MAX_PUBLIC_TRACKS);
    assert.equal(card.genres.length, MAX_PUBLIC_GENRES);
  });

  it("leaks no private listening data", () => {
    // The whole point of the split: another member gets the six chosen items
    // and nothing else from the Spotify import.
    const card = toPublicMusicCard(stored);
    const serialized = JSON.stringify(card);
    for (const leak of [
      "accessToken",
      "refreshToken",
      "access_token",
      "refresh_token",
      "codeVerifier",
      "clientSecret",
      "playedAt",
      "recentlyPlayed",
      "recentTrackIds",
      "playlistTrackIds",
      "musicFingerprint",
      "3am thoughts",
      "Secret Song",
      "spotifyUserId",
    ]) {
      assert.equal(
        serialized.includes(leak),
        false,
        `public music card must not carry ${leak}`,
      );
    }
  });

  it("carries only fields the profile UI needs", () => {
    const card = toPublicMusicCard(stored);
    assert.deepEqual(Object.keys(card.artists[0]).sort(), [
      "id",
      "imageUrl",
      "name",
      "spotifyUrl",
    ]);
    assert.deepEqual(Object.keys(card.tracks[0]).sort(), [
      "artist",
      "id",
      "imageUrl",
      "name",
      "spotifyUrl",
    ]);
  });
});

describe("re-sync reconciliation", () => {
  const published = buildPublicMusicProfile({
    enabled: true,
    artistIds: ["a1", "a2"],
    trackIds: ["t1"],
    summary: summary(),
  });

  it("keeps the member's own choices when they are still imported", () => {
    // A published choice belongs to the member. A re-sync must not swap it for
    // this month's top three.
    const reconciled = reconcilePublicMusicProfile(published, summary());
    assert.deepEqual(reconciled.artists.map((a) => a.id), ["a1", "a2"]);
    assert.deepEqual(reconciled.tracks.map((t) => t.id), ["t1"]);
    assert.equal(reconciled.enabled, true);
  });

  it("refreshes stale names and artwork from the new import", () => {
    const renamed = summary({
      topArtists: [
        {id: "a1", name: "Arctic Monkeys (Remastered)", image: "https://img/new.jpg", genres: ["indie"]},
        {id: "a2", name: "The Weeknd", image: null, genres: ["r&b"]},
      ],
    });
    const reconciled = reconcilePublicMusicProfile(published, renamed);
    assert.equal(reconciled.artists[0].name, "Arctic Monkeys (Remastered)");
    assert.equal(reconciled.artists[0].imageUrl, "https://img/new.jpg");
  });

  it("drops a selection Spotify no longer returns", () => {
    const shrunk = summary({
      topArtists: [{id: "a2", name: "The Weeknd", genres: ["r&b"]}],
      topTracks: [],
    });
    const reconciled = reconcilePublicMusicProfile(published, shrunk);
    assert.deepEqual(reconciled.artists.map((a) => a.id), ["a2"]);
    assert.deepEqual(reconciled.tracks, []);
    assert.equal(reconciled.enabled, true, "one surviving artist still shows");
  });

  it("never promotes an unselected artist into the public card", () => {
    const reconciled = reconcilePublicMusicProfile(published, summary());
    assert.equal(
      reconciled.artists.some((a) => a.id === "a3" || a.id === "a4"),
      false,
      "sync must not publish artists the member did not choose",
    );
  });

  it("turns the card off when nothing survives", () => {
    const gone = summary({topArtists: [], topTracks: []});
    const reconciled = reconcilePublicMusicProfile(published, gone);
    assert.equal(reconciled.enabled, false);
    assert.equal(toPublicMusicCard(reconciled), null);
  });

  it("keeps a hidden card hidden across a sync", () => {
    const hidden = {...published, enabled: false};
    assert.equal(reconcilePublicMusicProfile(hidden, summary()).enabled, false);
  });

  it("handles a profile that never published anything", () => {
    assert.deepEqual(
      reconcilePublicMusicProfile(undefined, summary()),
      emptyPublicMusicProfile(),
    );
  });
});

describe("disconnect clears the public card", () => {
  it("resets publicMusic alongside the connection flag", () => {
    const plan = disconnectPlan("uid-a", "spotify-user-1");
    assert.equal(plan.profileData.spotifyConnected, false);
    assert.deepEqual(plan.profileData.publicMusic, emptyPublicMusicProfile());
    assert.equal(
      toPublicMusicCard(plan.profileData.publicMusic),
      null,
      "no Music Taste section may survive a disconnect",
    );
  });

  it("removes every index key the account was reachable under", () => {
    const plan = disconnectPlan("uid-a", "legacy-id", ["account-id", "legacy-id", null]);
    assert.deepEqual(plan.deletes, [
      "spotifySecrets/uid-a",
      "users/uid-a/music/summary",
      "musicSpotifyIndex/legacy-id",
      "musicSpotifyIndex/account-id",
    ]);
  });

  it("still works for an account with only a legacy id", () => {
    const plan = disconnectPlan("uid-a", "legacy-id");
    assert.deepEqual(plan.deletes, [
      "spotifySecrets/uid-a",
      "users/uid-a/music/summary",
      "musicSpotifyIndex/legacy-id",
    ]);
  });
});
