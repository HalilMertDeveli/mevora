import {createHash} from "node:crypto";
import sharp from "sharp";

/** Longest edge sent to the provider. Enough for a face, well under its 5 MB limit. */
const MAX_EDGE_PX = 1600;

/** JPEG, PNG or WebP by content — the uploader's declared content type is not evidence. */
export function looksLikeImage(buffer: Buffer): boolean {
  if (buffer.length < 12) {
    return false;
  }
  const jpeg = buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const png = buffer.subarray(0, 8).equals(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  );
  const webp = buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP";
  return jpeg || png || webp;
}

/**
 * Re-encodes an image for the verification provider: upright, bounded, JPEG.
 *
 * sharp keeps no metadata by default, so whatever EXIF the original carried —
 * capture time, device, GPS position — is not sent to a third party. Throws
 * when the bytes are not a decodable image.
 */
export async function normalizeForVerification(bytes: Buffer): Promise<Buffer> {
  return sharp(bytes)
    .rotate()
    .resize({width: MAX_EDGE_PX, height: MAX_EDGE_PX, fit: "inside", withoutEnlargement: true})
    .jpeg({quality: 88})
    .toBuffer();
}

export function contentHash(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}
