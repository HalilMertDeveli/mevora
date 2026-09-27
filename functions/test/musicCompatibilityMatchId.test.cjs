const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * getMatchMusicCompatibility must only ever read a top-level matches/{id}
 * document. The compiled callable runs for real through `.run(request)`
 * against an in-memory Firestore; the Admin SDK entry points are swapped
 * before the module loads.
 */
const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

const {getMatchMusicCompatibility} = require("../lib/spotifyMusic.js");

const ATTACKER = "user-a";
const PEER = "user-b";
const VICTIM = "user-v";
const OUTSIDER = "user-c";
const canonical = (a, b) => [a, b].sort().join("_");
const MATCH_ATTACKER_PEER = canonical(ATTACKER, PEER);
const FORGED_MATCH_ID = `${MATCH_ATTACKER_PEER}/messages/forged`;

function musicSummary() {
  return {
    spotifyConnected: true,
    musicProfile: {
      trackIds: ["t1", "t2", "t3"],
      artistIds: ["ar1", "ar2"],
      genres: ["indie", "rock"],
      recentTrackIds: ["t1"],
      recentArtistIds: ["ar1"],
    },
    topTracks: [
      {id: "t1", name: "Song One", artist: "Band"},
      {id: "t2", name: "Song Two", artist: "Band"},
    ],
    topArtists: [{id: "ar1", name: "Band"}],
  };
}

function activeMatch(userIds) {
  return {userIds, isActive: true};
}

async function rejectsWith(promise, code) {
  await assert.rejects(promise, (error) => {
    assert.equal(error.code, code, `expected ${code}, got ${error.code}: ${error.message}`);
    return true;
  });
}

beforeEach(() => {
  db.reset({
    [`matches/${MATCH_ATTACKER_PEER}`]: activeMatch([ATTACKER, PEER]),
    // What a participant can write today: a message document under their own
    // match carrying match-shaped fields that name an arbitrary victim.
    [`matches/${FORGED_MATCH_ID}`]: {
      senderId: ATTACKER,
      receiverId: PEER,
      type: "text",
      encrypted: true,
      userIds: [ATTACKER, VICTIM],
      isActive: true,
    },
    [`users/${ATTACKER}/music/summary`]: musicSummary(),
    [`users/${PEER}/music/summary`]: musicSummary(),
    [`users/${VICTIM}/music/summary`]: musicSummary(),
  });
  auth.users.clear();
  // Premium unlocks the detailed payload, so a leak would be at its widest.
  auth.users.set(ATTACKER, {uid: ATTACKER, customClaims: {premium: true}});
});

describe("getMatchMusicCompatibility matchId validation", () => {
  it("the forged nested document is reachable through collection().doc()", () => {
    // Control: a slash-bearing id is a relative path to the Admin SDK, so
    // collection("matches").doc(id) alone does not stop the traversal. The
    // id pattern is what does.
    const ref = db.collection("matches").doc(FORGED_MATCH_ID);
    assert.equal(ref.path, `matches/${FORGED_MATCH_ID}`);
    assert.equal(db.has(ref.path), true);
  });

  it("rejects a matchId that resolves to a nested message document", async () => {
    await rejectsWith(
      callAs(getMatchMusicCompatibility, ATTACKER, {matchId: FORGED_MATCH_ID}),
      "invalid-argument",
    );
  });

  it("rejects every id that is not a single document id segment", async () => {
    const malformed = [
      `/${MATCH_ATTACKER_PEER}`,
      `${MATCH_ATTACKER_PEER}/`,
      `${MATCH_ATTACKER_PEER}/messages`,
      "..",
      ".",
      `${MATCH_ATTACKER_PEER}.x`,
      "a b",
      "x".repeat(129),
      "",
      "   ",
    ];
    for (const matchId of malformed) {
      await rejectsWith(
        callAs(getMatchMusicCompatibility, ATTACKER, {matchId}),
        "invalid-argument",
      );
    }
  });

  it("rejects a missing or non-string matchId", async () => {
    for (const data of [{}, {matchId: null}, {matchId: 42}, {matchId: ["a", "b"]}, {matchId: {}}]) {
      await rejectsWith(callAs(getMatchMusicCompatibility, ATTACKER, data), "invalid-argument");
    }
  });

  it("still requires sign-in before looking at the matchId", async () => {
    await rejectsWith(
      callAs(getMatchMusicCompatibility, null, {matchId: FORGED_MATCH_ID}),
      "unauthenticated",
    );
  });

  it("serves the real match to its participant", async () => {
    const result = await callAs(getMatchMusicCompatibility, ATTACKER, {
      matchId: MATCH_ATTACKER_PEER,
    });
    assert.equal(result.available, true);
    assert.equal(result.teaser, false);
    assert.ok(result.score > 0);
  });

  it("accepts the longest valid id and treats an unknown one as no match", async () => {
    const result = await callAs(getMatchMusicCompatibility, ATTACKER, {
      matchId: "x".repeat(128),
    });
    assert.deepEqual(result, {available: false, reason: "no_match"});
  });

  it("still refuses a well-formed id to a non-participant", async () => {
    await rejectsWith(
      callAs(getMatchMusicCompatibility, OUTSIDER, {matchId: MATCH_ATTACKER_PEER}),
      "permission-denied",
    );
  });
});
