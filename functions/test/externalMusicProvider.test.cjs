const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildExternalNormalizedProfile,
  extractExternalRecentArtists,
} = require("../lib/music/normalize/normalizeExternalMusicProfile.js");
const {
  buildSpotifyNormalizedProfile,
  normalizedToSummaryFields,
  tasteFromSummaryDocument,
} = require("../lib/music/normalize/normalizeMusicProfile.js");
const {ExternalMusicProvider} = require("../lib/music/providers/externalMusicProvider.js");
const {
  resolveMusicProvider,
  defaultMusicProviderId,
} = require("../lib/music/providers/musicProviderRegistry.js");
const {SpotifyMusicProvider} = require("../lib/music/providers/spotifyMusicProvider.js");
const {
  isExternalMusicApiConfigured,
  EXTERNAL_PROVIDER_ID,
} = require("../lib/music/externalMusicConfig.js");
const {scoreMusicCompatibility} = require("../lib/musicCompatibility.js");

const originalEnv = {...process.env};

function clearExternalEnv() {
  delete process.env.EXTERNAL_MUSIC_API_KEY;
  delete process.env.EXTERNAL_MUSIC_API_SECRET;
  delete process.env.EXTERNAL_MUSIC_API_BASE_URL;
}

function restoreEnv() {
  process.env = {...originalEnv};
}

function fullExternalPayload(overrides = {}) {
  return {
    userId: "ext-user-1",
    displayName: "External User",
    topTracks: [
      {id: "t1", name: "Track One", artist: "Artist A"},
      {id: "t2", name: "Track Two", artist: "Artist B"},
    ],
    topArtists: [
      {id: "a1", name: "Artist A", genres: ["R&B"]},
      {id: "a2", name: "Artist B", genres: ["Pop"]},
    ],
    recentPlays: [
      {
        trackId: "rt1",
        trackName: "Recent 1",
        artistId: "ra1",
        artistName: "Recent Artist 1",
        playedAt: "2026-08-28T10:00:00Z",
      },
      {
        trackId: "rt2",
        trackName: "Recent 2",
        artistId: "ra2",
        artistName: "Recent Artist 2",
        playedAt: "2026-08-28T09:00:00Z",
      },
    ],
    genres: [
      {name: "R&B", percent: 40},
      {name: "Pop", percent: 35},
      {name: "Hip-Hop", percent: 25},
    ],
    playlistTrackIds: ["p1", "p2"],
    playlists: [{id: "pl1", name: "Favorites", trackCount: 42}],
    ...overrides,
  };
}

test("external provider normalized profile contract", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload());
  assert.equal(normalized.provider, EXTERNAL_PROVIDER_ID);
  assert.equal(normalized.connected, true);
  assert.equal(normalized.providerUserId, "ext-user-1");
  assert.equal(normalized.displayName, "External User");
  assert.deepEqual(normalized.trackIds, ["t1", "t2"]);
  assert.deepEqual(normalized.artistIds, ["a1", "a2"]);
  assert.equal(normalized.recentArtists.length, 2);
  assert.equal(normalized.topGenres.length, 3);
  assert.deepEqual(normalized.playlistTrackIds, ["p1", "p2"]);
  assert.equal(normalized.playlists.length, 1);
});

test("external provider recent artists capped at 5 unique chronological", () => {
  const plays = [];
  for (let i = 0; i < 7; i += 1) {
    plays.push({
      trackId: `t${i}`,
      trackName: `Track ${i}`,
      artistId: `a${i}`,
      artistName: `Artist ${i}`,
      playedAt: `2026-08-28T0${i}:00:00Z`,
    });
  }
  plays.push({
    trackId: "dup",
    trackName: "Dup",
    artistId: "a0",
    artistName: "Artist 0",
    playedAt: "2026-08-28T08:00:00Z",
  });
  const recentArtists = extractExternalRecentArtists(plays);
  assert.equal(recentArtists.length, 5);
  assert.deepEqual(
    recentArtists.map((artist) => artist.id),
    ["a0", "a1", "a2", "a3", "a4"],
  );
});

test("external provider genres from explicit API payload", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload());
  assert.ok(normalized.topGenres.some((item) => item.name === "R&B"));
  assert.ok(normalized.topGenres.some((item) => item.name === "Pop"));
  assert.ok(normalized.topGenres.some((item) => item.name === "Hip-Hop"));
});

test("external provider missing genres yields empty topGenres", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload({
    genres: undefined,
    topArtists: [
      {id: "a1", name: "Artist A"},
      {id: "a2", name: "Artist B"},
    ],
  }));
  assert.deepEqual(normalized.topGenres, []);
});

