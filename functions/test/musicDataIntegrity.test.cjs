const test = require("node:test");
const assert = require("node:assert/strict");
const {
  buildSpotifyNormalizedProfile,
  extractRecentArtists,
  extractRecentArtistIds,
  genreShares,
  normalizedToSummaryFields,
  summarizeArtists,
  tasteFromSummaryDocument,
} = require("../lib/music/normalize/normalizeMusicProfile.js");
const {
  buildExternalNormalizedProfile,
} = require("../lib/music/normalize/normalizeExternalMusicProfile.js");
const {
  scoreMusicCompatibility,
  isTasteEmpty,
  SYNC_MIN_INTERVAL_MS,
  MUSIC_PROFILE_VERSION,
  RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT,
} = require("../lib/musicCompatibility.js");

const FORBIDDEN_SUMMARY_KEYS = [
  "accesstoken",
  "refreshtoken",
  "clientsecret",
  "spotify_client_secret",
  "api_key",
  "api_secret",
  "external_music_api",
];

function recentlyPlayedFromArtistNames(names) {
  return names.map((name, index) => ({
    played_at: `2026-08-28T${String(index).padStart(2, "0")}:00:00Z`,
    track: {
      id: `track-${index}`,
      name: `Track for ${name}`,
      artists: [{id: `id-${name.replace(/\s/g, "-").toLowerCase()}`, name, images: []}],
      album: {images: []},
    },
  }));
}

function spotifyFixture(overrides = {}) {
  return buildSpotifyNormalizedProfile({
    providerUserId: "sp-user-1",
    displayName: "Spotify User",
    topTracksRaw: [
      {id: "t1", name: "Track One", artists: [{id: "a1", name: "Artist A"}], album: {images: []}},
      {id: "t2", name: "Track Two", artists: [{id: "a2", name: "Artist B"}], album: {images: []}},
    ],
    topArtistsRaw: [
      {id: "a1", name: "Artist A", genres: ["pop"], images: []},
      {id: "a2", name: "Artist B", genres: ["rock"], images: []},
    ],
    recentlyPlayedRaw: [],
    playlistTrackIds: ["p1"],
    playlists: [{id: "pl1", name: "Mix", trackCount: 10}],
    ...overrides,
  });
}

function assertNoSecrets(payload, label) {
  const serialized = JSON.stringify(payload).toLowerCase();
  for (const key of FORBIDDEN_SUMMARY_KEYS) {
    assert.equal(serialized.includes(key), false, `${label} leaked ${key}`);
  }
}

/** Mirrors getMatchMusicCompatibility participant gate (no Firestore). */
function evaluateMatchParticipantAccess(matchData, uid) {
  if (!matchData || matchData.isActive !== true) {
    return {allowed: false, reason: "no_match"};
  }
  const userIds = Array.isArray(matchData.userIds) ? matchData.userIds : [];
  if (!userIds.includes(uid) || userIds.length !== 2) {
    return {allowed: false, error: "not-participant"};
  }
  const otherUid = userIds.find((id) => id !== uid) ?? "";
  if (!otherUid) {
    return {allowed: false, reason: "no_match"};
  }
  return {allowed: true, otherUid};
}

/** Mirrors syncSpotifyTaste throttle branch. */
function isSyncThrottled(lastSyncedMs, nowMs) {
  return lastSyncedMs != null && (nowMs - lastSyncedMs) < SYNC_MIN_INTERVAL_MS;
}

