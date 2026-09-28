const {describe, it} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {FIXTURES, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");

const {
  ACTIVE_CALIBRATION_CATALOG,
  ANCHOR_POOL_TARGET,
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
const {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} = require("../lib/humor/calibration.js");
const {HUMOR_CATEGORIES} = require("../lib/humor/categories.js");
const {GiphyHumorSource, GIPHY_QUERY_FAMILIES} = require("../lib/humor/giphySource.js");
const {syncHumorFromGiphy} = require("../lib/humor/ingest.js");

/**
 * The curated GIPHY catalogue: every Humor card — calibration included — is a
 * GIF Mevora hand-picked. The real catalogue is checked as data; the seeding
 * and retirement path is driven with a fixture catalogue of the same shape on
 * fake GIPHY ids, and with the real one.
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
 * A full fixture catalogue with the real catalogue's exact pool shape: the
 * same slots, categories and vectors, each on its own fake GIPHY clip.
 */
function fullFixtureCatalog() {
  return CURATED_GIPHY_CATALOG.map((item, index) =>
    entry(`FxClip${String(index).padStart(3, "0")}`, {
      slot: item.slot,
      category: item.category,
      humorVector: item.humorVector,
      language: item.language,
    }),
  );
}

/**
 * A database as the retired text catalogue left it: 36 active, calibration-
 * eligible text cards written by the old seeder.
 */
async function seededTextDb() {
  const db = createFakeFirestore({});
  for (const contentId of TEXT_JOKE_CONTENT_IDS) {
    await upsertHumorContentDoc(db, {
      contentId,
      type: "text",
      language: "tr",
      category: "dry",
      humorVector: {dry: 0.8},
      media: {textBody: "Evet. Güzel. Devam edelim."},
      safetyStatus: "approved",
      active: true,
      sourceType: "internal",
      provider: "mevora-qa-seed",
      calibration: {eligible: true, slot: null, version: HUMOR_CALIBRATION_VERSION},
    });
  }
  return db;
}

describe("curated GIPHY catalogue format", () => {
  it("calibration runs on the curated GIPHY catalogue; the text cards are retired", () => {
    assert.equal(ACTIVE_CALIBRATION_CATALOG, "curated_giphy");
    assert.equal(TEXT_JOKE_CONTENT_IDS.length, 36);
    const plan = calibrationCatalogPlan();
    assert.equal(plan.kind, "curated_giphy");
    assert.equal(plan.items.length, CURATED_GIPHY_CATALOG.length);
    const retired = new Set(plan.retire.map((r) => r.contentId));
    for (const id of TEXT_JOKE_CONTENT_IDS) assert.ok(retired.has(id), id);
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

describe("the real curated GIPHY catalogue", () => {
  it("every entry is well-formed", () => {
    for (const item of CURATED_GIPHY_CATALOG) {
      assert.deepEqual(curatedGiphyEntryProblems(item), [], item.contentId);
    }
  });

  it("holds 36 unique clips: 4 anchors per slot and a 12-clip open pool", () => {
    assert.equal(CURATED_GIPHY_CATALOG.length, 36);
    const ids = CURATED_GIPHY_CATALOG.map((e) => e.contentId);
    assert.equal(new Set(ids).size, 36, "duplicate contentId");
    assert.equal(new Set(CURATED_GIPHY_CATALOG.map((e) => e.giphyId)).size, 36, "duplicate clip");
    const anchors = CURATED_GIPHY_CATALOG.filter((e) => e.slot !== undefined);
    assert.equal(anchors.length, 24);
    for (const slot of ANCHOR_SLOTS) {
      const candidates = anchors.filter((e) => e.slot === slot.id);
      assert.equal(candidates.length, ANCHOR_POOL_TARGET, slot.id);
      for (const candidate of candidates) {
        assert.equal(candidate.category, slot.primary, candidate.contentId);
      }
    }
    // Open pool, mirroring the text catalogue: calibration content, no slot.
    const open = CURATED_GIPHY_CATALOG.filter((e) => e.slot === undefined);
    assert.equal(open.length, 12);
    for (const item of open) {
      assert.equal(item.calibrationEligible, true, item.contentId);
      assert.equal(Object.hasOwn(item, "slot"), false, item.contentId);
    }
    assert.ok(CURATED_GIPHY_CATALOG.every((e) => e.calibrationEligible === true));
  });

  it("represents all 11 humor categories, each as some clip's primary", () => {
    const categories = new Set(CURATED_GIPHY_CATALOG.map((e) => e.category));
    assert.deepEqual([...categories].sort(), [...HUMOR_CATEGORIES].sort());
    for (const item of CURATED_GIPHY_CATALOG) {
      const [top] = Object.entries(item.humorVector).sort((a, b) => b[1] - a[1]);
      assert.equal(top[0], item.category, `${item.contentId}: vector peaks on ${top[0]}`);
      assert.ok(top[1] >= 0.75 && top[1] <= 0.95, `${item.contentId}: primary ${top[1]}`);
      // Secondaries never reach coverage, so a clip measures one thing.
      for (const [dim, w] of Object.entries(item.humorVector)) {
        if (dim !== item.category) assert.ok(w < 0.5, `${item.contentId}: ${dim} ${w}`);
      }
    }
  });

  it("carries no caption: the joke is in the clip", () => {
    for (const item of CURATED_GIPHY_CATALOG) {
      assert.equal(item.caption, null, item.contentId);
      assert.equal(curatedGiphyUpsertInput(item).media.textBody, null, item.contentId);
    }
  });

  it("serves each clip's own rendition, poster and GIPHY credit", () => {
    for (const item of CURATED_GIPHY_CATALOG) {
      const media = new URL(item.media.downloadUrl);
      assert.ok(media.hostname.endsWith(".giphy.com"), item.contentId);
      assert.match(media.pathname, /\.(webp|gif)$/, item.contentId);
      assert.equal(item.media.thumbUrl, giphyStableStillUrl(item.giphyId), item.contentId);
      assert.ok(item.media.aspectRatio > 0.5 && item.media.aspectRatio < 2, item.contentId);
      assert.equal(item.attribution.provider, "giphy");
      assert.ok(item.attribution.sourceUrl.endsWith(item.giphyId), item.contentId);
      assert.equal(item.sourceTrust, "curated");
    }
  });

  it("marks exactly the Turkish broadcaster clips as Turkish", () => {
    for (const item of CURATED_GIPHY_CATALOG) {
      const turkish = ["trt_network", "showtv"].includes(item.attribution.username);
      assert.equal(item.language, turkish ? "tr" : "en", item.contentId);
    }
    assert.ok(CURATED_GIPHY_CATALOG.some((e) => e.language === "tr"));
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

  it("retires a clip dropped from the catalogue, and restoring it brings it back", async () => {
    const db = await seededTextDb();
    const catalog = fullFixtureCatalog();
    await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});

    const dropped = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog: catalog.slice(1)});
    assert.deepEqual(dropped.retiredIds, ["hc_gif_FxClip000"]);
    assert.equal(db.read("humorContent/hc_gif_FxClip000").retiredReason, "removed-from-curated-catalog");

    const restored = await seedCalibrationCatalog(db, {kind: "curated_giphy", catalog});
    assert.equal(restored.retired, 0);
    const clip = db.read("humorContent/hc_gif_FxClip000");
    assert.equal(clip.active, true);
    assert.equal(clip.calibrationEligible, true);
    assert.equal(clip.retiredReason, null);
    // The text cards stay retired throughout.
    const text = db.read(`humorContent/${TEXT_JOKE_CONTENT_IDS[0]}`);
    assert.equal(text.active, false);
    const pool = await listCalibrationPool(db, {calibrationVersion: HUMOR_CALIBRATION_VERSION, limit: 200});
    assert.equal(pool.length, 36);
    assert.ok(pool.every((item) => item.contentId.startsWith("hc_gif_")));
  });

  it("the default seed writes the real catalogue and retires the text cards", async () => {
    const db = await seededTextDb();
    const result = await seedCalibrationCatalog(db);
    assert.equal(result.kind, "curated_giphy");
    assert.equal(result.written, 36);
    assert.equal(result.created, 36);
    assert.equal(result.retired, 36);
    const pool = await listCalibrationPool(db, {calibrationVersion: HUMOR_CALIBRATION_VERSION, limit: 200});
    assert.equal(pool.length, 36);
    assert.ok(pool.every((item) => item.type === "meme" && item.media.textBody === null));
    const report = await buildCalibrationPoolReport(db);
    assert.equal(report.healthy, true, report.warnings.join("; "));
    assert.deepEqual(report.uncoveredDimensions, []);

    // On an empty database it seeds the same 36 and retires nothing.
    const fresh = createFakeFirestore({});
    const first = await seedCalibrationCatalog(fresh);
    assert.equal(first.written, 36);
    assert.equal(first.retired, 0);
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
