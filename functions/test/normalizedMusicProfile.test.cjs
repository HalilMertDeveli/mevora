const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildSpotifyNormalizedProfile,
  extractRecentArtists,
  extractRecentArtistIds,
  genreShares,
  summarizeArtists,
  tasteFromSummaryDocument,
} = require("../lib/music/normalize/normalizeMusicProfile.js");
const {scoreMusicCompatibility, MUSIC_PROFILE_VERSION} = require("../lib/musicCompatibility.js");

function recentlyPlayedItems(artistRows) {
  return artistRows.map((artists, index) => ({
    played_at: `2026-08-28T10:0${index}:00Z`,
    track: {
      id: `track-${index + 1}`,
      name: `Track ${index + 1}`,
      artists: artists.map((artist) => ({
        id: artist.id,
        name: artist.name,
        images: artist.image ? [{url: artist.image}] : [],
      })),
      album: {images: []},
    },
  }));
}

test("Spotify raw data maps to normalized profile", () => {
  const recentRaw = recentlyPlayedItems([
    [{id: "a-weeknd", name: "The Weeknd"}],
    [{id: "a-drake", name: "Drake"}],
  ]);
  const normalized = buildSpotifyNormalizedProfile({
    providerUserId: "spotify-user-1",
    displayName: "Listener",
    topTracksRaw: [{id: "t1", name: "Song", artists: [{name: "The Weeknd"}], album: {images: []}}],
    topArtistsRaw: [{
      id: "a-weeknd",
      name: "The Weeknd",
      genres: ["r&b", "pop"],
      images: [],
    }],
    recentlyPlayedRaw: recentRaw,
    playlistTrackIds: [],
    playlists: [],
  });

  assert.equal(normalized.provider, "spotify");
  assert.equal(normalized.connected, true);
  assert.equal(normalized.providerUserId, "spotify-user-1");
  assert.ok(normalized.trackIds.includes("t1"));
  assert.ok(normalized.artistIds.includes("a-weeknd"));
  assert.equal(normalized.recentTrackIds.length, 2);
  assert.equal(normalized.recentArtists.length, 2);
  assert.ok(normalized.topGenres.length > 0);
});

test("recent artists duplicate removal preserves chronological order", () => {
  const items = recentlyPlayedItems([
    [{id: "a-weeknd", name: "The Weeknd"}],
    [{id: "a-drake", name: "Drake"}],
    [{id: "a-weeknd", name: "The Weeknd"}],
    [{id: "a-sza", name: "SZA"}],
    [{id: "a-rihanna", name: "Rihanna"}],
    [{id: "a-drake", name: "Drake"}],
  ]);
  const recentArtists = extractRecentArtists(items);
  assert.deepEqual(
    recentArtists.map((artist) => artist.name),
    ["The Weeknd", "Drake", "SZA", "Rihanna"],
  );
});

test("recent artists capped at 5", () => {
  const items = recentlyPlayedItems([
    [{id: "a1", name: "A1"}],
    [{id: "a2", name: "A2"}],
    [{id: "a3", name: "A3"}],
    [{id: "a4", name: "A4"}],
    [{id: "a5", name: "A5"}],
    [{id: "a6", name: "A6"}],
    [{id: "a7", name: "A7"}],
  ]);
  const recentArtists = extractRecentArtists(items);
  assert.equal(recentArtists.length, 5);
  assert.deepEqual(recentArtists.map((artist) => artist.id), ["a1", "a2", "a3", "a4", "a5"]);
});

test("genre normalization from top artists", () => {
  const genres = genreShares(summarizeArtists([
    {id: "a1", name: "Artist 1", genres: ["R&B", "Pop"]},
    {id: "a2", name: "Artist 2", genres: ["Pop", "Hip-Hop"]},
  ]));
  assert.ok(genres.some((item) => item.name === "pop"));
  assert.ok(genres.every((item) => item.percent > 0));
});

test("provider is spotify in normalized profile", () => {
  const normalized = buildSpotifyNormalizedProfile({
    providerUserId: "uid",
    displayName: null,
    topTracksRaw: [],
    topArtistsRaw: [{id: "a1", name: "A", genres: ["pop"], images: []}],
    recentlyPlayedRaw: [],
    playlistTrackIds: [],
    playlists: [],
  });
  assert.equal(normalized.provider, "spotify");
});

test("v2 summary backward compatibility for taste extraction", () => {
  const taste = tasteFromSummaryDocument({
    spotifyConnected: true,
    musicProfileVersion: 2,
    musicProfile: {
      trackIds: ["t1"],
      artistIds: ["a1"],
      genreNames: ["pop"],
      recentTrackIds: ["t1"],
      recentArtistIds: ["a1"],
      playlistTrackIds: [],
    },
  });
  assert.ok(taste);
  assert.deepEqual(taste.trackIds, ["t1"]);
  assert.deepEqual(taste.genres, ["pop"]);
});

test("disconnected summary returns null taste", () => {
  assert.equal(tasteFromSummaryDocument({spotifyConnected: false}), null);
  assert.equal(tasteFromSummaryDocument(undefined), null);
});

test("recentArtistIds behavior unchanged (up to 30)", () => {
  const items = recentlyPlayedItems([
    [{id: "a-weeknd", name: "The Weeknd"}],
    [{id: "a-drake", name: "Drake"}],
    [{id: "a-weeknd", name: "The Weeknd"}],
  ]);
  const ids = extractRecentArtistIds(items);
  assert.deepEqual(ids, ["a-weeknd", "a-drake"]);
});

test("existing music compatibility score unchanged for same taste", () => {
  const taste = {
    trackIds: ["t1", "t2"],
    artistIds: ["a1"],
    genres: ["pop"],
    recentTrackIds: ["t1"],
    recentArtistIds: ["a1"],
    playlistTrackIds: [],
  };
  const result = scoreMusicCompatibility(taste, {...taste});
  assert.equal(result.score, 100);
});

test("music profile version is 3", () => {
  assert.equal(MUSIC_PROFILE_VERSION, 3);
});
