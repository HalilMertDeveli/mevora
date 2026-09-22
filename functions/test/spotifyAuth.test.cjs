const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  resolveSpotifyLoginIdentity,
  buildSpotifyAuthResponse,
  requireString,
} = require("../lib/spotifyAuth.js");

const SPOTIFY_ID = "spotify-user-1";

function index(uid) {
  return uid === undefined ? {exists: false} : {exists: true, uid};
}

describe("spotifyCompleteAuth input validation", () => {
  it("rejects a missing, blank or non-string argument", () => {
    for (const value of [undefined, null, "", "   ", 42, {}, []]) {
      assert.throws(
        () => requireString(value, "code"),
        (error) => error.code === "invalid-argument",
        `expected ${JSON.stringify(value)} to be rejected`,
      );
    }
  });

  it("trims an accepted value", () => {
    assert.equal(requireString("  auth-code  ", "code"), "auth-code");
  });
});

describe("spotifyCompleteAuth identity resolution", () => {
  it("creates a new Mevora account for an unseen Spotify identity", () => {
    const plan = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      index: index(undefined),
    });
    assert.deepEqual(plan, {
      uid: `sp_${SPOTIFY_ID}`,
      isNewUser: true,
      alreadyLinked: false,
      writeIndex: true,
      createAuthUser: true,
    });
  });

  it("returns to the same uid on a second sign-in", () => {
    const first = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      index: index(undefined),
    });
    const second = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      index: index(first.uid),
    });
    assert.equal(second.uid, first.uid);
    assert.equal(second.isNewUser, false);
    assert.equal(second.createAuthUser, false);
    assert.equal(second.writeIndex, false, "index must not be rewritten");
  });

  it("links Spotify to the signed-in account and claims the index once", () => {
    const first = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      currentUid: "uid-a",
      index: index(undefined),
    });
    assert.equal(first.uid, "uid-a");
    assert.equal(first.alreadyLinked, true);
    assert.equal(first.isNewUser, false);
    assert.equal(first.writeIndex, true);

    const again = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      currentUid: "uid-a",
      index: index("uid-a"),
    });
    assert.equal(again.writeIndex, false);
  });

  it("refuses a Spotify account another Mevora user already owns", () => {
    assert.throws(
      () =>
        resolveSpotifyLoginIdentity({
          spotifyId: SPOTIFY_ID,
          currentUid: "uid-b",
          index: index("uid-a"),
        }),
      (error) =>
        error.code === "failed-precondition" &&
        error.details?.mevoraCode === "account-exists",
    );
  });

  it("refuses a claimed index whose uid is missing rather than taking it over", () => {
    assert.throws(
      () =>
        resolveSpotifyLoginIdentity({
          spotifyId: SPOTIFY_ID,
          currentUid: "uid-b",
          index: {exists: true},
        }),
      (error) => error.code === "failed-precondition",
    );
  });

  it("never hands the same Spotify id to two different uids", () => {
    const owner = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      index: index(undefined),
    });
    const returning = resolveSpotifyLoginIdentity({
      spotifyId: SPOTIFY_ID,
      index: index(owner.uid),
    });
    assert.equal(returning.uid, owner.uid);
    assert.throws(() =>
      resolveSpotifyLoginIdentity({
        spotifyId: SPOTIFY_ID,
        currentUid: "someone-else",
        index: index(owner.uid),
      }),
    );
  });
});

describe("spotifyCompleteAuth response", () => {
  const profile = {
    id: SPOTIFY_ID,
    display_name: "Listener",
    email: "listener@example.test",
    images: [{url: "https://images.example.test/a.jpg"}],
  };

  it("returns only the public identity fields", () => {
    const response = buildSpotifyAuthResponse({
      customToken: "firebase-custom-token",
      alreadyLinked: false,
      isNewUser: true,
      profile,
    });
    assert.deepEqual(Object.keys(response).sort(), [
      "alreadyLinked",
      "customToken",
      "displayName",
      "email",
      "isNewUser",
      "photoUrl",
    ]);
    assert.equal(response.displayName, "Listener");
    assert.equal(response.photoUrl, "https://images.example.test/a.jpg");
  });

  it("leaks no Spotify token or client secret to the client", () => {
    // The client only ever needs a Firebase custom token. Spotify's access
    // and refresh tokens stay in spotifySecrets/{uid}, server-side.
    const response = buildSpotifyAuthResponse({
      customToken: "firebase-custom-token",
      alreadyLinked: false,
      isNewUser: true,
      profile: {
        ...profile,
        access_token: "spotify-access",
        refresh_token: "spotify-refresh",
      },
    });
    const serialized = JSON.stringify(response);
    for (const leak of [
      "access_token",
      "refresh_token",
      "accessToken",
      "refreshToken",
      "clientSecret",
      "client_secret",
      "spotify-access",
      "spotify-refresh",
    ]) {
      assert.equal(
        serialized.includes(leak),
        false,
        `response must not carry ${leak}`,
      );
    }
  });

  it("nulls absent profile fields instead of omitting them", () => {
    const response = buildSpotifyAuthResponse({
      customToken: null,
      alreadyLinked: true,
      isNewUser: false,
      profile: {id: SPOTIFY_ID},
    });
    assert.equal(response.email, null);
    assert.equal(response.displayName, null);
    assert.equal(response.photoUrl, null);
    assert.equal(response.customToken, null);
    assert.equal(response.alreadyLinked, true);
  });
});
