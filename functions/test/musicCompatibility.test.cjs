const test = require("node:test");
const assert = require("node:assert/strict");
const {
  scoreMusicCompatibility,
  enrichMusicCompatibility,
  musicRankingBonus,
  MUSIC_PROFILE_VERSION,
} = require("../lib/musicCompatibility.js");

function taste(partial = {}) {
  return {
    trackIds: [],
    artistIds: [],
    genres: [],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
    ...partial,
  };
}

test("empty taste scores 0", () => {
  const result = scoreMusicCompatibility(
    taste(),
    taste({trackIds: ["a"], artistIds: ["b"], genres: ["pop"]}),
  );
  assert.equal(result.score, 0);
  assert.equal(result.insights[0].code, "data_unavailable");
});

test("identical taste scores 100 and is deterministic", () => {
  const shared = taste({
    trackIds: ["t1", "t2", "t3"],
    artistIds: ["a1", "a2"],
    genres: ["jazz", "indie"],
    recentTrackIds: ["t1"],
    recentArtistIds: ["a1"],
  });
  const a = scoreMusicCompatibility(shared, shared);
  const b = scoreMusicCompatibility(shared, shared);
  assert.equal(a.score, 100);
  assert.equal(a.score, b.score);
  assert.deepEqual(a.sharedTracks, ["t1", "t2", "t3"]);
  assert.equal(a.sharedArtists.length, 2);
});

test("playlist overlap adjusts weights when both have playlists", () => {
  const viewer = taste({
    trackIds: ["t1"],
    artistIds: ["a1"],
    genres: ["pop"],
    playlistTrackIds: ["p1", "p2", "p3", "p4"],
  });
  const candidate = taste({
    trackIds: ["t1"],
    artistIds: ["a1"],
    genres: ["pop"],
    playlistTrackIds: ["p1", "p2", "x", "y"],
  });
  const result = scoreMusicCompatibility(viewer, candidate);
  assert.equal(result.sharedPlaylistTracks.length, 2);
  assert.ok(result.breakdown.playlist > 0);
  assert.ok(result.insights.some((item) => item.code === "shared_playlist_tracks"));
});

test("enrich resolves display names without inventing play counts", () => {
  const scored = scoreMusicCompatibility(
    taste({trackIds: ["t1"], artistIds: ["a1"], genres: ["r&b"]}),
    taste({trackIds: ["t1"], artistIds: ["a1"], genres: ["r&b"]}),
  );
  const enriched = enrichMusicCompatibility(scored, [
    {id: "t1", name: "Blinding Lights"},
    {id: "a1", name: "The Weeknd"},
  ]);
  assert.deepEqual(enriched.sharedTrackNames, ["Blinding Lights"]);
  assert.deepEqual(enriched.sharedArtistNames, ["The Weeknd"]);
  assert.ok(
    enriched.insights.some(
      (item) => item.code === "top_shared_artist" && item.params?.name === "The Weeknd",
    ),
  );
});

test("ranking bonus stays a soft signal", () => {
  assert.equal(musicRankingBonus(0), 0);
  assert.equal(musicRankingBonus(100), 15);
  assert.equal(MUSIC_PROFILE_VERSION, 3);
});
