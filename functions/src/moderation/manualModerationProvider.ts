import type {ModerationResult} from "./types.js";

const MAX_BYTES = 5 * 1024 * 1024;
const MIN_EDGE_PX = 200;
const MAX_EDGE_PX = 8000;

const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/jpg",
  "image/png",
  "image/webp",
]);

function magicMatches(contentType: string, buffer: Buffer): boolean {
  if (buffer.length < 12) {
    return false;
  }
  const lower = contentType.toLowerCase();
  if (lower.includes("png")) {
    return buffer.subarray(0, 8).equals(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
  }
  if (lower.includes("webp")) {
    return buffer.toString("ascii", 0, 4) === "RIFF" &&
      buffer.toString("ascii", 8, 12) === "WEBP";
  }
  return buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
}

function readPngDimensions(buffer: Buffer): {width: number; height: number} | null {
  if (buffer.length < 24) {
    return null;
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
  };
}

function readJpegDimensions(buffer: Buffer): {width: number; height: number} | null {
  let offset = 2;
  while (offset + 9 < buffer.length) {
    if (buffer[offset] !== 0xff) {
      return null;
    }
    const marker = buffer[offset + 1];
    const length = buffer.readUInt16BE(offset + 2);
    if (marker === 0xc0 || marker === 0xc2) {
      return {
        height: buffer.readUInt16BE(offset + 5),
        width: buffer.readUInt16BE(offset + 7),
      };
    }
    offset += 2 + length;
  }
  return null;
}

function readWebpDimensions(buffer: Buffer): {width: number; height: number} | null {
  if (buffer.length < 30) {
    return null;
  }
  const chunk = buffer.toString("ascii", 12, 16);
  if (chunk === "VP8 ") {
    return {
      width: buffer.readUInt16LE(26) & 0x3fff,
      height: buffer.readUInt16LE(28) & 0x3fff,
    };
  }
  if (chunk === "VP8L") {
    const bits = buffer.readUInt32LE(21);
    return {
      width: (bits & 0x3fff) + 1,
      height: ((bits >> 14) & 0x3fff) + 1,
    };
  }
  if (chunk === "VP8X") {
    return {
      width: 1 + buffer.readUIntLE(24, 3),
      height: 1 + buffer.readUIntLE(27, 3),
    };
  }
  return null;
}

function readDimensions(contentType: string, buffer: Buffer): {width: number; height: number} | null {
  const lower = contentType.toLowerCase();
  if (lower.includes("png")) {
    return readPngDimensions(buffer);
  }
  if (lower.includes("webp")) {
    return readWebpDimensions(buffer);
  }
  return readJpegDimensions(buffer);
}

function dimensionsValid(width: number, height: number): boolean {
  return width >= MIN_EDGE_PX &&
    height >= MIN_EDGE_PX &&
    width <= MAX_EDGE_PX &&
    height <= MAX_EDGE_PX;
}

/// Technical-only moderation (no AI). Future AIModerationProvider can wrap this.
export async function moderatePhotoBuffer(options: {
  contentType: string | undefined;
  sizeBytes: number;
  buffer: Buffer;
  smokeFastPath?: boolean;
}): Promise<ModerationResult> {
  if (options.smokeFastPath) {
    return {status: "approved", reason: "smoke-test-fast-path"};
  }

  const contentType = String(options.contentType ?? "").toLowerCase();
  if (!ALLOWED_TYPES.has(contentType)) {
    return {status: "rejected", reason: "unsupported-content-type"};
  }
  if (options.sizeBytes <= 0 || options.sizeBytes > MAX_BYTES) {
    return {status: "rejected", reason: "invalid-file-size"};
  }
  if (!magicMatches(contentType, options.buffer)) {
    return {status: "rejected", reason: "corrupt-or-mismatched-format"};
  }

  const dimensions = readDimensions(contentType, options.buffer);
  if (!dimensions || !dimensionsValid(dimensions.width, dimensions.height)) {
    return {status: "manual_review", reason: "dimensions-unverified"};
  }

  return {status: "approved", reason: "technical-check-passed"};
}