test("external provider missing recent artists yields empty recentArtists", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload({
    recentPlays: undefined,
  }));
  assert.deepEqual(normalized.recentArtists, []);
  assert.deepEqual(normalized.recentArtistIds, []);
  assert.deepEqual(normalized.recentTrackIds, []);
});

test("provider field correctly set to external", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload());
  assert.equal(normalized.provider, "external");
  const summary = normalizedToSummaryFields(normalized);
  assert.equal(summary.provider, "external");
  assert.equal(summary.connected, true);
  assert.equal(summary.spotifyConnected, false);
});

test("external API unavailable does not produce fake compatibility score", () => {
  clearExternalEnv();
  assert.equal(isExternalMusicApiConfigured(), false);
  const provider = new ExternalMusicProvider();
  assert.rejects(
    () => provider.fetchTaste({accessToken: "token"}),
    (error) => error.code === "failed-precondition" && error.message === "external-api-not-configured",
  );

  const disconnectedTaste = tasteFromSummaryDocument({
    provider: "external",
    connected: false,
    spotifyConnected: false,
    musicProfile: {trackIds: ["t1"], artistIds: ["a1"], genreNames: ["pop"]},
  });
  assert.equal(disconnectedTaste, null);

  const scored = scoreMusicCompatibility(
    {trackIds: [], artistIds: [], genres: [], recentTrackIds: [], recentArtistIds: [], playlistTrackIds: []},
    {trackIds: ["t1"], artistIds: ["a1"], genres: ["pop"], recentTrackIds: [], recentArtistIds: [], playlistTrackIds: []},
  );
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
  restoreEnv();
});

test("existing Spotify provider regression via registry", () => {
  assert.equal(defaultMusicProviderId(), "spotify");
  const spotifyGet = async () => ({items: []});
  const provider = resolveMusicProvider("spotify", {spotifyGet});
  assert.ok(provider instanceof SpotifyMusicProvider);
  assert.equal(provider.providerId, "spotify");

  const normalized = buildSpotifyNormalizedProfile({
    providerUserId: "spotify-user",
    displayName: "Spotify User",
    topTracksRaw: [{id: "st1", name: "Song", artists: [{id: "sa1", name: "Artist"}]}],
    topArtistsRaw: [{id: "sa1", name: "Artist", genres: ["pop"], images: []}],
    recentlyPlayedRaw: [],
    playlistTrackIds: [],
    playlists: [],
  });
  assert.equal(normalized.provider, "spotify");
  const summary = normalizedToSummaryFields(normalized);
  assert.equal(summary.spotifyConnected, true);
  assert.equal(summary.connected, true);
});

test("existing music compatibility regression unchanged for shared taste", () => {
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

test("external summaries work with match taste extraction path", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload());
  const summary = normalizedToSummaryFields(normalized);
  const viewerTaste = tasteFromSummaryDocument(summary);
  const peerTaste = tasteFromSummaryDocument({
    ...summary,
    musicProfile: {
      ...summary.musicProfile,
      trackIds: ["t1", "t3"],
      artistIds: ["a1", "a3"],
      genreNames: ["R&B", "Rock"],
    },
  });
  assert.ok(viewerTaste);
  assert.ok(peerTaste);
  const scored = scoreMusicCompatibility(viewerTaste, peerTaste);
  assert.ok(scored.score > 0);
  assert.ok(scored.score < 100);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("no token or secret exposed in normalized profile or summary", () => {
  const normalized = buildExternalNormalizedProfile(fullExternalPayload());
  const serialized = JSON.stringify({
    normalized,
    summary: normalizedToSummaryFields(normalized),
  }).toLowerCase();
  for (const forbidden of [
    "accesstoken",
    "refreshtoken",
    "api_key",
    "apikey",
    "api_secret",
    "apisecret",
    "external_music_api",
  ]) {
    assert.equal(serialized.includes(forbidden), false, `found forbidden key fragment: ${forbidden}`);
  }
});

test("provider registry rejects external when API not configured", () => {
  clearExternalEnv();
  assert.throws(
    () => resolveMusicProvider("external"),
    (error) => error.code === "failed-precondition" && error.message === "external-api-not-configured",
  );
  restoreEnv();
});

test("provider registry resolves external when API configured", () => {
  process.env.EXTERNAL_MUSIC_API_KEY = "key";
  process.env.EXTERNAL_MUSIC_API_SECRET = "secret";
  process.env.EXTERNAL_MUSIC_API_BASE_URL = "https://example.com";
  const provider = resolveMusicProvider("external");
  assert.ok(provider instanceof ExternalMusicProvider);
  assert.equal(provider.providerId, "external");
  restoreEnv();
});

test("external config is not configured without secrets", () => {
  clearExternalEnv();
  assert.equal(isExternalMusicApiConfigured(), false);
  restoreEnv();
});
