/**
 * GIPHY GIFs are silent short loops: they are ingested as animated images
 * ("meme" + animated WebP/GIF) that the client shows through Flutter's image
 * pipeline, not as MP4 "video" for a platform video player. Clips (real video
 * with sound) stay MP4 video. Legacy GIF-as-MP4 docs are migrated narrowly by
 * the provider sync.
 */
const {describe, it, afterEach} = require("node:test");
const assert = require("node:assert/strict");

const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {gif, clip, fakeGiphyFetch} = require("./helpers/giphyFixtures.cjs");

const {
  GIPHY_QUERY_FAMILIES,
  GiphyHumorSource,
  MAX_ORIGINAL_WEBP_BYTES,
  mapGiphyClip,
  mapGiphyGif,
  mediaPathKey,
  pickGifImageRendition,
} = require("../lib/humor/giphySource.js");
const {
  ingestHumorSourceItem,
  isLegacyGifVideoDoc,
  migrateLegacyGifVideoDoc,
  syncHumorFromGiphy,
} = require("../lib/humor/ingest.js");

const TR_FAMILY = GIPHY_QUERY_FAMILIES.find((f) => f.query === "komik tepki");
const CDN = "https://media1.giphy.com/media";

function images(id, options = {}) {
  return gif({id, title: "Funny Reaction GIF", imageOptions: options}).images;
}

function mapOk(fixture) {
  const outcome = mapGiphyGif(fixture, {language: "tr", family: TR_FAMILY});
  assert.equal(outcome.ok, true, `mapping failed: ${outcome.reason}`);
  return outcome.item;
}

// --------------------------------------------------------------------------
// Rendition policy
// --------------------------------------------------------------------------

describe("GIF animated-image rendition policy", () => {
  it("prefers original.webp when its webp_size is at most 1.5 MB", () => {
    assert.equal(MAX_ORIGINAL_WEBP_BYTES, 1_500_000);
    const pick = pickGifImageRendition(images("w1", {sizes: {original_webp: 1_500_000}}));
    assert.equal(pick.name, "original.webp");
    assert.equal(pick.url, `${CDN}/w1/giphy.webp`);
    assert.equal(pick.mimeHint, "image/webp");
    assert.equal(pick.sizeBytes, 1_500_000);
  });

  it("falls back to downsized_medium when the original WebP is too big or unsized", () => {
    for (const original_webp of [1_500_001, 6_000_000, null]) {
      const pick = pickGifImageRendition(images("w2", {sizes: {original_webp}}));
      assert.equal(pick.name, "downsized_medium", `original_webp=${original_webp}`);
      assert.equal(pick.url, `${CDN}/w2/giphy-downsized-medium.gif`);
      assert.equal(pick.mimeHint, "image/gif");
    }
  });

  it("then takes the wider of fixed_width.webp / fixed_height.webp", () => {
    const img = images("w3", {sizes: {original_webp: 4_000_000}});
    delete img.downsized_medium;
    let pick = pickGifImageRendition(img);
    assert.equal(pick.name, "fixed_height.webp", "356 px beats 200 px");
    assert.equal(pick.url, `${CDN}/w3/200.webp`);

    const wide = images("w3b", {sizes: {original_webp: 4_000_000}, dims: {fixed_width: [480, 270]}});
    delete wide.downsized_medium;
    pick = pickGifImageRendition(wide);
    assert.equal(pick.name, "fixed_width.webp");

    delete wide.fixed_width.webp;
    assert.equal(pickGifImageRendition(wide).name, "fixed_height.webp");
  });

  it("finally takes the smallest known WebP of any other rendition", () => {
    const img = images("w4", {sizes: {original_webp: 4_000_000}});
    delete img.downsized_medium;
    delete img.fixed_width.webp;
    delete img.fixed_height.webp;
    img.fixed_width_small = {
      url: `${CDN}/w4/100w.gif`,
      webp: `${CDN}/w4/100w.webp`,
      webp_size: "90000",
      width: "100",
      height: "56",
    };
    let pick = pickGifImageRendition(img);
    assert.equal(pick.name, "fixed_width_small.webp");
    assert.equal(pick.sizeBytes, 90_000);

    // Only the oversized original is left: still better than nothing.
    delete img.fixed_width_small;
    pick = pickGifImageRendition(img);
    assert.equal(pick.name, "original.webp");
  });

  it("only considers https URLs on allowed hosts", () => {
    const img = images("w5");
    img.original.webp = "http://media1.giphy.com/media/w5/giphy.webp";
    img.downsized_medium.url = "https://giphy.com.attacker.tld/media/w5/giphy-downsized-medium.gif";
    const pick = pickGifImageRendition(img);
    assert.equal(pick.name, "fixed_height.webp");
    assert.equal(pickGifImageRendition(null), null);
    assert.equal(pickGifImageRendition(images("w6", {http: true})), null);
    assert.equal(pickGifImageRendition(images("w7", {host: "giphy.com.attacker.tld"})), null);
  });
});

