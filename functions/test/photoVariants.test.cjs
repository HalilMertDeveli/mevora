const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");
const {
  PHOTO_CACHE_CONTROL,
  PHOTO_VARIANTS,
  deletePhotoVariants,
  publishPhotoVariants,
  renderVariant,
  variantPath,
} = require("../lib/moderation/photoVariants.js");
const {publishApprovedPhoto} = require("../lib/moderation/photoModerationService.js");
const {reconcilePhoto, writeLedgerEntry} = require("../lib/moderation/photoModerationLedger.js");
const {publicProfileProjection} = require("../lib/profileSafety.js");

const UID = "member-1";
const PORTRAIT_DIR = path.join(__dirname, "..", "..", "assets", "images", "portraits");
const PORTRAIT = fs.readFileSync(path.join(PORTRAIT_DIR, "mock-06.jpg"));

/** In-memory bucket recording every object with the metadata it was given. */
function memoryBucket(seed = {}) {
  const files = new Map(Object.entries(seed).map(([k, v]) => [k, {bytes: v, metadata: {}}]));
  return {
    name: "test-bucket",
    files,
    file(p) {
      return {
        name: p,
        async save(data, options = {}) {
          files.set(p, {bytes: Buffer.from(data), metadata: {...(options.metadata ?? {})}});
        },
        async copy(dest) {
          files.set(dest.name, {bytes: files.get(p).bytes, metadata: {}});
        },
        async setMetadata(meta) {
          files.get(p).metadata = {...files.get(p).metadata, ...meta};
        },
        async download() {
          if (!files.has(p)) throw Object.assign(new Error("not found"), {code: 404});
          return [files.get(p).bytes];
        },
        async delete() {
          files.delete(p);
        },
      };
    },
  };
}

function ledgerDb() {
  const docs = new Map();
  return {
    docs,
    doc(p) {
      return {
        async set(data) {
          docs.set(p, {...(docs.get(p) ?? {}), ...data});
        },
      };
    },
  };
}

describe("profile photo variants", () => {
  it("renders a JPEG whose shorter edge is the variant target, keeping aspect", async () => {
    for (const spec of PHOTO_VARIANTS) {
      const out = await renderVariant(PORTRAIT, spec);
      const meta = await sharp(out.data).metadata();
      assert.equal(meta.format, "jpeg");
      assert.equal(Math.min(meta.width, meta.height), spec.minEdgePx);
      // mock-06 is 800x1200 (2:3); the variant keeps that ratio.
      assert.ok(Math.abs(meta.height / meta.width - 1.5) < 0.01);
    }
  });

  it("never enlarges a photo smaller than the variant", async () => {
    const small = await sharp({create: {width: 240, height: 300, channels: 3, background: "#884422"}})
      .jpeg().toBuffer();
    const out = await renderVariant(small, PHOTO_VARIANTS[1]);
    assert.equal(out.width, 240);
    assert.equal(out.height, 300);
  });

  it("drops EXIF from the variant", async () => {
    const withExif = await sharp(PORTRAIT)
      .withExif({IFD0: {Copyright: "location-bearing metadata"}})
      .jpeg().toBuffer();
    assert.ok((await sharp(withExif).metadata()).exif);
    const out = await renderVariant(withExif, PHOTO_VARIANTS[0]);
    assert.equal((await sharp(out.data).metadata()).exif, undefined);
  });

  it("thumb and card are far smaller than the original", async () => {
    const [thumb, card] = await Promise.all(PHOTO_VARIANTS.map((spec) => renderVariant(PORTRAIT, spec)));
    assert.ok(thumb.data.length < PORTRAIT.length * 0.25, `thumb ${thumb.data.length} vs ${PORTRAIT.length}`);
    assert.ok(card.data.length < PORTRAIT.length * 0.75, `card ${card.data.length} vs ${PORTRAIT.length}`);
  });

  it("uploads each variant under thumbs/ with a token and long private caching", async () => {
    const bucket = memoryBucket();
    const out = await publishPhotoVariants({bucket, uid: UID, imageId: "img1", source: PORTRAIT});
    for (const spec of PHOTO_VARIANTS) {
      const p = variantPath(UID, "img1", spec.name);
      assert.equal(p, `users/${UID}/profile/thumbs/img1_${spec.name}.jpg`);
      const stored = bucket.files.get(p);
      assert.ok(stored, `missing ${p}`);
      assert.equal(stored.metadata.contentType, "image/jpeg");
      assert.equal(stored.metadata.cacheControl, PHOTO_CACHE_CONTROL);
      const token = stored.metadata.metadata.firebaseStorageDownloadTokens;
      assert.match(token, /^[0-9a-f-]{36}$/);
      assert.equal(out[spec.name].url,
        `https://firebasestorage.googleapis.com/v0/b/test-bucket/o/${encodeURIComponent(p)}?alt=media&token=${token}`);
    }
  });

  it("an undecodable approved photo publishes with no variants rather than failing", async () => {
    const bucket = memoryBucket();
    const out = await publishPhotoVariants({bucket, uid: UID, imageId: "img1", source: Buffer.from("not an image")});
    assert.deepEqual(out, {});
    assert.equal(bucket.files.size, 0);
  });

  it("deletePhotoVariants removes every variant", async () => {
    const bucket = memoryBucket();
    await publishPhotoVariants({bucket, uid: UID, imageId: "img1", source: PORTRAIT});
    await deletePhotoVariants(bucket, UID, "img1");
    assert.equal(bucket.files.size, 0);
  });
});

