const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {MEDIA} = require("./helpers/klipyFixtures.cjs");

const {
  CALIBRATION_SEED,
  CURATED_CATALOG,
  CURATED_GIPHY_CATALOG,
  CURATED_KLIPY_CATALOG,
  CURATED_KLIPY_ID_PREFIX,
  KLIPY_ID_PATTERN,
  curatedGiphyUpsertInput,
  curatedKlipyContentId,
  curatedKlipyUpsertInput,
  curatedUpsertInput,
  isCuratedKlipyEntry,
} = require("../lib/humor/calibrationSeed.js");
const {
  MAX_CURATED_VIDEO_DURATION_MS,
  calibrationCatalogPlan,
  curatedEntryProblems,
  curatedGiphyEntryProblems,
  curatedKlipyEntryProblems,
  seedCalibrationCatalog,
} = require("../lib/humor/calibrationCatalog.js");
const {
  parseHumorContent,
  toFeedSafeContent,
} = require("../lib/humor/contentRepository.js");
const {HUMOR_CORE_SEQUENCE, humorCoreSequenceProblems} = require("../lib/humor/coreSequence.js");
const {HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");

/**
 * The curated catalogue with video entries: a KLIPY clip can be a curated
 * item next to the GIPHY GIFs, validated by its own provider's rules, and the
 * GIFs are written exactly as they always were.
 */

/** A well-formed curated KLIPY clip for a fake id. */
function klipyEntry(klipyId = "1000000000000001", overrides = {}) {
  return {
    contentId: curatedKlipyContentId(klipyId),
    klipyId,
    calibrationEligible: true,
    category: "sarcasm",
    humorVector: {sarcasm: 0.85, dry: 0.4},
    language: "en",
    caption: null,
    media: {
      downloadUrl: `${MEDIA}/video.mp4`,
      thumbUrl: `${MEDIA}/preview.webp`,
      aspectRatio: 2.388,
      durationMs: 2460,
    },
    attribution: {
      provider: "klipy",
      displayName: null,
      username: null,
      sourceUrl: "https://klipy.com/clips/fixture-clip",
      verified: false,
    },
    sourceTrust: "curated",
    ...overrides,
  };
}

const withMedia = (media) => klipyEntry(undefined, {media: {...klipyEntry().media, ...media}});
const withCredit = (attribution) =>
  klipyEntry(undefined, {attribution: {...klipyEntry().attribution, ...attribution}});

describe("curated KLIPY entry", () => {
  it("has its own id namespace that fits a Core sequence id", () => {
    assert.equal(CURATED_KLIPY_ID_PREFIX, "hc_klipy_");
    assert.equal(curatedKlipyContentId("9924056256405606"), "hc_klipy_9924056256405606");
    assert.match(curatedKlipyContentId("9".repeat(24)), /^[A-Za-z0-9_-]{1,128}$/);
    assert.equal(KLIPY_ID_PATTERN.test("9924056256405606"), true);
    for (const id of ["", "12", "abc123456", "1e15", "1000000000000001x", "-1000000"]) {
      assert.equal(KLIPY_ID_PATTERN.test(id), false, id);
    }
    assert.equal(isCuratedKlipyEntry(klipyEntry()), true);
    assert.ok(CURATED_GIPHY_CATALOG.every((entry) => !isCuratedKlipyEntry(entry)));
  });

  it("accepts a well-formed clip, with or without a poster and a duration", () => {
    assert.deepEqual(curatedKlipyEntryProblems(klipyEntry()), []);
    assert.deepEqual(curatedKlipyEntryProblems(withMedia({thumbUrl: null})), []);
    assert.deepEqual(curatedKlipyEntryProblems(withMedia({durationMs: null})), []);
    assert.deepEqual(curatedKlipyEntryProblems(withMedia({thumbUrl: `${MEDIA}/preview.gif`})), []);
    assert.deepEqual(curatedKlipyEntryProblems(withMedia({aspectRatio: null})), []);
    assert.deepEqual(curatedKlipyEntryProblems(withCredit({sourceUrl: null})), []);
    assert.deepEqual(curatedKlipyEntryProblems(klipyEntry(undefined, {calibrationEligible: false})), []);
    assert.deepEqual(curatedKlipyEntryProblems(klipyEntry(undefined, {caption: "Oh, really?"})), []);
    assert.deepEqual(curatedEntryProblems(klipyEntry()), []);
  });

  it("names every way an entry can be wrong", () => {
    const cases = [
      [klipyEntry("12ab"), ["klipyId"]],
      [klipyEntry(undefined, {klipyId: undefined}), ["klipyId"]],
      [klipyEntry(undefined, {contentId: "hc_gif_1000000000000001"}), ["contentId"]],
      [klipyEntry(undefined, {slot: "anchor_wit"}), ["slot"]],
      [klipyEntry(undefined, {calibrationEligible: "yes"}), ["calibrationEligible"]],
      [klipyEntry(undefined, {category: "slapstick"}), ["category"]],
      [klipyEntry(undefined, {humorVector: {}}), ["humorVector"]],
      [klipyEntry(undefined, {humorVector: {sarcasm: 1.2}}), ["humorVector"]],
      [klipyEntry(undefined, {humorVector: {slapstick: 0.5}}), ["humorVector"]],
      [klipyEntry(undefined, {language: "de"}), ["language"]],
      [klipyEntry(undefined, {caption: "   "}), ["caption"]],
      [klipyEntry(undefined, {caption: "x".repeat(201)}), ["caption"]],
      // media: the MP4
      [withMedia({downloadUrl: ""}), ["media.downloadUrl"]],
      [withMedia({downloadUrl: "http://static.klipy.com/ii/a/b/c/video.mp4"}), ["media.downloadUrl"]],
      [withMedia({downloadUrl: `${MEDIA}/preview.webp`}), ["media.downloadUrl"]],
      [withMedia({downloadUrl: "https://static.klipy.com.evil.tld/ii/a/video.mp4"}), ["media.downloadUrl"]],
      // A URL the general allowlist accepts is still wrong for a KLIPY clip.
      [withMedia({downloadUrl: "https://media1.giphy.com/media/abc/giphy.mp4"}), ["media.downloadUrl"]],
      [withMedia({downloadUrl: "https://firebasestorage.googleapis.com/v0/b/x/o/video.mp4"}), ["media.downloadUrl"]],
      // media: the poster
      [withMedia({thumbUrl: undefined}), ["media.thumbUrl"]],
      [withMedia({thumbUrl: ""}), ["media.thumbUrl"]],
      [withMedia({thumbUrl: "https://evil.example/preview.webp"}), ["media.thumbUrl"]],
      [withMedia({thumbUrl: "https://media1.giphy.com/media/abc/200_s.gif"}), ["media.thumbUrl"]],
      [withMedia({thumbUrl: `${MEDIA}/video.mp4`}), ["media.thumbUrl"]],
      [withMedia({thumbUrl: "https://static.klipy.com/ii/another-clip/aa/bb/preview.webp"}), ["media.thumbUrl-not-this-item"]],
      [withMedia({thumbUrl: "https://static1.klipy.com/ii/0123456789abcdef0123456789abcdef/aa/bb/preview.webp"}), ["media.thumbUrl-not-this-item"]],
      [withMedia({aspectRatio: 0}), ["media.aspectRatio"]],
      [withMedia({aspectRatio: "2"}), ["media.aspectRatio"]],
      [withMedia({durationMs: 0}), ["media.durationMs"]],
      [withMedia({durationMs: 2.5}), ["media.durationMs"]],
      [withMedia({durationMs: "2460"}), ["media.durationMs"]],
      [withMedia({durationMs: MAX_CURATED_VIDEO_DURATION_MS + 1}), ["media.durationMs"]],
      [withMedia({durationMs: undefined}), ["media.durationMs"]],
      // credit: KLIPY's, and no invented uploader
      [klipyEntry(undefined, {attribution: null}), ["attribution"]],
      [withCredit({provider: "giphy"}), ["attribution"]],
      [withCredit({username: "someone"}), ["attribution"]],
      [withCredit({displayName: "Some One"}), ["attribution"]],
      [withCredit({verified: true}), ["attribution"]],
      [withCredit({sourceUrl: "http://klipy.com/clips/x"}), ["attribution.sourceUrl"]],
      [withCredit({sourceUrl: "https://klipy.com.evil.tld/clips/x"}), ["attribution.sourceUrl"]],
      [withCredit({sourceUrl: "https://giphy.com/gifs/x"}), ["attribution.sourceUrl"]],
      [withCredit({sourceUrl: "not a url"}), ["attribution.sourceUrl"]],
      [klipyEntry(undefined, {sourceTrust: "provider"}), ["sourceTrust"]],
    ];
    for (const [entry, expected] of cases) {
      assert.deepEqual(curatedKlipyEntryProblems(entry), expected, JSON.stringify(entry));
    }
  });

  it("is checked by its own provider's rules, and a GIPHY entry by GIPHY's", () => {
    // The dispatcher never lets one provider's entry pass as the other's.
    const giphy = CURATED_GIPHY_CATALOG[0];
    assert.deepEqual(curatedEntryProblems(giphy), curatedGiphyEntryProblems(giphy));
    assert.deepEqual(curatedEntryProblems(giphy), []);
    const klipyMediaOnGiphyEntry = {...giphy, media: {...giphy.media, downloadUrl: `${MEDIA}/video.mp4`}};
    assert.ok(curatedEntryProblems(klipyMediaOnGiphyEntry).includes("media.downloadUrl-not-this-item"));
    assert.ok(curatedEntryProblems(klipyEntry(undefined, {attribution: giphy.attribution})).includes("attribution"));
  });

  it("is written as an approved, curated video card with KLIPY's credit", () => {
    const entry = klipyEntry();
    assert.deepEqual(curatedKlipyUpsertInput(entry), {
      contentId: "hc_klipy_1000000000000001",
      type: "video",
      language: "en",
      category: "sarcasm",
      humorTags: [],
      humorVector: {sarcasm: 0.85, dry: 0.4},
      media: {
        downloadUrl: `${MEDIA}/video.mp4`,
        thumbUrl: `${MEDIA}/preview.webp`,
        durationMs: 2460,
        aspectRatio: 2.388,
        textBody: null,
      },
      safetyStatus: "approved",
      active: true,
      sourceType: "licensed_api",
      provider: "klipy",
      licenseRef: "https://klipy.com/clips/fixture-clip",
      calibration: {eligible: true, slot: null, version: HUMOR_CALIBRATION_VERSION},
      sourceTrust: "curated",
      curatedCatalogEntry: true,
      attribution: entry.attribution,
      sourceId: "1000000000000001",
      sourceUrl: "https://klipy.com/clips/fixture-clip",
    });
    assert.deepEqual(curatedUpsertInput(entry), curatedKlipyUpsertInput(entry));
    assert.deepEqual(
      curatedKlipyUpsertInput(klipyEntry(undefined, {calibrationEligible: false})).calibration,
      {eligible: false},
    );
  });
});

describe("the GIPHY catalogue is untouched by the video support", () => {
  // sha256 of the 36 GIPHY upserts as `curatedGiphyUpsertInput` wrote them on
  // main before KLIPY support existed (a8e8d522). A change here means a GIF
  // would be seeded differently — which this work must never cause.
  const GIPHY_UPSERTS_SHA256 = "ff14f5b8eb04d70d866877ea965ea114a02df6fe3b799a727f7f9ca347eafba1";
  const digest = (value) => crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");

  it("still holds the same 36 GIFs, written exactly as before", () => {
    assert.equal(CURATED_GIPHY_CATALOG.length, 36);
    const viaGiphy = CURATED_GIPHY_CATALOG.map(curatedGiphyUpsertInput);
    assert.equal(digest(viaGiphy), GIPHY_UPSERTS_SHA256);
    // …and the provider-aware path writes those same 36, in the same order.
    assert.deepEqual(CURATED_GIPHY_CATALOG.map(curatedUpsertInput), viaGiphy);
    const planned = calibrationCatalogPlan().items.filter((item) => item.contentId.startsWith("hc_gif_"));
    assert.deepEqual(planned, viaGiphy);
    assert.ok(viaGiphy.every((item) => item.type === "meme" && item.media.durationMs === null));
  });

  it("is the first part of the whole catalogue, followed by the KLIPY clips", () => {
    assert.deepEqual(CURATED_CATALOG.slice(0, 36), [...CURATED_GIPHY_CATALOG]);
    assert.deepEqual(CURATED_CATALOG.slice(36), [...CURATED_KLIPY_CATALOG]);
    assert.equal(CALIBRATION_SEED.length, CURATED_CATALOG.length);
    assert.deepEqual(
      CALIBRATION_SEED.slice(0, 36).map(({calibration: _c, ...rest}) => rest),
      CURATED_GIPHY_CATALOG.map(curatedGiphyUpsertInput).map(({calibration: _c, ...rest}) => rest),
    );
  });

  it("holds only well-formed KLIPY clips with distinct ids and media", () => {
    for (const entry of CURATED_KLIPY_CATALOG) {
      assert.deepEqual(curatedKlipyEntryProblems(entry), [], entry.contentId);
      assert.equal(entry.calibrationEligible, true, entry.contentId);
      assert.equal(entry.caption, null, "the joke is in the clip; no caption is written");
    }
    const ids = CURATED_CATALOG.map((entry) => entry.contentId);
    assert.equal(new Set(ids).size, ids.length, "duplicate contentId");
    const media = CURATED_KLIPY_CATALOG.map((entry) => entry.media.downloadUrl);
    assert.equal(new Set(media).size, media.length, "two entries share one MP4");
  });
});

describe("seeding a mixed catalogue", () => {
  const mixed = () => [...CURATED_GIPHY_CATALOG, klipyEntry("1000000000000001"), klipyEntry("1000000000000002", {
    category: "absurd",
    humorVector: {absurd: 0.9},
    media: {downloadUrl: "https://static.klipy.com/ii/ffff/cc/dd/v.mp4", thumbUrl: null, aspectRatio: 1.778, durationMs: null},
  })];

  it("plans the GIFs and the clips, and looks for a synced twin of GIFs only", () => {
    const plan = calibrationCatalogPlan("curated_giphy", mixed());
    assert.equal(plan.items.length, 38);
    assert.deepEqual(plan.items.slice(36).map((item) => [item.contentId, item.type, item.provider]), [
      ["hc_klipy_1000000000000001", "video", "klipy"],
      ["hc_klipy_1000000000000002", "video", "klipy"],
    ]);
    assert.equal(plan.retire.filter((r) => r.reason === "superseded-by-curated").length, 36);
    assert.ok(plan.retire.every((r) => !/klipy/i.test(r.contentId)));
  });

  it("refuses a malformed clip, naming it as a KLIPY problem", () => {
    assert.throws(
      () => calibrationCatalogPlan("curated_giphy", [...CURATED_GIPHY_CATALOG, withMedia({downloadUrl: "https://evil.example/v.mp4"})]),
      /^Error: curated-klipy-catalog-invalid: hc_klipy_1000000000000001 \(media\.downloadUrl\)$/,
    );
    assert.throws(
      () => calibrationCatalogPlan("curated_giphy", [klipyEntry(), klipyEntry()]),
      /duplicate contentId/,
    );
    const brokenGif = {...CURATED_GIPHY_CATALOG[0], category: "slapstick"};
    assert.throws(
      () => calibrationCatalogPlan("curated_giphy", [brokenGif, withMedia({downloadUrl: ""})]),
      /^Error: curated-giphy-catalog-invalid: /,
    );
  });

  it("writes a clip as a servable video card and retires it when it leaves the catalogue", async () => {
    const db = createFakeFirestore();
    const first = await seedCalibrationCatalog(db, {catalog: mixed()});
    assert.equal(first.written, 38);
    assert.equal(first.created, 38);

    const stored = db.read("humorContent/hc_klipy_1000000000000001");
    assert.equal(stored.type, "video");
    assert.equal(stored.active, true);
    assert.equal(stored.safetyStatus, "approved");
    assert.equal(stored.sourceTrust, "curated");
    assert.deepEqual(stored.source, {type: "licensed_api", provider: "klipy", licenseRef: "https://klipy.com/clips/fixture-clip"});
    assert.equal(stored.sourceId, "1000000000000001");
    assert.equal(stored.calibrationEligible, true);
    assert.equal(stored.calibrationSlot, null);
    assert.deepEqual(stored.media, {
      storagePath: null,
      downloadUrl: `${MEDIA}/video.mp4`,
      thumbUrl: `${MEDIA}/preview.webp`,
      durationMs: 2460,
      aspectRatio: 2.388,
      textBody: null,
    });

    // What a member's app receives: a video, credited to KLIPY alone.
    const card = toFeedSafeContent(parseHumorContent("hc_klipy_1000000000000001", stored));
    assert.equal(card.type, "video");
    assert.equal(card.media.downloadUrl, `${MEDIA}/video.mp4`);
    assert.equal(card.media.durationMs, 2460);
    assert.deepEqual(card.attribution, {
      provider: "klipy",
      displayName: null,
      username: null,
      sourceUrl: "https://klipy.com/clips/fixture-clip",
      verified: false,
    });
    // A clip without a poster or a measured duration is still a whole card.
    const bare = db.read("humorContent/hc_klipy_1000000000000002");
    assert.equal(bare.media.thumbUrl, null);
    assert.equal(bare.media.durationMs, null);

    // The GIFs next to it are what they always were.
    const gif = db.read(`humorContent/${CURATED_GIPHY_CATALOG[0].contentId}`);
    assert.equal(gif.type, "meme");
    assert.equal(gif.source.provider, "giphy");

    const again = await seedCalibrationCatalog(db, {catalog: mixed()});
    assert.equal(again.refreshed, 38);
    assert.equal(again.retired, 0);

    const without = await seedCalibrationCatalog(db, {catalog: mixed().slice(0, 37)});
    assert.deepEqual(without.retiredIds, ["hc_klipy_1000000000000002"]);
    const retired = db.read("humorContent/hc_klipy_1000000000000002");
    assert.equal(retired.active, false);
    assert.equal(retired.retiredReason, "removed-from-curated-catalog");
  });
});

describe("Core sequence with a mixed catalogue", () => {
  const catalog = [...CURATED_GIPHY_CATALOG, klipyEntry("1000000000000001"), klipyEntry("1000000000000002")];
  const live = (id) => ({id, active: true});

  it("accepts KLIPY clips appended after the GIFs", () => {
    const sequence = [...HUMOR_CORE_SEQUENCE.slice(0, 36), live("hc_klipy_1000000000000001"), live("hc_klipy_1000000000000002")];
    assert.deepEqual(humorCoreSequenceProblems(sequence, catalog), []);
  });

  it("refuses a clip that is not in the curated catalogue, or not curated", () => {
    const sequence = [...HUMOR_CORE_SEQUENCE.slice(0, 36), live("hc_klipy_1000000000000009")];
    assert.deepEqual(humorCoreSequenceProblems(sequence, catalog), [
      "V37 hc_klipy_1000000000000009: not in the curated catalogue",
    ]);
    const notEligible = [...CURATED_GIPHY_CATALOG, klipyEntry("1000000000000001", {calibrationEligible: false})];
    assert.deepEqual(
      humorCoreSequenceProblems([...HUMOR_CORE_SEQUENCE.slice(0, 36), live("hc_klipy_1000000000000001")], notEligible),
      ["V37 hc_klipy_1000000000000001: not curated"],
    );
    assert.deepEqual(
      humorCoreSequenceProblems(
        [...HUMOR_CORE_SEQUENCE.slice(0, 36), live("hc_klipy_1000000000000001"), live("hc_klipy_1000000000000001")],
        catalog,
      ),
      ["V38 hc_klipy_1000000000000001: duplicate of V37"],
    );
  });

  it("keeps V1–V36 the GIFs they were, with every shipped KLIPY clip after them", () => {
    assert.ok(HUMOR_CORE_SEQUENCE.slice(0, 36).every((entry) => entry.id.startsWith("hc_gif_")));
    assert.deepEqual(humorCoreSequenceProblems(), []);
    const shipped = HUMOR_CORE_SEQUENCE.slice(36).map((entry) => entry.id);
    assert.deepEqual(shipped, CURATED_KLIPY_CATALOG.map((entry) => entry.contentId));
  });
});
