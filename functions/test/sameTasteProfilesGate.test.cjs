const {describe, it, beforeEach} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

/**
 * getSameTasteProfiles hands another member's profile to the caller, so it
 * must hold the same line as Discover and Picks: only a discoverable profile
 * on an eligible account, and only its moderation-approved photos. The
 * compiled callable runs for real through `.run(request)` against an
 * in-memory Firestore; the Admin SDK entry points are swapped before the
 * module loads.
 */
const db = createFakeFirestore();
installFirebaseAdminStubs({db});

const {getSameTasteProfiles} = require("../lib/spotifyMusic.js");
const profileSafety = require("../lib/profileSafety.js");

const VIEWER = "viewer";
const DAY_MS = 24 * 60 * 60 * 1000;

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

function photo(id, moderationStatus, order) {
  return {
    id,
    downloadUrl: `https://photos.test/${id}/full.jpg`,
    thumbUrl: `https://photos.test/${id}/thumb.jpg`,
    cardUrl: `https://photos.test/${id}/card.jpg`,
    storagePath: `users/x/photos/${id}.jpg`,
    order,
    isPrimary: order === 0,
    ...(moderationStatus ? {moderationStatus} : {}),
  };
}

function profile(overrides = {}) {
  return {
    displayName: "Ada",
    age: 27,
    gender: "woman",
    bio: "Vinyl and long walks",
    city: "Izmir",
    interests: ["music"],
    isDiscoverable: true,
    profileCompleted: true,
    profileModerationStatus: "approved",
    photos: [photo("p0", "approved", 0), photo("p1", "approved", 1), photo("p2", "approved", 2)],
    ...overrides,
  };
}

/** A member who shares the viewer's taste; `overrides` bend one document. */
function member(uid, {profileData, account, summary} = {}) {
  return {
    [`users/${uid}`]: account ?? {accountStatus: "active"},
    [`users/${uid}/music/summary`]: summary ?? musicSummary(),
    [`profiles/${uid}`]: profileData ?? profile(),
  };
}

function seed(...members) {
  db.reset(Object.assign(
    {
      [`users/${VIEWER}`]: {accountStatus: "active"},
      [`users/${VIEWER}/music/summary`]: musicSummary(),
      [`profiles/${VIEWER}`]: profile({displayName: "Viewer", gender: "man"}),
    },
    ...members,
  ));
}

async function sameTaste() {
  const result = await callAs(getSameTasteProfiles, VIEWER);
  return result.items;
}

const uidsOf = (items) => items.map((item) => item.uid).sort();

beforeEach(() => {
  db.reset({});
});

describe("getSameTasteProfiles candidate gate", () => {
  it("returns a discoverable member on an eligible account", async () => {
    seed(member("ada"));
    const items = await sameTaste();
    assert.deepEqual(uidsOf(items), ["ada"]);
    assert.ok(items[0].musicScore > 0);
  });

  it("keeps the response shape the client parses", async () => {
    seed(member("ada"));
    const [item] = await sameTaste();
    for (const key of [
      "uid", "musicScore", "sharedArtists", "sharedTracks", "sharedGenres",
      "sharedArtistCount", "sharedTrackCount", "sharedGenreCount", "profile",
    ]) {
      assert.ok(key in item, `item.${key} is missing`);
    }
    assert.equal(item.profile.uid, "ada");
    assert.equal(item.profile.displayName, "Ada");
    assert.equal(item.profile.age, 27);
    assert.equal(item.profile.gender, "woman");
    assert.equal(item.profile.bio, "Vinyl and long walks");
    assert.equal(item.profile.city, "Izmir");
    assert.deepEqual(item.profile.interests, ["music"]);
    assert.ok(Array.isArray(item.profile.photos));
  });

  it("excludes a profile held by moderation", async () => {
    seed(
      member("ok"),
      member("review", {profileData: profile({profileModerationStatus: "manual_review"})}),
      member("rejected", {profileData: profile({profileModerationStatus: "rejected"})}),
      member("suspended", {profileData: profile({profileModerationStatus: "suspended"})}),
      // The legacy field is honoured when the canonical one is absent.
      member("legacy", {profileData: profile({profileModerationStatus: undefined, moderationStatus: "manual_review"})}),
    );
    assert.deepEqual(uidsOf(await sameTaste()), ["ok"]);
  });

  it("excludes an incomplete profile", async () => {
    const unfinished = profile();
    delete unfinished.profileCompleted;
    seed(
      member("ok"),
      member("incomplete", {profileData: profile({profileCompleted: false})}),
      member("unfinished", {profileData: unfinished}),
    );
    assert.deepEqual(uidsOf(await sameTaste()), ["ok"]);
  });

  it("excludes a profile that is not explicitly discoverable", async () => {
    const unset = profile();
    delete unset.isDiscoverable;
    seed(
      member("ok"),
      member("hidden", {profileData: profile({isDiscoverable: false})}),
      member("unset", {profileData: unset}),
    );
    assert.deepEqual(uidsOf(await sameTaste()), ["ok"]);
  });

  it("excludes an underage profile and a member with no profile", async () => {
    const noProfile = member("ghost");
    delete noProfile["profiles/ghost"];
    seed(member("ok"), member("minor", {profileData: profile({age: 17})}), noProfile);
    assert.deepEqual(uidsOf(await sameTaste()), ["ok"]);
  });

  it("excludes a member whose account is restricted", async () => {
    const now = Date.now();
    seed(
      member("ok"),
      member("banned", {account: {accountStatus: "banned"}}),
      member("legacy-banned", {account: {isBanned: true}}),
      member("suspended", {account: {accountStatus: "suspended"}}),
      member("timed-out", {account: {accountStatus: "suspended", suspendedUntil: new Date(now + DAY_MS)}}),
      member("deleted", {account: {accountStatus: "deleted"}}),
    );
    assert.deepEqual(uidsOf(await sameTaste()), ["ok"]);
  });

  it("returns a member whose suspension has ended", async () => {
    seed(member("back", {
      account: {accountStatus: "suspended", suspendedUntil: new Date(Date.now() - DAY_MS)},
    }));
    assert.deepEqual(uidsOf(await sameTaste()), ["back"]);
  });

  it("reads each candidate's account once", async () => {
    seed(member("ada"), member("banned", {account: {accountStatus: "banned"}}));
    await sameTaste();
    const {byPath} = db.stats();
    assert.equal(byPath.get("users/ada"), 1);
    assert.equal(byPath.get("users/banned"), 1);
    // A restricted account is dropped before its profile is fetched.
    assert.equal(byPath.get("profiles/banned"), undefined);
  });
});

