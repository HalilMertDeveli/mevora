const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {FIXTURES, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");

const {
  ACTIVE_CALIBRATION_CATALOG,
  CALIBRATION_SEED,
  CURATED_GIPHY_CATALOG,
  CURATED_GIPHY_ID_PREFIX,
  curatedGiphyContentId,
  giphyStableStillUrl,
  giphyStableWebpUrl,
} = require("../lib/humor/calibrationSeed.js");
const {
  TEXT_JOKE_CONTENT_IDS,
  calibrationCatalogPlan,
  curatedGiphyEntryProblems,
  curatedGiphyUpsertInput,
  seedCalibrationCatalog,
} = require("../lib/humor/calibrationCatalog.js");
const {
  listCalibrationPool,
  parseHumorContent,
  toFeedSafeContent,
  upsertHumorContentDoc,
} = require("../lib/humor/contentRepository.js");
const {buildCalibrationPoolReport} = require("../lib/humor/calibrationPoolReport.js");
const {HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
const {GiphyHumorSource, GIPHY_QUERY_FAMILIES} = require("../lib/humor/giphySource.js");
const {syncHumorFromGiphy} = require("../lib/humor/ingest.js");

/**
 * The curated GIPHY catalogue: every Humor card — calibration included — is a
 * GIF Mevora hand-picked. Phase 1 ships the format, the validation and the
 * seeding/retirement path with an empty catalogue; these tests drive that
 * path with a fixture catalogue shaped exactly like the real one will be.
 */

/** A well-formed curated entry for a fake GIPHY id. */
function entry(giphyId, overrides = {}) {
  return {
    contentId: curatedGiphyContentId(giphyId),
    giphyId,
    slot: "anchor_wit",
    calibrationEligible: true,
    category: "sarcasm",
    humorTags: ["sitcom"],
    humorVector: {sarcasm: 0.88, dry: 0.4},
    language: "en",
    caption: "Oh Really",
    media: {
      downloadUrl: giphyStableWebpUrl(giphyId),
      thumbUrl: `https://media2.giphy.com/media/${giphyId}/200_s.gif`,
      aspectRatio: 1.78,
    },
    attribution: {
      provider: "giphy",
      displayName: "The Office",
      username: "theoffice",
      sourceUrl: `https://giphy.com/gifs/theoffice-oh-really-${giphyId}`,
      verified: true,
    },
    sourceTrust: "curated",
    ...overrides,
  };
}

/**
 * A full fixture catalogue with the text catalogue's exact pool shape: the
 * same slots, categories and vectors, each on its own fake GIPHY clip.
 */
function fullFixtureCatalog() {
  return CALIBRATION_SEED.map((item, index) =>
    entry(`FxClip${String(index).padStart(3, "0")}`, {
      slot: item.calibration.slot ?? undefined,
      category: item.category,
      humorVector: item.humorVector,
      language: item.language === "en" ? "en" : "tr",
    }),
  );
}

async function seededTextDb() {
  const db = createFakeFirestore({});
  await seedCalibrationCatalog(db, {kind: "text_jokes"});
  return db;
}

describe("curated GIPHY catalogue format", () => {
  it("phase 1: calibration still runs on the text catalogue, GIPHY catalogue empty", () => {
    assert.equal(ACTIVE_CALIBRATION_CATALOG, "text_jokes");
    assert.deepEqual([...CURATED_GIPHY_CATALOG], []);
    assert.equal(TEXT_JOKE_CONTENT_IDS.length, 36);
  });

  it("derives ids and stable media URLs from the GIPHY id", () => {
    assert.equal(curatedGiphyContentId("AbCd1234"), "hc_gif_AbCd1234");
    assert.ok(curatedGiphyContentId("x").startsWith(CURATED_GIPHY_ID_PREFIX));
    assert.equal(giphyStableWebpUrl("AbCd1234"), "https://media.giphy.com/media/AbCd1234/giphy.webp");
    assert.equal(giphyStableStillUrl("AbCd1234"), "https://media.giphy.com/media/AbCd1234/giphy_s.gif");
  });

  it("accepts a well-formed entry", () => {
    assert.deepEqual(curatedGiphyEntryProblems(entry("AbCd1234")), []);
    assert.deepEqual(curatedGiphyEntryProblems(entry("AbCd1234", {caption: null, slot: undefined})), []);
    for (const item of fullFixtureCatalog()) {
      assert.deepEqual(curatedGiphyEntryProblems(item), [], item.contentId);
    }
  });

  it("rejects entries that are not one exact, credited GIPHY item", () => {
    const cases = [
      [{giphyId: "bad id!"}, "giphyId"],
      [{contentId: "hc_gif_Other123"}, "contentId"],
      [{slot: "anchor_wtt"}, "slot"],
      [{calibrationEligible: false}, "slot-without-eligibility"],
      [{category: "slapstick"}, "category"],
      [{humorVector: {}}, "humorVector"],
      [{humorVector: {sarcasm: 1.4}}, "humorVector"],
      [{language: "de"}, "language"],
      [{caption: ""}, "caption"],
      [{caption: "x".repeat(201)}, "caption"],
      // Media must be this item's own rendition, on GIPHY's CDN, over https.
      [{media: {...entry("AbCd1234").media, downloadUrl: giphyStableWebpUrl("Zzzz9999")}}, "media.downloadUrl-not-this-item"],
      [{media: {...entry("AbCd1234").media, thumbUrl: "https://picsum.photos/AbCd1234/1.jpg"}}, "media.thumbUrl"],
      [{media: {...entry("AbCd1234").media, downloadUrl: "http://media.giphy.com/media/AbCd1234/giphy.webp"}}, "media.downloadUrl"],
      [{media: {...entry("AbCd1234").media, aspectRatio: 0}}, "media.aspectRatio"],
      [{attribution: {...entry("AbCd1234").attribution, provider: "tenor"}}, "attribution"],
      [{attribution: {...entry("AbCd1234").attribution, sourceUrl: "https://evil.example/AbCd1234"}}, "attribution.sourceUrl"],
      [{sourceTrust: "provider"}, "sourceTrust"],
    ];
    for (const [overrides, expected] of cases) {
      const problems = curatedGiphyEntryProblems(entry("AbCd1234", overrides));
      assert.ok(problems.includes(expected), `${JSON.stringify(overrides)} → ${problems}`);
    }
  });

  it("maps an entry to a curated, credited, provider-sourced GIF upsert", () => {
    const input = curatedGiphyUpsertInput(entry("AbCd1234"));
    assert.equal(input.type, "meme");
    assert.equal(input.sourceType, "licensed_api");
    assert.equal(input.provider, "giphy");
    assert.equal(input.sourceTrust, "curated");
    assert.equal(input.curatedCatalogEntry, true);
    assert.equal(input.media.textBody, "Oh Really", "caption is GIPHY's own title");
    assert.equal(input.media.durationMs, null);
    assert.deepEqual(input.calibration, {
      eligible: true,
      slot: "anchor_wit",
      version: HUMOR_CALIBRATION_VERSION,
    });
    assert.deepEqual(
      curatedGiphyUpsertInput(entry("AbCd1234", {calibrationEligible: false, slot: undefined})).calibration,
      {eligible: false},
    );
  });

  it("refuses to plan an invalid or duplicated catalogue", () => {
    assert.throws(
      () => calibrationCatalogPlan("curated_giphy", [entry("AbCd1234", {sourceTrust: "provider"})]),
      /curated-giphy-catalog-invalid: hc_gif_AbCd1234 \(sourceTrust\)/,
    );
    assert.throws(
      () => calibrationCatalogPlan("curated_giphy", [entry("AbCd1234"), entry("AbCd1234")]),
      /duplicate contentId/,
    );
  });
});

describe("seeding the curated GIPHY catalogue", () => {
  it("writes curated GIFs that keep their credit and serve in calibration", async () => {
    const db = await seededTextDb();
    const catalog = fullFixtureCatalog();
    const result = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});
    assert.equal(result.kind, "curated_giphy");
    assert.equal(result.written, 36);
    assert.equal(result.created, 36);

    const stored = db.read("humorContent/hc_gif_FxClip000");
    assert.equal(stored.type, "meme");
    assert.equal(stored.sourceTrust, "curated");
    assert.deepEqual(stored.source, {type: "licensed_api", provider: "giphy", licenseRef: catalog[0].attribution.sourceUrl});
    assert.equal(stored.sourceId, "FxClip000");
    assert.equal(stored.calibrationEligible, true);
    assert.equal(stored.calibrationSlot, catalog[0].slot);
    assert.equal(stored.calibrationVersion, HUMOR_CALIBRATION_VERSION);
    assert.equal(stored.media.downloadUrl, giphyStableWebpUrl("FxClip000"));
    assert.equal(stored.media.thumbUrl, catalog[0].media.thumbUrl);
    assert.equal(stored.media.textBody, "Oh Really");
    assert.deepEqual(stored.attribution, catalog[0].attribution);

    // K1: the card credits GIPHY's uploader.
    const card = toFeedSafeContent(parseHumorContent("hc_gif_FxClip000", stored));
    assert.deepEqual(card.attribution, catalog[0].attribution);
    assert.equal(card.type, "meme");

    // The calibration pool is now GIFs only, and as healthy as the text one was.
    const pool = await listCalibrationPool(db, {calibrationVersion: HUMOR_CALIBRATION_VERSION, limit: 200});
    assert.equal(pool.length, 36);
    assert.ok(pool.every((item) => item.contentId.startsWith("hc_gif_") && item.type === "meme"));
    const report = await buildCalibrationPoolReport(db);
    assert.equal(report.healthy, true, report.warnings.join("; "));
  });

  it("retires every text-joke card — deactivated and un-curated, never deleted", async () => {
    const db = await seededTextDb();
    const result = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog: fullFixtureCatalog()});
    assert.equal(result.retired, 36);
    for (const id of TEXT_JOKE_CONTENT_IDS) {
      const doc = db.read(`humorContent/${id}`);
      assert.ok(doc, `${id} was deleted`);
      assert.equal(doc.active, false, id);
      assert.equal(doc.calibrationEligible, false, id);
      assert.equal(doc.calibrationSlot, null, id);
      assert.equal(doc.retiredReason, "text-joke-catalog-retired", id);
      assert.equal(doc.type, "text", "the text itself is left alone");
    }
  });

  it("is idempotent: a second run retires nothing new and creates nothing", async () => {
    const db = await seededTextDb();
    const catalog = fullFixtureCatalog();
    await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});
    const snapshot = db.paths();
    const again = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});
    assert.equal(again.created, 0);
    assert.equal(again.refreshed, 36);
    assert.equal(again.retired, 0);
    assert.deepEqual(db.paths(), snapshot);
  });

  it("retires the ordinary sync copy of a curated clip", async () => {
    const db = await seededTextDb();
    db._store.set("humorContent/ext_giphy_FxClip001", {
      type: "meme",
      category: "meme",
      active: true,
      safetyStatus: "approved",
      calibrationEligible: false,
      source: {type: "licensed_api", provider: "giphy"},
      sourceTrust: "provider",
    });
    const result = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog: fullFixtureCatalog()});
    assert.ok(result.retiredIds.includes("ext_giphy_FxClip001"));
    const doc = db.read("humorContent/ext_giphy_FxClip001");
    assert.equal(doc.active, false);
    assert.equal(doc.retiredReason, "superseded-by-curated");
  });

  it("retires a clip dropped from the catalogue, and a revert brings the text back", async () => {
    const db = await seededTextDb();
    const catalog = fullFixtureCatalog();
    await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});

    const dropped = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog: catalog.slice(1)});
    assert.deepEqual(dropped.retiredIds, ["hc_gif_FxClip000"]);
    assert.equal(db.read("humorContent/hc_gif_FxClip000").retiredReason, "removed-from-curated-catalog");

    const reverted = await seedCalibrationCatalog(db, {kind: "text_jokes"});
    assert.equal(reverted.retired, 35, "every remaining curated GIF leaves calibration");
    const text = db.read(`humorContent/${TEXT_JOKE_CONTENT_IDS[0]}`);
    assert.equal(text.active, true);
    assert.equal(text.calibrationEligible, true);
    assert.equal(text.retiredReason, null);
    const pool = await listCalibrationPool(db, {calibrationVersion: HUMOR_CALIBRATION_VERSION, limit: 200});
    assert.ok(pool.every((item) => !item.contentId.startsWith("hc_gif_")));
  });

  it("the text catalogue seeds exactly as before", async () => {
    const db = createFakeFirestore({});
    const result = await seedCalibrationCatalog(db);
    assert.equal(result.kind, "text_jokes");
    assert.equal(result.written, 36);
    assert.equal(result.retired, 0);
    const report = await buildCalibrationPoolReport(db);
    assert.equal(report.healthy, true, report.warnings.join("; "));
  });
});

