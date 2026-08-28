const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildExternalNormalizedProfile,
} = require("../lib/music/normalize/normalizeExternalMusicProfile.js");
const {
  buildSpotifyNormalizedProfile,
  extractRecentArtists,
  normalizedToSummaryFields,
  tasteFromSummaryDocument,
} = require("../lib/music/normalize/normalizeMusicProfile.js");
const {
  resolveMusicProvider,
  resolveProviderIdFromSummary,
  isKnownMusicProviderId,
  isExternalProviderProductionReady,
  defaultMusicProviderId,
} = require("../lib/music/providers/musicProviderRegistry.js");
const {EXTERNAL_PROVIDER_ID} = require("../lib/music/externalMusicConfig.js");
const {scoreMusicCompatibility} = require("../lib/musicCompatibility.js");

const originalEnv = {...process.env};

function restoreEnv() {
  process.env = {...originalEnv};
}

function clearExternalEnv() {
  delete process.env.EXTERNAL_MUSIC_API_KEY;
  delete process.env.EXTERNAL_MUSIC_API_SECRET;
  delete process.env.EXTERNAL_MUSIC_API_BASE_URL;
}

function configureExternalEnv() {
  process.env.EXTERNAL_MUSIC_API_KEY = "test-key";
  process.env.EXTERNAL_MUSIC_API_SECRET = "test-secret";
  process.env.EXTERNAL_MUSIC_API_BASE_URL = "https://example.test";
}

function spotifyNormalized(overrides = {}) {
  return buildSpotifyNormalizedProfile({
    providerUserId: "sp-1",
    displayName: "Spotify User",
    topTracksRaw: [
      {id: "t1", name: "Track One", artists: [{id: "a1", name: "Artist A"}]},
      {id: "t2", name: "Track Two", artists: [{id: "a2", name: "Artist B"}]},
    ],
    topArtistsRaw: [
      {id: "a1", name: "Artist A", genres: ["pop"], images: []},
      {id: "a2", name: "Artist B", genres: ["rock"], images: []},
    ],
    recentlyPlayedRaw: [],
    playlistTrackIds: [],
    playlists: [],
    ...overrides,
  });
}

function externalNormalized(overrides = {}) {
  return buildExternalNormalizedProfile({
    userId: "ext-1",
    displayName: "External User",
    topTracks: [
      {id: "t1", name: "Track One", artist: "Artist A"},
      {id: "t3", name: "Track Three", artist: "Artist C"},
    ],
    topArtists: [
      {id: "a1", name: "Artist A", genres: ["pop"]},
      {id: "a3", name: "Artist C", genres: ["indie"]},
    ],
    genres: [
      {name: "pop", percent: 60},
      {name: "indie", percent: 40},
    ],
    recentPlays: [],
    playlistTrackIds: [],
    playlists: [],
    ...overrides,
  });
}

function tasteFromNormalized(normalized) {
  return tasteFromSummaryDocument(normalizedToSummaryFields(normalized));
}