describe("publishApprovedPhoto", () => {
  it("keeps the original byte-for-byte, caches it, and returns the variant URLs", async () => {
    const pending = `users/${UID}/profile/pending/img1.jpg`;
    const bucket = memoryBucket({[pending]: PORTRAIT});
    const published = await publishApprovedPhoto({
      db: {},
      bucket,
      uid: UID,
      imageId: "img1",
      sourcePath: pending,
      contentType: "image/jpeg",
    });
    assert.equal(published.destPath, `users/${UID}/profile/photos/img1.jpg`);
    const original = bucket.files.get(published.destPath);
    assert.ok(original.bytes.equals(PORTRAIT));
    assert.equal(original.metadata.cacheControl, PHOTO_CACHE_CONTROL);
    assert.match(published.thumbUrl, /img1_thumb\.jpg\?alt=media&token=/);
    assert.match(published.cardUrl, /img1_card\.jpg\?alt=media&token=/);
  });

  it("uses the buffer moderation already downloaded", async () => {
    const pending = `users/${UID}/profile/pending/img1.jpg`;
    const bucket = memoryBucket({[pending]: PORTRAIT});
    const file = bucket.file.bind(bucket);
    let downloads = 0;
    bucket.file = (p) => {
      const f = file(p);
      return {...f, async download() {
        downloads += 1;
        return f.download();
      }};
    };
    const published = await publishApprovedPhoto({
      db: {}, bucket, uid: UID, imageId: "img1", sourcePath: pending, contentType: "image/jpeg", sourceBuffer: PORTRAIT,
    });
    assert.equal(downloads, 0);
    assert.ok(published.thumbUrl);
  });
});

describe("variant URLs are server-owned", () => {
  const approved = {
    status: "approved",
    storagePath: `users/${UID}/profile/photos/img1.jpg`,
    downloadUrl: "https://firebasestorage.googleapis.com/original",
    thumbUrl: "https://firebasestorage.googleapis.com/thumb",
    cardUrl: "https://firebasestorage.googleapis.com/card",
  };

  it("the ledger records variant URLs next to the original", async () => {
    const db = ledgerDb();
    await writeLedgerEntry(db, UID, "img1", approved);
    const doc = db.docs.get(`users/${UID}/photoModeration/img1`);
    assert.equal(doc.thumbUrl, approved.thumbUrl);
    assert.equal(doc.cardUrl, approved.cardUrl);
  });

  it("a status-only ledger update leaves the recorded variants alone", async () => {
    const db = ledgerDb();
    await writeLedgerEntry(db, UID, "img1", approved);
    await writeLedgerEntry(db, UID, "img1", {status: "manual_review", reason: "reported"});
    const doc = db.docs.get(`users/${UID}/photoModeration/img1`);
    assert.equal(doc.cardUrl, approved.cardUrl);
  });

  it("an approved photo projects the ledger's variants over whatever the client wrote", () => {
    const next = reconcilePhoto(
      {id: "img1", thumbUrl: "https://evil.example/t.jpg", cardUrl: "https://evil.example/c.jpg"},
      approved,
    );
    assert.equal(next.thumbUrl, approved.thumbUrl);
    assert.equal(next.cardUrl, approved.cardUrl);
  });

  it("a client-supplied cardUrl on an unmoderated photo is cleared", () => {
    const next = reconcilePhoto({id: "img1", cardUrl: "https://evil.example/c.jpg"}, null);
    assert.equal(next.cardUrl, null);
    assert.equal(next.thumbUrl, null);
  });

  it("a photo pulled back into review stops carrying variant URLs", () => {
    const next = reconcilePhoto(
      {id: "img1", thumbUrl: approved.thumbUrl, cardUrl: approved.cardUrl},
      {...approved, status: "manual_review"},
    );
    assert.equal(next.thumbUrl, null);
    assert.equal(next.cardUrl, null);
  });

  it("the public projection carries cardUrl for approved photos only", () => {
    const projection = publicProfileProjection({
      uid: UID,
      photos: [
        {id: "a", moderationStatus: "approved", downloadUrl: "o", thumbUrl: "t", cardUrl: "c"},
        {id: "b", moderationStatus: "pending", downloadUrl: "o2", cardUrl: "c2"},
      ],
    });
    assert.equal(projection.photos.length, 1);
    assert.equal(projection.photos[0].cardUrl, "c");
    assert.equal(projection.photos[0].thumbUrl, "t");
  });
});
