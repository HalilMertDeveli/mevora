const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  deriveGeneralMusicTaste,
  emptyGeneralMusicTaste,
  MAX_SIGNATURE_ARTISTS,
  MAX_TASTE_GENRES,
  publicGeneralTasteHasContent,
  readGeneralMusicTaste,
  readPublicGeneralTaste,
  toPublicGeneralTaste,
} = require("../lib/musicTasteAnalysis.js");

const artist = (id, name, genres = []) => ({id, name, genres});
const track = (id, name) => ({id, name});

describe("a general taste needs something to work from", () => {
  it("returns an empty summary when Spotify gave nothing", () => {
    assert.deepEqual(deriveGeneralMusicTaste({}), emptyGeneralMusicTaste());
  });

  it("returns an empty summary for a brand new account", () => {
    const taste = deriveGeneralMusicTaste({
      longTermArtists: [],
      mediumTermArtists: [],
      longTermTracks: [],
      mediumTermTracks: [],
    });
    assert.equal(taste.dominantGenre, null);
    assert.deepEqual(taste.genres, []);
    assert.equal(taste.artistBreadth, 0);
  });

  it("works from one window alone", () => {
    const taste = deriveGeneralMusicTaste({
      mediumTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
    });
    assert.equal(taste.dominantGenre, "indie");
    assert.deepEqual(taste.signatureArtists.map((a) => a.name), [
      "Arctic Monkeys",
    ]);
    assert.equal(taste.stableArtistCount, 0, "one window cannot be stable");
  });
});

describe("what the member keeps coming back to", () => {
  const longTerm = [
    artist("a1", "Arctic Monkeys", ["indie", "alternative"]),
    artist("a2", "The Weeknd", ["r&b", "pop"]),
    artist("a3", "Radiohead", ["alternative"]),
  ];
  const mediumTerm = [
    artist("a2", "The Weeknd", ["r&b", "pop"]),
    artist("a1", "Arctic Monkeys", ["indie", "alternative"]),
    artist("a9", "A Passing Mood", ["hyperpop"]),
  ];

  const taste = deriveGeneralMusicTaste({
    longTermArtists: longTerm,
    mediumTermArtists: mediumTerm,
    longTermTracks: [track("t1", "Do I Wanna Know?"), track("t2", "Creep")],
    mediumTermTracks: [track("t1", "Do I Wanna Know?"), track("t9", "New Thing")],
  });

  it("counts the artists present in both windows", () => {
    assert.equal(taste.stableArtistCount, 2, "Arctic Monkeys and The Weeknd");
  });

  it("counts the tracks present in both windows", () => {
    assert.equal(taste.stableTrackCount, 1);
  });

  it("measures breadth across both windows without double counting", () => {
    assert.equal(taste.artistBreadth, 4, "a1, a2, a3, a9");
  });

  it("puts an artist in both windows ahead of one in a single window", () => {
    const names = taste.signatureArtists.map((a) => a.name);
    assert.ok(names.includes("Arctic Monkeys"));
    assert.ok(names.includes("The Weeknd"));
    assert.ok(
      !names.includes("A Passing Mood"),
      "a recent arrival is not a signature artist",
    );
  });

  it("names at most three artists", () => {
    assert.ok(taste.signatureArtists.length <= MAX_SIGNATURE_ARTISTS);
  });

  it("leads with the genre the lasting favourites carry", () => {
    assert.ok(
      ["alternative", "indie", "r&b"].includes(taste.dominantGenre),
      `unexpected dominant genre ${taste.dominantGenre}`,
    );
    // A genre carried by one short-lived artist may still appear in a long
    // enough list, but it must never outrank the lasting ones.
    const hyperpop = taste.genres.indexOf("hyperpop");
    assert.ok(
      hyperpop === -1 || hyperpop === taste.genres.length - 1,
      `a passing mood ranked at ${hyperpop} of ${taste.genres.length}`,
    );
    assert.notEqual(taste.dominantGenre, "hyperpop");
  });
});

describe("the summary is stable and bounded", () => {
  const many = Array.from({length: 12}, (_, i) =>
    artist(`a${i}`, `Artist ${i}`, [`genre${i}`]),
  );

  it("caps the genre list", () => {
    const taste = deriveGeneralMusicTaste({longTermArtists: many});
    assert.equal(taste.genres.length, MAX_TASTE_GENRES);
    assert.equal(taste.secondaryGenres.length, MAX_TASTE_GENRES - 1);
  });

  it("gives the same answer for the same input", () => {
    const once = deriveGeneralMusicTaste({longTermArtists: many});
    const twice = deriveGeneralMusicTaste({longTermArtists: many});
    assert.deepEqual(once, twice);
  });

  it("ignores entries Spotify returned without an id or a name", () => {
    const taste = deriveGeneralMusicTaste({
      longTermArtists: [
        {name: "No Id", genres: ["indie"]},
        {id: "a1", genres: ["indie"]},
        artist("a2", "Real Artist", ["indie"]),
      ],
    });
    assert.deepEqual(taste.signatureArtists.map((a) => a.name), [
      "Real Artist",
    ]);
  });

  it("folds genre casing and spacing together", () => {
    const taste = deriveGeneralMusicTaste({
      longTermArtists: [
        artist("a1", "One", ["Indie"]),
        artist("a2", "Two", [" indie "]),
      ],
    });
    assert.deepEqual(taste.genres, ["indie"]);
  });
});

