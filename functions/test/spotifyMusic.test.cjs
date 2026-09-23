const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  assertMusicOwnership,
  disconnectPlan,
  genreShares,
  hasPlaylistScope,
  isSyncThrottled,
  planTokenUse,
  spotifyErrorForStatus,
  summarizeArtists,
  summarizeTracks,
  toClientProfile,
  TOKEN_REFRESH_SKEW_MS,
} = require("../lib/spotifyMusic.js");
const {
  RECENT_UNIQUE_TRACK_LIMIT,
  SYNC_MIN_INTERVAL_MS,
} = require("../lib/musicCompatibility.js");

function track(id, name, artists = ["Artist"], albumImage = "https://img/a.jpg") {
  return {
    id,
    name,
    artists: artists.map((artistName, index) => ({
      id: `artist-${index}`,
      name: artistName,
    })),
    album: {images: [{url: albumImage}]},
  };
}

function artist(id, name, genres = []) {
  return {id, name, genres, images: [{url: `https://img/${id}.jpg`}]};
}

describe("spotifyLinkMusic account ownership", () => {
  it("accepts a Spotify account nobody has claimed", () => {
    assert.doesNotThrow(() => assertMusicOwnership({exists: false}, "uid-a"));
  });

  it("accepts re-linking the account the same user already owns", () => {
    assert.doesNotThrow(() =>
      assertMusicOwnership({exists: true, uid: "uid-a"}, "uid-a"),
    );
  });

  it("refuses a Spotify account another Mevora user owns", () => {
    assert.throws(
      () => assertMusicOwnership({exists: true, uid: "uid-a"}, "uid-b"),
      (error) => error.code === "failed-precondition",
    );
  });

  it("refuses a claimed index with a missing uid", () => {
    assert.throws(
      () => assertMusicOwnership({exists: true}, "uid-b"),
      (error) => error.code === "failed-precondition",
    );
  });
});

describe("music summary sent to the client", () => {
  it("reports a disconnected account without any taste data", () => {
    for (const data of [undefined, {}, {spotifyConnected: false}]) {
      assert.deepEqual(toClientProfile(data), {
        spotifyConnected: false,
        connected: false,
      });
    }
  });

  it("carries the public taste for a connected account", () => {
    const profile = toClientProfile({
      spotifyConnected: true,
      spotifyUserId: "spotify-user-1",
      displayName: "Listener",
      topTracks: [{id: "t1", name: "One"}],
      topArtists: [{id: "a1", name: "Artist"}],
      recentlyPlayed: [{id: "t2", name: "Two"}],
      musicProfile: {genreNames: ["pop"]},
    });
    assert.equal(profile.spotifyConnected, true);
    assert.equal(profile.spotifyUserId, "spotify-user-1");
    assert.equal(profile.topTracks.length, 1);
    assert.equal(profile.topArtists.length, 1);
    assert.equal(profile.recentlyPlayed.length, 1);
  });

  it("never forwards the stored Spotify tokens", () => {
    // Tokens live in spotifySecrets/{uid}. Even if a summary document ever
    // carried them, the client projection must drop them.
    const profile = toClientProfile({
      spotifyConnected: true,
      spotifyUserId: "spotify-user-1",
      accessToken: "spotify-access",
      refreshToken: "spotify-refresh",
      clientSecret: "shhh",
      expiresAt: 123,
    });
    const serialized = JSON.stringify(profile);
    for (const leak of [
      "accessToken",
      "refreshToken",
      "clientSecret",
      "spotify-access",
      "spotify-refresh",
      "shhh",
    ]) {
      assert.equal(
        serialized.includes(leak),
        false,
        `client profile must not carry ${leak}`,
      );
    }
  });
});

describe("taste mapping", () => {
  it("summarizes top tracks with artist and artwork", () => {
    const [first] = summarizeTracks([track("t1", "One", ["A", "B"])]);
    assert.equal(first.id, "t1");
    assert.equal(first.name, "One");
    assert.equal(first.artist, "A, B");
    assert.equal(first.image, "https://img/a.jpg");
  });

  it("unwraps the recently-played envelope and keeps played_at", () => {
    const [first] = summarizeTracks([
      {track: track("t1", "One"), played_at: "2026-09-22T10:00:00Z"},
    ]);
    assert.equal(first.id, "t1");
    assert.equal(first.playedAt, "2026-09-22T10:00:00Z");
  });

  it("deduplicates repeated tracks by Spotify id, not by name", () => {
    const items = [
      {track: track("t1", "One")},
      {track: track("t1", "One (Radio Edit)")},
      {track: track("t2", "One")},
    ];
    const summarized = summarizeTracks(items, RECENT_UNIQUE_TRACK_LIMIT);
    assert.deepEqual(
      summarized.map((item) => item.id),
      ["t1", "t2"],
    );
  });

  it("honours the recent-track limit", () => {
    const items = Array.from({length: 40}, (_, index) => ({
      track: track(`t${index}`, `Track ${index}`),
    }));
    assert.equal(
      summarizeTracks(items, RECENT_UNIQUE_TRACK_LIMIT).length,
      RECENT_UNIQUE_TRACK_LIMIT,
    );
  });

  it("skips entries without a Spotify id", () => {
    assert.deepEqual(summarizeTracks([{name: "no id"}, {track: {}}]), []);
    assert.deepEqual(summarizeArtists([{name: "no id"}]), []);
  });

  it("summarizes top artists with their genres", () => {
    const [first] = summarizeArtists([artist("a1", "Artist", ["pop", "indie"])]);
    assert.equal(first.id, "a1");
    assert.deepEqual(first.genres, ["pop", "indie"]);
  });

  it("derives genre shares from artist genres, normalized and ranked", () => {
    const shares = genreShares([
      {id: "a1", name: "A", genres: ["Pop", "indie"]},
      {id: "a2", name: "B", genres: ["pop"]},
      {id: "a3", name: "C", genres: ["POP", "rock"]},
    ]);
    assert.equal(shares[0].name, "pop", "case is folded and pop ranks first");
    const total = shares.reduce((sum, item) => sum + item.percent, 0);
    assert.ok(total > 0 && total <= 105, `unexpected share total ${total}`);
    assert.ok(shares.length <= 8);
  });

  it("returns no genres when the account has none", () => {
    assert.deepEqual(genreShares([]), []);
    assert.deepEqual(genreShares([{id: "a1", name: "A", genres: []}]), []);
  });

  it("handles an empty or partial Spotify response without throwing", () => {
    // An account with no listening history is a successful import of nothing,
    // not a failed pipeline.
    assert.deepEqual(summarizeTracks([]), []);
    assert.deepEqual(summarizeArtists([]), []);
    assert.deepEqual(summarizeTracks([{track: null}]), []);
  });
});