describe("GIF mapping", () => {
  it("maps a GIF to a meme with its animated WebP, own poster and aspect", () => {
    const item = mapOk(gif({id: "gm01", title: "Komik Tepki GIF", username: "someone"}));
    assert.equal(item.type, "meme");
    assert.equal(item.origin, "gif");
    assert.equal(item.media.downloadUrl, `${CDN}/gm01/giphy.webp`);
    assert.equal(item.media.mimeHint, "image/webp");
    assert.equal(item.media.thumbUrl, `${CDN}/gm01/200_s.gif`, "the still poster");
    assert.equal(item.media.aspectRatio, 480 / 270);
    assert.equal(item.media.durationMs, null);
    assert.equal(item.media.textBody, "Komik Tepki");
  });

  it("takes the aspect ratio from the chosen rendition", () => {
    const fixture = gif({
      id: "gm02",
      title: "Funny Reaction GIF",
      imageOptions: {sizes: {original_webp: 9_000_000}, dims: {downsized_medium: [300, 400]}},
    });
    const item = mapOk(fixture);
    assert.ok(item.media.downloadUrl.endsWith("/gm02/giphy-downsized-medium.gif"));
    assert.equal(item.media.mimeHint, "image/gif");
    assert.equal(item.media.aspectRatio, 300 / 400);
  });

  it("keeps a GIF whose only rendition is an MP4 as video", () => {
    const item = mapOk(gif({id: "gm03", title: "Funny Reaction GIF", imageOptions: {mp4Only: true}}));
    assert.equal(item.type, "video");
    assert.equal(item.media.mimeHint, "video/mp4");
    assert.ok(item.media.downloadUrl.endsWith("/gm03/giphy.mp4"));
    assert.equal(item.media.thumbUrl, `${CDN}/gm03/200_s.gif`);
  });

  it("records the GIF's own MP4 keys (never stored) for the legacy migration", () => {
    const item = mapOk(gif({id: "gm04", title: "Funny Reaction GIF"}));
    assert.deepEqual([...item.legacyVideoKeys].sort(), [
      "gm04/200.mp4",
      "gm04/200w.mp4",
      "gm04/giphy-downsized-small.mp4",
      "gm04/giphy.mp4",
    ]);
  });

  it("keeps Clips as MP4 video even though their GIF metadata has WebP", () => {
    const c = clip({id: "clipw01", title: "Awkward Reaction", username: "nbc", verified: true});
    const outcome = mapGiphyClip(c, {language: "en", family: TR_FAMILY});
    assert.equal(outcome.ok, true);
    assert.equal(outcome.item.type, "video");
    assert.equal(outcome.item.origin, "clip");
    assert.ok(outcome.item.media.downloadUrl.endsWith("/clipw01/480p.mp4"));
    assert.equal(outcome.item.media.mimeHint, "video/mp4");
    assert.equal(outcome.item.media.durationMs, 7500);
    assert.equal(outcome.item.legacyVideoKeys, undefined);
  });

  it("media keys ignore the CDN shard and the query string", () => {
    assert.equal(
      mediaPathKey("https://media3.giphy.com/media/v1.Y2lk/Abc123/giphy.mp4?cid=x&rid=giphy.mp4&ct=g"),
      "abc123/giphy.mp4",
    );
    assert.equal(mediaPathKey("http://media1.giphy.com/media/a/giphy.mp4"), null);
    assert.equal(mediaPathKey("https://evil.example/media/a/giphy.mp4"), null);
    assert.equal(mediaPathKey(null), null);
  });
});

// --------------------------------------------------------------------------
// Legacy GIF-as-MP4 migration
// --------------------------------------------------------------------------

