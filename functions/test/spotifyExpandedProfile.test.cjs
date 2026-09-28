const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  FOLLOWED_ARTIST_LIMIT,
  hasFollowScope,
  PROFILE_TOP_LIMIT,
  summarizeArtists,
  toClientProfile,
} = require("../lib/spotifyMusic.js");
const {
  buildPublicMusicProfile,
  selectableArtists,
  toPublicMusicCard,
} = require("../lib/spotifyMusicProfile.js");

const artist = (id, name) => ({id, name, genres: ["indie"]});

describe("reading the artists a member follows needs its own permission", () => {
  it("recognises the granted scope", () => {
    assert.equal(
      hasFollowScope("user-top-read user-follow-read playlist-read-private"),
      true,
    );
  });

  it("treats a connection made before we asked as simply not granted", () => {
    assert.equal(
      hasFollowScope("user-top-read user-read-recently-played"),
      false,
    );
    assert.equal(hasFollowScope(undefined), false);
    assert.equal(hasFollowScope(""), false);
  });
});

describe("the Music Profile's four collections", () => {
  const summary = {
    spotifyConnected: true,
    topArtists: Array.from({length: 20}, (_, i) => artist(`a${i}`, `A${i}`)),
    topTracks: Array.from({length: 20}, (_, i) => ({
      id: `t${i}`,
      name: `T${i}`,
    })),
    followedArtists: Array.from({length: FOLLOWED_ARTIST_LIMIT}, (_, i) =>
      artist(`f${i}`, `F${i}`),
    ),
    playlists: Array.from({length: 10}, (_, i) => ({
      id: `p${i}`,
      name: `P${i}`,
      trackCount: i,
    })),
    profileTopArtists: Array.from({length: PROFILE_TOP_LIMIT}, (_, i) =>
      artist(`a${i}`, `A${i}`),
    ),
    profileTopTracks: Array.from({length: PROFILE_TOP_LIMIT}, (_, i) => ({
      id: `t${i}`,
      name: `T${i}`,
    })),
  };
  const client = toClientProfile(summary);

  it("shows five top artists and five top tracks", () => {
    assert.equal(client.profileTopArtists.length, PROFILE_TOP_LIMIT);
    assert.equal(client.profileTopTracks.length, PROFILE_TOP_LIMIT);
  });

  it("keeps the fuller lists behind them", () => {
    // The selection pool and the compatibility engine both read these; capping
    // them to satisfy a display limit would cost matching accuracy.
    assert.equal(client.topArtists.length, 20);
    assert.equal(client.topTracks.length, 20);
  });

  it("shows ten followed artists and ten playlists", () => {
    assert.equal(client.followedArtists.length, FOLLOWED_ARTIST_LIMIT);
    assert.equal(client.playlists.length, 10);
  });

  it("derives the short lists for a connection stored before they existed", () => {
    const older = toClientProfile({
      spotifyConnected: true,
      topArtists: summary.topArtists,
      topTracks: summary.topTracks,
    });
    assert.equal(older.profileTopArtists.length, PROFILE_TOP_LIMIT);
    assert.equal(older.profileTopTracks.length, PROFILE_TOP_LIMIT);
    assert.deepEqual(older.followedArtists, []);
    assert.equal(older.followScopeGranted, false);
  });

  it("reports whether follows could be read", () => {
    assert.equal(
      toClientProfile({...summary, followScopeGranted: true}).followScopeGranted,
      true,
    );
    assert.equal(client.followScopeGranted, false);
  });
});

describe("normalising what Spotify returned", () => {
  it("keeps at most ten followed artists", () => {
    const many = Array.from({length: 25}, (_, i) => ({
      id: `f${i}`,
      name: `F${i}`,
    }));
    assert.equal(
      summarizeArtists(many, FOLLOWED_ARTIST_LIMIT).length,
      FOLLOWED_ARTIST_LIMIT,
    );
  });

  it("accepts fewer than ten, and none at all", () => {
    assert.equal(summarizeArtists([artist("f0", "F0")], 10).length, 1);
    assert.deepEqual(summarizeArtists([], 10), []);
  });

  it("drops entries with no id", () => {
    const out = summarizeArtists([{name: "No id"}, artist("f1", "Real")], 10);
    assert.deepEqual(out.map((a) => a.name), ["Real"]);
  });
});

describe("a followed artist can be published", () => {
  const summary = {
    topArtists: [artist("a1", "Top One")],
    followedArtists: [artist("f1", "Followed One"), artist("a1", "Top One")],
    topTracks: [],
  };

  it("offers both lists as candidates", () => {
    const catalog = selectableArtists(summary);
    assert.ok(catalog.has("a1"), "a top artist stays selectable");
    assert.ok(catalog.has("f1"), "a followed artist becomes selectable");
  });

  it("does not offer the same artist twice", () => {
    assert.equal(selectableArtists(summary).size, 2);
  });

  it("publishes a followed artist with server-resolved metadata", () => {
    const built = buildPublicMusicProfile({
      enabled: true,
      artistIds: ["f1"],
      trackIds: [],
      summary,
    });
    assert.equal(built.artists[0].name, "Followed One");
    assert.ok(
      built.artists[0].spotifyUrl.startsWith(
        "https://open.spotify.com/artist/",
      ),
    );
  });

  it("still refuses an artist from neither list", () => {
    assert.throws(() =>
      buildPublicMusicProfile({
        enabled: true,
        artistIds: ["never-heard-of-them"],
        trackIds: [],
        summary,
      }),
    );
  });
});

describe("none of the new data reaches another member", () => {
  const card = toPublicMusicCard({
    enabled: true,
    artists: [{id: "a1", name: "Top One"}],
    tracks: [],
    genres: ["indie"],
    // A tampered stored document carrying things it should not.
    followedArtists: [{id: "f1", name: "Followed One"}],
    playlists: [{id: "p1", name: "Late night mix"}],
    recentlyPlayed: [{id: "r1", playedAt: "2026-09-28T10:00:00Z"}],
  });

  it("publishes only the card's own fields", () => {
    assert.deepEqual(Object.keys(card).sort(), [
      "artists",
      "enabled",
      "genres",
      "tracks",
    ]);
  });

  it("carries no followed artists, playlists or recent history", () => {
    const raw = JSON.stringify(card);
    for (const leak of ["Followed One", "Late night mix", "playedAt", "f1", "p1"]) {
      assert.ok(!raw.includes(leak), `leaked ${leak}`);
    }
  });
});