describe("what a viewer is allowed to see", () => {
  const taste = deriveGeneralMusicTaste({
    longTermArtists: [
      artist("a1", "Arctic Monkeys", ["indie", "alternative"]),
      artist("a2", "The Weeknd", ["r&b"]),
    ],
    mediumTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
  });
  const published = toPublicGeneralTaste(taste, new Set(["a1", "a2"]));

  it("names only the artists the member chose to show", () => {
    assert.deepEqual(taste.signatureArtists.map((a) => a.name), ["Arctic Monkeys", "The Weeknd"]);
    assert.deepEqual(toPublicGeneralTaste(taste, new Set(["a2"])).signatureArtists, ["The Weeknd"]);
    assert.deepEqual(toPublicGeneralTaste(taste, new Set()).signatureArtists, []);
    // An id that is not a signature artist adds nothing.
    assert.deepEqual(toPublicGeneralTaste(taste, new Set(["zz"])).signatureArtists, []);
  });

  it("keeps genres and counts whatever was chosen", () => {
    const none = toPublicGeneralTaste(taste, new Set());
    assert.equal(none.dominantGenre, published.dominantGenre);
    assert.deepEqual(none.secondaryGenres, published.secondaryGenres);
    assert.equal(none.stableArtistCount, published.stableArtistCount);
    assert.equal(none.artistBreadth, published.artistBreadth);
  });

  it("publishes names, never ids", () => {
    const raw = JSON.stringify(published);
    assert.ok(raw.includes("Arctic Monkeys"));
    assert.ok(!raw.includes("a1"), "an id would let a viewer probe the library");
  });

  it("carries nothing from recently played", () => {
    // Checked on the field names: an artist called The Weeknd would make a
    // substring search on the whole payload lie.
    assert.deepEqual(Object.keys(published).sort(), [
      "artistBreadth",
      "dominantGenre",
      "secondaryGenres",
      "signatureArtists",
      "stableArtistCount",
    ]);
    assert.ok(published.signatureArtists.every((n) => typeof n === "string"));
  });

  it("keeps the secondary genre list short", () => {
    assert.ok(published.secondaryGenres.length <= 2);
  });
});

describe("reading a stored summary back", () => {
  it("treats a missing summary as empty", () => {
    assert.deepEqual(readGeneralMusicTaste(undefined), emptyGeneralMusicTaste());
    assert.deepEqual(readGeneralMusicTaste(null), emptyGeneralMusicTaste());
  });

  it("drops fields of the wrong shape rather than trusting them", () => {
    const taste = readGeneralMusicTaste({
      dominantGenre: 42,
      genres: ["indie", 7, "pop"],
      signatureArtists: [{id: "a1", name: "Real"}, {name: "No id"}, "nope"],
      stableArtistCount: -3,
      artistBreadth: "many",
    });
    assert.equal(taste.dominantGenre, null);
    assert.deepEqual(taste.genres, ["indie", "pop"]);
    assert.deepEqual(taste.signatureArtists, [{id: "a1", name: "Real"}]);
    assert.equal(taste.stableArtistCount, 0);
    assert.equal(taste.artistBreadth, 0);
  });

  it("round-trips a summary it produced itself", () => {
    const taste = deriveGeneralMusicTaste({
      longTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
      mediumTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
    });
    const back = readGeneralMusicTaste(JSON.parse(JSON.stringify(taste)));
    assert.deepEqual(back, taste);
  });
});

describe("reading a summary back in its published shape", () => {
  // The published shape flattens signatureArtists to names. Reading it with
  // the private reader silently dropped every one of them, so a viewer got a
  // summary with no artists in it.
  const published = {
    dominantGenre: "alternative",
    secondaryGenres: ["indie", "r&b"],
    signatureArtists: ["Arctic Monkeys", "The Weeknd"],
    stableArtistCount: 2,
    artistBreadth: 9,
  };

  it("keeps the artist names", () => {
    assert.deepEqual(readPublicGeneralTaste(published).signatureArtists, [
      "Arctic Monkeys",
      "The Weeknd",
    ]);
  });

  it("is not the private reader", () => {
    assert.deepEqual(
      readGeneralMusicTaste(published).signatureArtists,
      [],
      "the private reader wants {id, name} — that is the whole point",
    );
  });

  it("drops anything of the wrong shape", () => {
    const taste = readPublicGeneralTaste({
      dominantGenre: 7,
      secondaryGenres: "indie",
      signatureArtists: ["Real", 42, ""],
      stableArtistCount: -1,
      artistBreadth: "many",
    });
    assert.equal(taste.dominantGenre, null);
    assert.deepEqual(taste.secondaryGenres, []);
    assert.deepEqual(taste.signatureArtists, ["Real"]);
    assert.equal(taste.stableArtistCount, 0);
    assert.equal(taste.artistBreadth, 0);
  });

  it("treats an absent summary as nothing to show", () => {
    assert.equal(publicGeneralTasteHasContent(readPublicGeneralTaste(null)), false);
    assert.equal(publicGeneralTasteHasContent(readPublicGeneralTaste({})), false);
    assert.equal(publicGeneralTasteHasContent(readPublicGeneralTaste(published)), true);
  });

  it("round-trips what toPublicGeneralTaste produced", () => {
    const derived = toPublicGeneralTaste(
      deriveGeneralMusicTaste({
        longTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
        mediumTermArtists: [artist("a1", "Arctic Monkeys", ["indie"])],
      }),
      new Set(["a1"]),
    );
    assert.deepEqual(derived.signatureArtists, ["Arctic Monkeys"]);
    assert.deepEqual(readPublicGeneralTaste(derived), derived);
  });
});
