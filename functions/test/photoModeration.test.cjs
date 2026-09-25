const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {moderatePhotoBuffer} = require("../lib/moderation/manualModerationProvider.js");

function tinyPngBuffer(width = 320, height = 320) {
  // Minimal valid PNG with IHDR dimensions.
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(width, 0);
  ihdrData.writeUInt32BE(height, 4);
  ihdrData[8] = 8;
  ihdrData[9] = 2;
  ihdrData[10] = 0;
  ihdrData[11] = 0;
  ihdrData[12] = 0;
  const ihdrType = Buffer.from("IHDR");
  const ihdrChunk = Buffer.concat([ihdrType, ihdrData]);
  const ihdrCrc = Buffer.alloc(4);
  const iend = Buffer.from([
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(13, 0);
  return Buffer.concat([signature, length, ihdrChunk, ihdrCrc, iend]);
}

describe("photo moderation provider", () => {
  it("approves valid png images after technical checks", async () => {
    const buffer = tinyPngBuffer();
    const result = await moderatePhotoBuffer({
      contentType: "image/png",
      sizeBytes: buffer.length,
      buffer,
    });
    assert.equal(result.status, "approved");
  });

  it("rejects unsupported content types", async () => {
    const result = await moderatePhotoBuffer({
      contentType: "application/pdf",
      sizeBytes: 100,
      buffer: Buffer.from("%PDF"),
    });
    assert.equal(result.status, "rejected");
  });

  it("uses smoke fast path when enabled", async () => {
    const result = await moderatePhotoBuffer({
      contentType: "application/pdf",
      sizeBytes: 10,
      buffer: Buffer.from("bad"),
      smokeFastPath: true,
    });
    assert.equal(result.status, "approved");
    assert.equal(result.reason, "smoke-test-fast-path");
  });
});

describe("photos array write shape", () => {
  // Firestore rejects a FieldValue sentinel inside an array element, and
  // profiles/{uid}.photos is an array of maps. Both moderation writes used to
  // put FieldValue.serverTimestamp() straight into a photo, so the whole
  // transaction threw:
  //   - reportUser wrote the report, then died flagging the reported photos,
  //     so the reporter saw "Something went wrong" and retried into duplicate
  //     reports while the reported profile was never escalated
  //   - the upload pipeline could not record an approve/reject decision
  // Run the real payloads through Firestore's own write validator so neither
  // shape can regress.
  const {
    buildModeratedPhotos,
    buildReportFlaggedPhotos,
  } = require("../lib/moderation/photoModerationService.js");
  const {FieldValue, Firestore} = require("@google-cloud/firestore");

  // set() validates synchronously, before any RPC, so no emulator is needed.
  const db = new Firestore({projectId: "validation-only"});
  const assertWritable = (photos) => {
    assert.doesNotThrow(() => {
      db.batch().set(
        db.doc("profiles/u1"),
        {photos, updatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
    });
  };

  const existing = [
    {id: "p0", order: 0, isPrimary: true, moderationStatus: "pending"},
    {id: "p1", order: 1, isPrimary: false, moderationStatus: "rejected"},
  ];

  it("a moderation decision survives write validation", () => {
    const photos = buildModeratedPhotos(existing, "p0", {
      moderationStatus: "approved",
      moderatedAt: FieldValue.serverTimestamp(),
      moderatedBy: "system",
    });
    assertWritable(photos);
    assert.equal(photos[0].moderationStatus, "approved");
    assert.ok(!(photos[0].moderatedAt instanceof FieldValue));
  });

  it("a new photo entry survives write validation", () => {
    const photos = buildModeratedPhotos(existing, "p2", {
      moderationStatus: "manual_review",
      moderatedAt: FieldValue.serverTimestamp(),
    });
    assertWritable(photos);
    assert.equal(photos.length, 3);
    assert.equal(photos[2].id, "p2");
  });

  it("a concrete moderatedAt is passed through untouched", () => {
    const when = new Date(Date.UTC(2026, 8, 23));
    const photos = buildModeratedPhotos(existing, "p0", {moderatedAt: when});
    assert.equal(photos[0].moderatedAt, when);
  });

  it("report escalation survives write validation", () => {
    const photos = buildReportFlaggedPhotos(existing, "harassment");
    assertWritable(photos);
    assert.equal(photos[0].moderationStatus, "manual_review");
    assert.equal(photos[0].moderatedBy, "report-pipeline");
    assert.ok(!(photos[0].moderatedAt instanceof FieldValue));
  });

  it("report escalation never un-rejects an already rejected photo", () => {
    const photos = buildReportFlaggedPhotos(existing, "harassment");
    assert.equal(photos[1].moderationStatus, "rejected");
    assert.equal(photos[1].moderatedBy, undefined);
  });
});