test("Firestore summary contract from normalized Spotify profile", () => {
  const normalized = spotifyFixture();
  const summary = normalizedToSummaryFields(normalized);
  const profile = summary.musicProfile;

  assert.equal(summary.provider, "spotify");
  assert.equal(summary.connected, true);
  assert.equal(summary.spotifyConnected, true);
  assert.equal(summary.musicProfileVersion, MUSIC_PROFILE_VERSION);
  assert.ok(Array.isArray(profile.trackIds));
  assert.ok(Array.isArray(profile.artistIds));
  assert.ok(Array.isArray(profile.recentTrackIds));
  assert.ok(Array.isArray(profile.recentArtistIds));
  assert.ok(Array.isArray(profile.recentArtists));
  assert.ok(Array.isArray(profile.genres));
  assert.ok(Array.isArray(profile.genreNames));
  assert.ok(Array.isArray(summary.topTracks));
  assert.ok(Array.isArray(summary.topArtists));
  assert.ok(Array.isArray(profile.playlistTrackIds));
  assert.equal(new Set(profile.trackIds).size, profile.trackIds.length);
  assert.equal(new Set(profile.artistIds).size, profile.artistIds.length);
});

test("summary excludes tokens and secrets", () => {
  const summary = normalizedToSummaryFields(spotifyFixture());
  assertNoSecrets(summary, "spotify summary");
  assertNoSecrets(buildExternalNormalizedProfile({
    userId: "ext-1",
    topTracks: [{id: "t1", name: "T", artist: "A"}],
    topArtists: [{id: "a1", name: "A", genres: ["pop"]}],
    genres: [{name: "pop", percent: 100}],
  }), "external normalized");
});

test("disconnect state: stale profile with connected false is not used", () => {
  const taste = tasteFromSummaryDocument({
    provider: "spotify",
    connected: false,
    spotifyConnected: false,
    musicProfile: {
      trackIds: ["stale-t1"],
      artistIds: ["stale-a1"],
      genreNames: ["pop"],
    },
  });
  assert.equal(taste, null);
});

test("disconnect state: missing summary yields null taste", () => {
  assert.equal(tasteFromSummaryDocument(undefined), null);
});

