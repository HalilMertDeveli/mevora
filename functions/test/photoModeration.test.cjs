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

  it("uses the smoke fast path only inside the emulator process", async () => {
    const unchecked = {
      contentType: "application/pdf",
      sizeBytes: 10,
      buffer: Buffer.from("bad"),
      smokeFastPath: true,
    };
    const saved = process.env.FUNCTIONS_EMULATOR;
    try {
      process.env.FUNCTIONS_EMULATOR = "true";
      const result = await moderatePhotoBuffer(unchecked);
      assert.equal(result.status, "approved");
      assert.equal(result.reason, "smoke-test-fast-path");

      // A deployed backend ignores the option: the bytes are checked like
      // anyone's, and these are not an image.
      for (const live of [undefined, "false", "1"]) {
        if (live === undefined) delete process.env.FUNCTIONS_EMULATOR;
        else process.env.FUNCTIONS_EMULATOR = live;
        const checked = await moderatePhotoBuffer(unchecked);
        assert.equal(checked.status, "rejected");
        assert.equal(checked.reason, "unsupported-content-type");
      }
    } finally {
      if (saved === undefined) delete process.env.FUNCTIONS_EMULATOR;
      else process.env.FUNCTIONS_EMULATOR = saved;
    }
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

  // The upload trigger's first write marks the photo "processing" with
  // lastProcessingAttempt: serverTimestamp(). That sentinel was not resolved,
  // so every upload of a photo already listed in profiles.photos crashed the
  // trigger and left the photo stuck in "processing" — and completeOnboarding
  // then refused the profile with photos-required.
  it("the processing mark survives write validation", () => {
    const photos = buildModeratedPhotos(existing, "p0", {
      moderationStatus: "processing",
      processingAttempts: 1,
      lastProcessingAttempt: FieldValue.serverTimestamp(),
      processingError: null,
    });
    assertWritable(photos);
    assert.equal(photos[0].moderationStatus, "processing");
    assert.ok(!(photos[0].lastProcessingAttempt instanceof FieldValue));
  });

  it("a concrete moderatedAt is passed through untouched", () => {
    const when = new Date(Date.UTC(2026, 8, 23));
    const photos = buildModeratedPhotos(existing, "p0", {moderatedAt: when});
    assert.equal(photos[0].moderatedAt, when);
  });

  // An admin approving an already-published photo (a reported member's photo
  // sent to manual review) publishes nothing new and leaves thumbUrl/cardUrl
  // undefined: "leave the field as it is", which is how the ledger reads it.
  // Firestore accepts undefined nowhere in a document, so copying it into the
  // array element failed the profile write after the ledger already said
  // approved, and a retry was refused as photo_already_reviewed.
  const publishedApproval = {
    moderationStatus: "approved",
    moderationReason: "admin-approved",
    moderatedBy: "admin_review",
    moderatedAt: FieldValue.serverTimestamp(),
    storagePath: "users/u1/profile/photos/p0.jpg",
    downloadUrl: "https://example.test/p0.jpg",
    thumbUrl: undefined,
    cardUrl: undefined,
    processingError: null,
  };

  it("re-approving a published photo survives write validation and keeps its variants", () => {
    const published = [{
      id: "p0",
      order: 0,
      isPrimary: true,
      moderationStatus: "manual_review",
      storagePath: "users/u1/profile/photos/p0.jpg",
      downloadUrl: "https://example.test/p0.jpg",
      thumbUrl: "https://example.test/p0_thumb.jpg",
      cardUrl: "https://example.test/p0_card.jpg",
    }];
    const photos = buildModeratedPhotos(published, "p0", publishedApproval);
    assertWritable(photos);
    assert.equal(photos[0].moderationStatus, "approved");
    assert.equal(photos[0].thumbUrl, "https://example.test/p0_thumb.jpg");
    assert.equal(photos[0].cardUrl, "https://example.test/p0_card.jpg");
    assert.equal(photos[0].processingError, null);
  });

  it("an undefined patch value adds no field to a photo that lacks it", () => {
    for (const imageId of ["p0", "p2"]) {
      const photos = buildModeratedPhotos(existing, imageId, publishedApproval);
      assertWritable(photos);
      const photo = photos.find((entry) => entry.id === imageId);
      assert.equal("thumbUrl" in photo, false);
      assert.equal("cardUrl" in photo, false);
    }
  });

  // The suites that drive whole callables run on the in-memory double, which
  // used to store undefined without complaint — so the write above passed
  // `npm test` and failed only against Firestore. It must refuse what the real
  // validator refuses, naming the same field.
  it("the in-memory Firestore double refuses undefined like the real validator", async () => {
    const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
    const photos = [{id: "p0", thumbUrl: undefined}];
    const refused = /Cannot use "undefined" as a Firestore value \(found in field "photos\.`0`\.thumbUrl"\)/;
    assert.throws(() => db.batch().set(db.doc("profiles/u1"), {photos}, {merge: true}), refused);

    const fake = createFakeFirestore({"profiles/u1": {photos: []}});
    const ref = fake.doc("profiles/u1");
    await assert.rejects(ref.set({photos}, {merge: true}), refused);
    await assert.rejects(ref.update({photos}), refused);
    await assert.rejects(fake.doc("profiles/u2").create({photos}), refused);
    assert.throws(() => fake.batch().set(ref, {photos}, {merge: true}), refused);
    await assert.rejects(fake.runTransaction(async (tx) => {
      await tx.get(ref);
      tx.set(ref, {photos}, {merge: true});
    }), refused);
    assert.deepEqual(fake.read("profiles/u1"), {photos: []});
    // null and an absent key stay legal.
    await ref.set({photos: [{id: "p0", thumbUrl: null}]}, {merge: true});
  });

  it("a null patch value still clears the field", () => {
    const withVariants = [{id: "p0", order: 0, isPrimary: true, thumbUrl: "https://t", cardUrl: "https://c"}];
    const photos = buildModeratedPhotos(withVariants, "p0", {thumbUrl: null, cardUrl: null});
    assertWritable(photos);
    assert.equal(photos[0].thumbUrl, null);
    assert.equal(photos[0].cardUrl, null);
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