describe("playlist taste scope gate", () => {
  it("reads playlists only when the grant allows it", () => {
    assert.equal(hasPlaylistScope("user-top-read playlist-read-private"), true);
    assert.equal(hasPlaylistScope("playlist-read-collaborative"), true);
  });

  it("stays out of playlists without the scope", () => {
    assert.equal(hasPlaylistScope(undefined), false);
    assert.equal(hasPlaylistScope(""), false);
    assert.equal(hasPlaylistScope("user-top-read user-read-recently-played"), false);
  });
});

describe("Spotify Web API failures", () => {
  it("maps 401 to an expired token", () => {
    const error = spotifyErrorForStatus(401);
    assert.equal(error.code, "unauthenticated");
    assert.match(error.message, /token-expired/);
  });

  it("maps 403 to a denied grant", () => {
    assert.equal(spotifyErrorForStatus(403).code, "permission-denied");
  });

  it("maps other non-2xx responses to an upstream outage", () => {
    for (const status of [400, 429, 500, 502, 503]) {
      assert.equal(
        spotifyErrorForStatus(status).code,
        "unavailable",
        `status ${status}`,
      );
    }
  });

  it("lets a successful response through", () => {
    for (const status of [200, 201, 204]) {
      assert.equal(spotifyErrorForStatus(status), null, `status ${status}`);
    }
  });
});

describe("token lifecycle", () => {
  const now = 1_700_000_000_000;

  it("reuses a token that is still comfortably valid", () => {
    assert.equal(
      planTokenUse({accessToken: "a", expiresAt: now + 60_000}, now),
      "use",
    );
  });

  it("refreshes inside the expiry skew, before the token actually dies", () => {
    assert.equal(
      planTokenUse(
        {accessToken: "a", refreshToken: "r", expiresAt: now + TOKEN_REFRESH_SKEW_MS - 1},
        now,
      ),
      "refresh",
    );
  });

  it("refreshes an expired token when a refresh grant exists", () => {
    assert.equal(
      planTokenUse({accessToken: "a", refreshToken: "r", expiresAt: now - 1}, now),
      "refresh",
    );
  });

  it("reports an expired token with no way to refresh", () => {
    assert.equal(
      planTokenUse({accessToken: "a", expiresAt: now - 1}, now),
      "expired",
    );
  });

  it("reports an account that never connected Spotify", () => {
    assert.equal(planTokenUse(null, now), "not-connected");
    assert.equal(planTokenUse(undefined, now), "not-connected");
  });
});

describe("sync throttle", () => {
  const now = 1_700_000_000_000;

  it("always allows the first sync", () => {
    assert.equal(isSyncThrottled(null, now), false);
  });

  it("throttles a re-sync inside the interval", () => {
    const last = new Date(now - SYNC_MIN_INTERVAL_MS + 1_000);
    assert.equal(isSyncThrottled(last, now), true);
  });

  it("allows a re-sync once the interval has passed", () => {
    const last = new Date(now - SYNC_MIN_INTERVAL_MS - 1);
    assert.equal(isSyncThrottled(last, now), false);
  });
});

describe("disconnect cleanup", () => {
  it("removes the secrets, the summary and the Spotify index claim", () => {
    const plan = disconnectPlan("uid-a", "spotify-user-1");
    assert.deepEqual(plan.deletes, [
      "spotifySecrets/uid-a",
      "users/uid-a/music/summary",
      "musicSpotifyIndex/spotify-user-1",
    ]);
  });

  it("clears the discoverable spotifyConnected flag", () => {
    const plan = disconnectPlan("uid-a", "spotify-user-1");
    assert.equal(plan.profilePath, "profiles/uid-a");
    assert.deepEqual(plan.profileData, {spotifyConnected: false});
  });

  it("still clears local state when the Spotify id is unknown", () => {
    for (const unknown of [undefined, null, ""]) {
      const plan = disconnectPlan("uid-a", unknown);
      assert.deepEqual(plan.deletes, [
        "spotifySecrets/uid-a",
        "users/uid-a/music/summary",
      ]);
      assert.deepEqual(plan.profileData, {spotifyConnected: false});
    }
  });

  it("writes music data only under the authenticated uid", () => {
    const plan = disconnectPlan("uid-a", "spotify-user-1");
    for (const docPath of [...plan.deletes, plan.profilePath]) {
      assert.ok(
        docPath.includes("uid-a") || docPath.startsWith("musicSpotifyIndex/"),
        `${docPath} escapes the caller's own documents`,
      );
    }
  });
});