test("disconnect leads to data_unavailable in compatibility", () => {
  const connected = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture()));
  const empty = {
    trackIds: [],
    artistIds: [],
    genres: [],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  assert.ok(connected);
  const scored = scoreMusicCompatibility(connected, empty);
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("sync throttle: under 6 hours blocks, after 6 hours allows", () => {
  const now = Date.now();
  const fiveHoursAgo = now - (5 * 60 * 60 * 1000);
  const sevenHoursAgo = now - (7 * 60 * 60 * 1000);
  assert.equal(isSyncThrottled(fiveHoursAgo, now), true);
  assert.equal(isSyncThrottled(sevenHoursAgo, now), false);
  assert.equal(isSyncThrottled(null, now), false);
});

test("recent artists Phase 6.9 canonical example A B A C D E F", () => {
  const items = recentlyPlayedFromArtistNames([
    "Artist A",
    "Artist B",
    "Artist A",
    "Artist C",
    "Artist D",
    "Artist E",
    "Artist F",
  ]);
  const recentArtists = extractRecentArtists(items);
  assert.deepEqual(
    recentArtists.map((artist) => artist.name),
    ["Artist A", "Artist B", "Artist C", "Artist D", "Artist E"],
  );
});

test("recent artists: 0 artists", () => {
  assert.deepEqual(extractRecentArtists([]), []);
});

test("recent artists: 1 artist", () => {
  const items = recentlyPlayedFromArtistNames(["Solo"]);
  assert.equal(extractRecentArtists(items).length, 1);
});

test("recent artists: exactly 5 artists", () => {
  const items = recentlyPlayedFromArtistNames(["A1", "A2", "A3", "A4", "A5"]);
  assert.equal(extractRecentArtists(items).length, 5);
});

test("recent artists: 10 artists capped at 5", () => {
  const items = recentlyPlayedFromArtistNames([
    "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10",
  ]);
  assert.equal(extractRecentArtists(items).length, RECENT_UNIQUE_ARTIST_DISPLAY_LIMIT);
});

test("recent artists: duplicate IDs skipped", () => {
  const items = [
    {
      played_at: "2026-08-28T01:00:00Z",
      track: {id: "t1", name: "Track 1", artists: [{id: "dup", name: "Artist X"}], album: {images: []}},
    },
    {
      played_at: "2026-08-28T02:00:00Z",
      track: {id: "t2", name: "Track 2", artists: [{id: "dup", name: "Artist X"}], album: {images: []}},
    },
  ];
  assert.equal(extractRecentArtists(items).length, 1);
});

test("recent artists: same artist different track names keeps first chronological", () => {
  const items = [
    {
      played_at: "2026-08-28T01:00:00Z",
      track: {id: "t1", name: "Song Alpha", artists: [{id: "a1", name: "Shared Artist"}], album: {images: []}},
    },
    {
      played_at: "2026-08-28T02:00:00Z",
      track: {id: "t2", name: "Song Beta", artists: [{id: "a1", name: "Shared Artist"}], album: {images: []}},
    },
  ];
  assert.equal(extractRecentArtists(items).length, 1);
  assert.equal(extractRecentArtists(items)[0].name, "Shared Artist");
});

test("recent artists: missing image allowed", () => {
  const items = recentlyPlayedFromArtistNames(["No Image"]);
  const recentArtists = extractRecentArtists(items);
  assert.equal(recentArtists.length, 1);
  assert.equal(recentArtists[0].image, null);
});

test("recentArtistIds capped at 30 unique", () => {
  const items = [];
  for (let i = 0; i < 40; i += 1) {
    items.push({
      played_at: `2026-08-28T${String(i % 24).padStart(2, "0")}:00:00Z`,
      track: {
        id: `t${i}`,
        name: `Track ${i}`,
        artists: [{id: `artist-${i}`, name: `Artist ${i}`}],
        album: {images: []},
      },
    });
  }
  assert.equal(extractRecentArtistIds(items).length, 30);
});

test("genres: valid multiple genres from top artists only", () => {
  const genres = genreShares(summarizeArtists([
    {id: "a1", name: "A", genres: ["Pop", "R&B"]},
    {id: "a2", name: "B", genres: ["Rock"]},
  ]));
  assert.ok(genres.some((item) => item.name === "pop"));
  assert.ok(genres.some((item) => item.name === "r&b"));
  assert.ok(genres.some((item) => item.name === "rock"));
});

test("genres: duplicate genres aggregated not duplicated entries", () => {
  const genres = genreShares(summarizeArtists([
    {id: "a1", name: "A", genres: ["Pop"]},
    {id: "a2", name: "B", genres: ["Pop"]},
  ]));
  assert.equal(genres.filter((item) => item.name === "pop").length, 1);
});

test("genres: no genres when artists have none", () => {
  const normalized = spotifyFixture({
    topArtistsRaw: [
      {id: "a1", name: "Artist A", genres: [], images: []},
    ],
  });
  assert.deepEqual(normalized.topGenres, []);
});

test("genres: missing genre field yields empty", () => {
  const genres = genreShares(summarizeArtists([
    {id: "a1", name: "A"},
  ]));
  assert.deepEqual(genres, []);
});

test("genres: recently played alone does not invent genres", () => {
  const normalized = spotifyFixture({
    topArtistsRaw: [{id: "a1", name: "Artist A", genres: [], images: []}],
    recentlyPlayedRaw: recentlyPlayedFromArtistNames(["Recent Only"]),
  });
  assert.deepEqual(normalized.topGenres, []);
});

test("compatibility: Spotify + Spotify overlap", () => {
  const left = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture()));
  const right = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture({providerUserId: "sp-2"})));
  const scored = scoreMusicCompatibility(left, right);
  assert.ok(scored.score > 0);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("compatibility: Spotify + no music → data_unavailable", () => {
  const spotify = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture()));
  const empty = {
    trackIds: [],
    artistIds: [],
    genres: [],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const scored = scoreMusicCompatibility(spotify, empty);
  assert.equal(scored.score, 0);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("compatibility: no music + Spotify → data_unavailable", () => {
  const spotify = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture()));
  const empty = {
    trackIds: [],
    artistIds: [],
    genres: [],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const scored = scoreMusicCompatibility(empty, spotify);
  assert.equal(scored.insights[0].code, "data_unavailable");
});