const LEGACY_ID = "legacy01";
const fullGif = (id = LEGACY_ID) => gif({id, title: "Funny Reaction GIF", username: "someone"});
const legacyGif = (id = LEGACY_ID) =>
  gif({id, title: "Funny Reaction GIF", username: "someone", imageOptions: {mp4Only: true}});

/** A catalogue holding the GIF as the old ingest stored it: MP4 video. */
async function legacyCatalogue(patch = {}) {
  const db = createFakeFirestore({});
  const written = await ingestHumorSourceItem(db, mapOk(legacyGif()), "giphy", {probe: false});
  assert.equal(written.upserted, true);
  const path = `humorContent/${written.contentId}`;
  const stored = db.read(path);
  assert.equal(stored.type, "video");
  assert.ok(stored.media.downloadUrl.endsWith(`/${LEGACY_ID}/giphy.mp4`));
  db._store.set(path, {...stored, ...patch});
  return {db, path, contentId: written.contentId};
}

describe("legacy GIF-as-MP4 migration", () => {
  const originalFetch = globalThis.fetch;
  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  it("switches an approved, active GIF doc to the animated image: type + media only", async () => {
    const {db, path} = await legacyCatalogue({stats: {viewCount: 9, ratingCount: 4, avgRating: 0.5}});
    const before = db.read(path);

    const result = await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false});
    assert.deepEqual(result, {upserted: false, contentId: `ext_giphy_${LEGACY_ID}`, reason: "migrated"});

    const after = db.read(path);
    assert.equal(after.type, "meme");
    assert.equal(after.media.downloadUrl, `${CDN}/${LEGACY_ID}/giphy.webp`);
    assert.equal(after.media.aspectRatio, 480 / 270);
    // Everything else is exactly as it was.
    const strip = (doc) => {
      const {type, updatedAt, media, ...rest} = doc;
      const {downloadUrl, aspectRatio, ...mediaRest} = media;
      return {...rest, media: mediaRest};
    };
    assert.deepEqual(strip(after), strip(before));
    assert.equal(after.safetyStatus, "approved");
    assert.equal(after.active, true);
    assert.equal(after.calibrationEligible, false);
    assert.deepEqual(after.stats, {viewCount: 9, ratingCount: 4, avgRating: 0.5});
    assert.equal(after.media.thumbUrl, `${CDN}/${LEGACY_ID}/200_s.gif`);
  });

  it("is idempotent: a second fetch of the same GIF changes nothing", async () => {
    const {db, path} = await legacyCatalogue();
    await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false});
    const once = db.read(path);
    const again = await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false});
    assert.equal(again.reason, "duplicate");
    assert.deepEqual(db.read(path), once);
  });

  it("matches the stored MP4 across CDN shards and query strings", async () => {
    const {db, path} = await legacyCatalogue();
    const stored = db.read(path);
    db._store.set(path, {
      ...stored,
      media: {
        ...stored.media,
        downloadUrl: `https://media4.giphy.com/media/v1.Y2lkPTc5/${LEGACY_ID}/200.mp4?cid=abc&rid=200.mp4&ct=g`,
      },
    });
    const result = await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false});
    assert.equal(result.reason, "migrated");
    assert.equal(db.read(path).type, "meme");
  });

  for (const [label, patch, reason] of [
    ["rejected", {safetyStatus: "rejected", active: false}, "rejected"],
    ["approved but deactivated", {active: false}, "duplicate"],
    ["pending review", {safetyStatus: "pending", active: false}, "duplicate"],
    ["needs_review", {safetyStatus: "needs_review"}, "duplicate"],
  ]) {
    it(`never touches a ${label} doc, and never reactivates it`, async () => {
      const {db, path} = await legacyCatalogue(patch);
      const before = db.read(path);
      const result = await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false});
      assert.equal(result.upserted, false);
      assert.equal(result.reason, reason);
      assert.deepEqual(db.read(path), before);
    });
  }

  it("never touches a Clip doc, even when GIF search returns the same id", async () => {
    const db = createFakeFirestore({});
    const c = clip({id: "clipm01", title: "Funny Reaction", username: "nbc"});
    const clipItem = mapGiphyClip(c, {language: "tr", family: TR_FAMILY}).item;
    const written = await ingestHumorSourceItem(db, clipItem, "giphy", {probe: false});
    const path = `humorContent/${written.contentId}`;
    const before = db.read(path);
    assert.equal(before.type, "video");

    const twin = mapOk(gif({id: "clipm01", title: "Funny Reaction GIF", username: "nbc"}));
    assert.equal((await ingestHumorSourceItem(db, twin, "giphy", {probe: false})).reason, "duplicate");
    assert.deepEqual(db.read(path), before);

    // Even without a stored duration, a Clip asset is not one of the GIF's MP4s.
    db._store.set(path, {...before, media: {...before.media, durationMs: null}});
    const noDuration = db.read(path);
    assert.equal((await ingestHumorSourceItem(db, twin, "giphy", {probe: false})).reason, "duplicate");
    assert.deepEqual(db.read(path), noDuration);
  });

  it("leaves a doc whose MP4 is not this GIF's own, or that is not GIPHY's", async () => {
    const {db, path} = await legacyCatalogue();
    const stored = db.read(path);
    db._store.set(path, {
      ...stored,
      media: {...stored.media, downloadUrl: `${CDN}/someoneElse/giphy.mp4`},
    });
    const foreign = db.read(path);
    assert.equal(
      (await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: false})).reason,
      "duplicate",
    );
    assert.deepEqual(db.read(path), foreign);

    const internal = {...stored, source: {type: "internal", provider: "mevora-internal"}};
    assert.equal(isLegacyGifVideoDoc(`ext_giphy_${LEGACY_ID}`, internal, mapOk(fullGif())), false);
    assert.equal(isLegacyGifVideoDoc("hc_other", stored, mapOk(fullGif())), false);
  });

  it("does nothing when the fresh result is itself MP4-only", async () => {
    const {db, path} = await legacyCatalogue();
    const before = db.read(path);
    const result = await ingestHumorSourceItem(db, mapOk(legacyGif()), "giphy", {probe: false});
    assert.equal(result.reason, "duplicate");
    assert.deepEqual(db.read(path), before);
  });

  it("skips the migration when the new rendition is unreachable", async () => {
    const {db, path} = await legacyCatalogue();
    const before = db.read(path);
    const probed = [];
    globalThis.fetch = async (url) => {
      probed.push(String(url));
      return {ok: false, status: 404};
    };
    const result = await ingestHumorSourceItem(db, mapOk(fullGif()), "giphy", {probe: true});
    assert.equal(result.reason, "duplicate");
    assert.deepEqual(db.read(path), before);
    assert.ok(probed.every((u) => u === `${CDN}/${LEGACY_ID}/giphy.webp`));
    assert.ok(probed.length > 0);
  });

  it("re-checks inside its transaction: an ineligible doc is never written", async () => {
    const {db, path} = await legacyCatalogue({active: false});
    const before = db.read(path);
    assert.equal(
      await migrateLegacyGifVideoDoc(db, `ext_giphy_${LEGACY_ID}`, mapOk(fullGif()), {probe: false}),
      false,
    );
    assert.deepEqual(db.read(path), before);
  });

  it("the provider sync reports migrations separately from duplicates", async () => {
    const run = async (db, fixture) => {
      const fake = fakeGiphyFetch({gifsByQuery: {"*": [fixture]}});
      const logs = [];
      const result = await syncHumorFromGiphy({
        db,
        language: "tr",
        limit: 40,
        probe: false,
        source: new GiphyHumorSource("fixture-key", {fetchImpl: fake.fetchImpl}),
        rotation: 0,
        queryCount: 1,
        log: (message, meta) => logs.push({message, meta}),
      });
      return {result, logs};
    };
    const db = createFakeFirestore({});
    const first = await run(db, legacyGif());
    assert.equal(first.result.accepted, 1);
    assert.equal(first.result.migrated, 0);
    assert.equal(db.read(`humorContent/ext_giphy_${LEGACY_ID}`).type, "video");

    const second = await run(db, fullGif());
    assert.equal(second.result.accepted, 0);
    assert.equal(second.result.migrated, 1);
    assert.equal(second.result.duplicates, 0);
    assert.equal(second.logs[0].meta.migrated, 1);
    assert.equal(db.read(`humorContent/ext_giphy_${LEGACY_ID}`).type, "meme");

    const third = await run(db, fullGif());
    assert.equal(third.result.migrated, 0);
    assert.equal(third.result.duplicates, 1);
  });
});