describe("getSameTasteProfiles photo projection", () => {
  it("never returns a pending, rejected or unmoderated photo", async () => {
    const unmoderated = photo("p-unmoderated", null, 4);
    seed(member("ada", {
      profileData: profile({
        photos: [
          photo("p-approved", "approved", 0),
          photo("p-pending", "pending", 1),
          photo("p-rejected", "rejected", 2),
          photo("p-review", "manual_review", 3),
          unmoderated,
        ],
      }),
    }));
    const [item] = await sameTaste();
    assert.deepEqual(item.profile.photos.map((entry) => entry.id), ["p-approved"]);
    const wire = JSON.stringify(item);
    for (const id of ["p-pending", "p-rejected", "p-review", "p-unmoderated"]) {
      assert.ok(!wire.includes(id), `${id} reached the caller`);
    }
  });

  it("returns an approved photo as the public projection, without storage fields", async () => {
    seed(member("ada"));
    const [item] = await sameTaste();
    assert.deepEqual(item.profile.photos[0], {
      id: "p0",
      downloadUrl: "https://photos.test/p0/full.jpg",
      thumbUrl: "https://photos.test/p0/thumb.jpg",
      cardUrl: "https://photos.test/p0/card.jpg",
      order: 0,
      isPrimary: true,
      moderationStatus: "approved",
    });
    assert.equal(item.profile.photos.length, 3);
    assert.ok(!JSON.stringify(item).includes("storagePath"));
  });

  it("returns an empty list when no photo is approved", async () => {
    seed(member("ada", {
      profileData: profile({photos: [photo("p-pending", "pending", 0)]}),
    }));
    const [item] = await sameTaste();
    assert.deepEqual(item.profile.photos, []);
  });

  it("carries no profile field beyond the public projection", async () => {
    seed(member("ada", {
      profileData: profile({
        latitude: 38.4,
        longitude: 27.1,
        geohash: "swg",
        fcmToken: "secret-token",
        faceAnchorPhotoIds: ["p0"],
      }),
    }));
    const [item] = await sameTaste();
    const wire = JSON.stringify(item);
    for (const leaked of ["latitude", "longitude", "geohash", "secret-token", "faceAnchorPhotoIds"]) {
      assert.ok(!wire.includes(leaked), `${leaked} reached the caller`);
    }
  });
});

// The Face Anchor rule lives in isProfileDiscoverable. It applies here from
// the moment this build has it, with no change to the callable.
const faceAnchorRule = typeof profileSafety.faceAnchorSatisfied === "function";

describe("getSameTasteProfiles Face Anchor rule", {skip: !faceAnchorRule && "this build has no Face Anchor rule"}, () => {
  it("excludes a profile under the rule with no verified first photo", async () => {
    seed(
      member("anchored", {profileData: profile({faceAnchorRequired: true, faceAnchorPhotoIds: ["p0"]})}),
      member("unanchored", {profileData: profile({faceAnchorRequired: true, faceAnchorPhotoIds: []})}),
      member("wrong-first", {profileData: profile({faceAnchorRequired: true, faceAnchorPhotoIds: ["p2"]})}),
      member("exempt"),
    );
    assert.deepEqual(uidsOf(await sameTaste()), ["anchored", "exempt"]);
  });
});