function emptyTaste() {
  return {
    trackIds: [],
    artistIds: [],
    genres: [],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
}

test("1. Spotify + Spotify compatibility uses normalized taste only", () => {
  const left = tasteFromNormalized(spotifyNormalized());
  const right = tasteFromNormalized(spotifyNormalized({providerUserId: "sp-2"}));
  const scored = scoreMusicCompatibility(left, right);
  assert.ok(scored.score >= 80);
  assert.deepEqual(scored.sharedTracks.sort(), ["t1", "t2"]);
  assert.deepEqual(scored.sharedArtists.sort(), ["a1", "a2"]);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("2. Spotify + External normalized profile compatibility", () => {
  const spotify = tasteFromNormalized(spotifyNormalized());
  const external = tasteFromNormalized(externalNormalized());
  const scored = scoreMusicCompatibility(spotify, external);
  assert.ok(scored.score > 0);
  assert.ok(scored.score < 100);
  assert.ok(scored.sharedTracks.includes("t1"));
  assert.ok(scored.sharedArtists.includes("a1"));
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("3. External + Spotify normalized profile is symmetric", () => {
  const external = tasteFromNormalized(externalNormalized());
  const spotify = tasteFromNormalized(spotifyNormalized());
  const forward = scoreMusicCompatibility(external, spotify);
  const reverse = scoreMusicCompatibility(spotify, external);
  assert.equal(forward.score, reverse.score);
  assert.deepEqual(forward.sharedTracks, reverse.sharedTracks);
});

test("4. External + External normalized profile compatibility", () => {
  const left = tasteFromNormalized(externalNormalized());
  const right = tasteFromNormalized(externalNormalized({userId: "ext-2", displayName: "Peer"}));
  const scored = scoreMusicCompatibility(left, right);
  assert.ok(scored.score >= 80);
  assert.deepEqual(scored.sharedTracks.sort(), ["t1", "t3"]);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("5. Spotify + no music yields data_unavailable not a fake score", () => {
  const spotify = tasteFromNormalized(spotifyNormalized());
  const noMusic = tasteFromSummaryDocument({
    provider: "spotify",
    connected: false,
    spotifyConnected: false,
    musicProfile: {},
  });
  assert.equal(noMusic, null);
  const scored = scoreMusicCompatibility(spotify, emptyTaste());
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("6. External + no music yields data_unavailable", () => {
  const external = tasteFromNormalized(externalNormalized());
  const noMusic = tasteFromSummaryDocument({
    provider: EXTERNAL_PROVIDER_ID,
    connected: false,
    spotifyConnected: false,
    musicProfile: {},
  });
  assert.equal(noMusic, null);
  const scored = scoreMusicCompatibility(external, emptyTaste());
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("7. No music + no music yields data_unavailable", () => {
  const scored = scoreMusicCompatibility(emptyTaste(), emptyTaste());
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("real score 0 with data is distinct from data_unavailable", () => {
  const viewer = {
    trackIds: ["v1", "v2"],
    artistIds: ["va1"],
    genres: ["jazz"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const candidate = {
    trackIds: ["c1", "c2"],
    artistIds: ["ca1"],
    genres: ["metal"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const scored = scoreMusicCompatibility(viewer, candidate);
  assert.equal(scored.score, 0);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
  assert.ok(scored.insights.some((item) => item.code === "band_low"));
});

test("recent artists: max 5 unique chronological with duplicate skip (Phase 5.9)", () => {
  const artistNames = ["Artist A", "Artist B", "Artist A", "Artist C", "Artist D", "Artist E", "Artist F"];
  const artistIds = ["a", "b", "a", "c", "d", "e", "f"];
  const recentlyPlayedRaw = artistNames.map((name, index) => ({
    played_at: `2026-08-28T${String(index).padStart(2, "0")}:00:00Z`,
    track: {
      id: `t${index}`,
      name: `Track ${index}`,
      artists: [{id: artistIds[index], name}],
    },
  }));
  const recentArtists = extractRecentArtists(recentlyPlayedRaw);
  assert.equal(recentArtists.length, 5);
  assert.deepEqual(
    recentArtists.map((artist) => artist.name),
    ["Artist A", "Artist B", "Artist C", "Artist D", "Artist E"],
  );
});

test("recentArtists display field stays separate from recentArtistIds scoring field", () => {
  const normalized = spotifyNormalized({
    recentlyPlayedRaw: [
      {
        played_at: "2026-08-28T01:00:00Z",
        track: {id: "rt1", name: "R1", artists: [{id: "ra1", name: "Recent A"}]},
      },
      {
        played_at: "2026-08-28T02:00:00Z",
        track: {id: "rt2", name: "R2", artists: [{id: "ra2", name: "Recent B"}]},
      },
    ],
  });
  assert.equal(normalized.recentArtists.length, 2);
  assert.deepEqual(normalized.recentArtistIds, ["ra1", "ra2"]);
  const summary = normalizedToSummaryFields(normalized);
  assert.equal(summary.musicProfile.recentArtists.length, 2);
  assert.deepEqual(summary.musicProfile.recentArtistIds, ["ra1", "ra2"]);
});

test("provider registry: unknown provider rejected", () => {
  assert.throws(
    () => resolveMusicProvider("apple-music"),
    (error) => error.code === "invalid-argument" && error.message === "unknown-music-provider",
  );
});

test("provider registry: external unavailable in production until configured", () => {
  clearExternalEnv();
  assert.equal(isExternalProviderProductionReady(), false);
  assert.throws(
    () => resolveMusicProvider(EXTERNAL_PROVIDER_ID),
    (error) => error.code === "failed-precondition" && error.message === "external-api-not-configured",
  );
  restoreEnv();
});

test("provider registry: resolveProviderIdFromSummary defaults safely", () => {
  assert.equal(defaultMusicProviderId(), "spotify");
  assert.equal(isKnownMusicProviderId("spotify"), true);
  assert.equal(isKnownMusicProviderId("external"), true);
  assert.equal(isKnownMusicProviderId("unknown"), false);
  assert.equal(
    resolveProviderIdFromSummary({spotifyConnected: true, provider: undefined}),
    "spotify",
  );
  assert.equal(
    resolveProviderIdFromSummary({connected: true, provider: EXTERNAL_PROVIDER_ID}),
    EXTERNAL_PROVIDER_ID,
  );
});

test("summary serialization excludes secrets for spotify and external", () => {
  for (const normalized of [spotifyNormalized(), externalNormalized()]) {
    const summary = normalizedToSummaryFields(normalized);
    const serialized = JSON.stringify(summary).toLowerCase();
    for (const forbidden of [
      "accesstoken",
      "refreshtoken",
      "client_secret",
      "api_secret",
      "api_key",
    ]) {
      assert.equal(serialized.includes(forbidden), false, `${forbidden} in ${normalized.provider}`);
    }
  }
});

test("external provider resolves only when API configured", () => {
  configureExternalEnv();
  assert.equal(isExternalProviderProductionReady(), true);
  const provider = resolveMusicProvider(EXTERNAL_PROVIDER_ID);
  assert.equal(provider.providerId, EXTERNAL_PROVIDER_ID);
  restoreEnv();
});