describe("curated vs. ordinary provider items", () => {
  const base = {
    contentId: "hc_gif_Claim123",
    type: "meme",
    language: "en",
    category: "meme",
    humorVector: {meme: 0.9},
    media: {downloadUrl: "https://media.giphy.com/media/Claim123/giphy.webp"},
    safetyStatus: "approved",
    active: true,
    sourceType: "licensed_api",
    provider: "giphy",
    sourceTrust: "curated",
  };

  it("only the curated-catalogue path may keep the curated tier", async () => {
    const db = createFakeFirestore({});
    await upsertHumorContentDoc(db, base);
    assert.equal(db.read("humorContent/hc_gif_Claim123").sourceTrust, "provider");
    await upsertHumorContentDoc(db, {...base, curatedCatalogEntry: true});
    assert.equal(db.read("humorContent/hc_gif_Claim123").sourceTrust, "curated");
  });

  it("provider sync never re-ingests a curated clip as ext_giphy_*", async () => {
    const family = GIPHY_QUERY_FAMILIES.find((f) => f.query === "komik tepki");
    const fake = fakeGiphyFetch({gifsByQuery: {"*": [FIXTURES.turkishReaction, FIXTURES.sitcomReaction]}});
    const db = createFakeFirestore({});
    const result = await syncHumorFromGiphy({
      db,
      source: new GiphyHumorSource("fixture-key", {fetchImpl: fake.fetchImpl}),
      probe: false,
      rotation: GIPHY_QUERY_FAMILIES.filter((f) => f.language === "tr").indexOf(family),
      queryCount: 1,
      curatedGiphyIds: new Set(["trReact01"]),
      log: () => {},
    });
    assert.equal(db.has("humorContent/ext_giphy_trReact01"), false);
    assert.equal(db.has("humorContent/ext_giphy_sitcom01"), true);
    assert.equal(result.accepted, 1);
    assert.ok(result.duplicates >= 1);
  });
});
