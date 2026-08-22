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