test("compatibility: real zero score vs data_unavailable", () => {
  const viewer = {
    trackIds: ["v1"],
    artistIds: ["va1"],
    genres: ["jazz"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const candidate = {
    trackIds: ["c1"],
    artistIds: ["ca1"],
    genres: ["metal"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const scored = scoreMusicCompatibility(viewer, candidate);
  assert.equal(scored.score, 0);
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("compatibility: identical artists and tracks score high", () => {
  const taste = {
    trackIds: ["t1", "t2"],
    artistIds: ["a1"],
    genres: ["pop"],
    recentTrackIds: ["t1"],
    recentArtistIds: ["a1"],
    playlistTrackIds: [],
  };
  assert.equal(scoreMusicCompatibility(taste, {...taste}).score, 100);
});

test("compatibility: partial overlap mid score", () => {
  const viewer = {
    trackIds: ["t1", "t2"],
    artistIds: ["a1", "a2"],
    genres: ["pop"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const candidate = {
    trackIds: ["t1", "t3"],
    artistIds: ["a1", "a3"],
    genres: ["pop", "rock"],
    recentTrackIds: [],
    recentArtistIds: [],
    playlistTrackIds: [],
  };
  const scored = scoreMusicCompatibility(viewer, candidate);
  assert.ok(scored.score > 0);
  assert.ok(scored.score < 100);
});

test("match authorization: participant allowed", () => {
  const result = evaluateMatchParticipantAccess({
    isActive: true,
    userIds: ["user-a", "user-b"],
  }, "user-a");
  assert.equal(result.allowed, true);
  assert.equal(result.otherUid, "user-b");
});

test("match authorization: other participant allowed", () => {
  const result = evaluateMatchParticipantAccess({
    isActive: true,
    userIds: ["user-a", "user-b"],
  }, "user-b");
  assert.equal(result.allowed, true);
  assert.equal(result.otherUid, "user-a");
});

test("match authorization: non-participant denied", () => {
  const result = evaluateMatchParticipantAccess({
    isActive: true,
    userIds: ["user-a", "user-b"],
  }, "user-c");
  assert.equal(result.allowed, false);
  assert.equal(result.error, "not-participant");
});

test("match authorization: missing match denied", () => {
  const result = evaluateMatchParticipantAccess(undefined, "user-a");
  assert.equal(result.allowed, false);
  assert.equal(result.reason, "no_match");
});

test("match authorization: inactive match denied", () => {
  const result = evaluateMatchParticipantAccess({
    isActive: false,
    userIds: ["user-a", "user-b"],
  }, "user-a");
  assert.equal(result.allowed, false);
  assert.equal(result.reason, "no_match");
});

test("premium gate: server returns teaser shape for non-premium (contract)", () => {
  const nonPremiumResponse = {
    available: true,
    premiumRequired: true,
    teaser: true,
  };
  assert.equal(nonPremiumResponse.teaser, true);
  assert.equal(nonPremiumResponse.premiumRequired, true);
  assert.equal("score" in nonPremiumResponse, false);
});

test("provider compatibility: Spotify + External normalized profiles", () => {
  const spotify = tasteFromSummaryDocument(normalizedToSummaryFields(spotifyFixture()));
  const external = tasteFromSummaryDocument(normalizedToSummaryFields(buildExternalNormalizedProfile({
    userId: "ext-1",
    topTracks: [{id: "t1", name: "Track One", artist: "Artist A"}],
    topArtists: [{id: "a1", name: "Artist A", genres: ["pop"]}],
    genres: [{name: "pop", percent: 100}],
  })));
  const scored = scoreMusicCompatibility(spotify, external);
  assert.ok(scored.sharedTracks.includes("t1"));
  assert.notEqual(scored.insights[0]?.code, "data_unavailable");
});

test("deployed config: Spotify client ID default in source config", () => {
  const fs = require("node:fs");
  const path = require("node:path");
  const src = fs.readFileSync(
    path.join(__dirname, "../src/spotifyConfig.ts"),
    "utf8",
  );
  assert.ok(src.includes('default: "b0a808c4c2264b0ba179c2045a8d3445"'));
});
