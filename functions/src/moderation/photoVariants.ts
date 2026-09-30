import {randomUUID} from "node:crypto";
import sharp from "sharp";
import {logger} from "firebase-functions";

/**
 * Display-size derivatives of an approved profile photo.
 *
 * Every surface used to load the moderated original (up to 1080px, ~150–400 KB)
 * — a 56dp chat avatar included. publishApprovedPhoto now renders two smaller
 * JPEGs from the same approved bytes, so they carry exactly the moderation
 * decision the original does:
 *
 *   thumb — shorter edge 320px: avatars, list rows, chat inbox.
 *   card  — shorter edge 720px: the full-width Picks and Discover cards,
 *           where 320px would visibly blur on a 3x screen.
 *
 * The original stays untouched for the full-screen profile gallery.
 *
 * Variants live under users/{uid}/profile/thumbs/, which the Storage rules
 * already make server-write-only and readable by signed-in members — the same
 * exposure as photos/. Re-encoding also drops EXIF (sharp keeps none by
 * default), so a variant never carries the original's location metadata.
 */

export const PHOTO_VARIANTS = [
  {name: "thumb", minEdgePx: 320, quality: 72},
  {name: "card", minEdgePx: 720, quality: 80},
] as const;

export type PhotoVariantName = (typeof PHOTO_VARIANTS)[number]["name"];
export type PhotoVariantSpec = (typeof PHOTO_VARIANTS)[number];

/**
 * Published photo objects never change in place: every upload gets a fresh
 * imageId and every publish a fresh download token, so a URL always names the
 * same bytes. `private` keeps shared proxies from holding a copy past a
 * moderation removal; the member's own device may keep it for a year.
 */
export const PHOTO_CACHE_CONTROL = "private, max-age=31536000, immutable";

export interface PublishedVariant {
  path: string;
  url: string;
  bytes: number;
  width: number;
  height: number;
}

export type PublishedVariants = Partial<Record<PhotoVariantName, PublishedVariant>>;

/** Minimal Storage surface this module needs; the Admin SDK bucket satisfies it. */
export interface VariantBucket {
  name: string;
  file(path: string): {
    save(data: Buffer, options?: Record<string, unknown>): Promise<unknown>;
    delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>;
  };
}

export function variantPath(uid: string, imageId: string, name: PhotoVariantName): string {
  return `users/${uid}/profile/thumbs/${imageId}_${name}.jpg`;
}

export function firebaseDownloadUrl(bucketName: string, path: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/` +
    `${encodeURIComponent(path)}?alt=media&token=${token}`;
}

/**
 * Resizes so the shorter edge is [spec.minEdgePx] (never enlarging) and keeps
 * the aspect ratio — an avatar can centre-crop a portrait or a landscape
 * without dropping below its target resolution.
 */
export async function renderVariant(
  source: Buffer,
  spec: PhotoVariantSpec,
): Promise<{data: Buffer; width: number; height: number}> {
  const {data, info} = await sharp(source)
    .rotate() // bake EXIF orientation in before the metadata is dropped
    .resize({
      width: spec.minEdgePx,
      height: spec.minEdgePx,
      fit: "outside",
      withoutEnlargement: true,
    })
    .jpeg({quality: spec.quality, mozjpeg: true})
    .toBuffer({resolveWithObject: true});
  return {data, width: info.width, height: info.height};
}

/**
 * Renders and uploads every variant. Best effort by design: a photo that
 * passed moderation but cannot be decoded here (an odd encoder, the smoke
 * fast path) is still published — clients fall back to the original URL
 * when a variant URL is null.
 */
export async function publishPhotoVariants(options: {
  bucket: VariantBucket;
  uid: string;
  imageId: string;
  source: Buffer;
}): Promise<PublishedVariants> {
  const out: PublishedVariants = {};
  for (const spec of PHOTO_VARIANTS) {
    try {
      const rendered = await renderVariant(options.source, spec);
      const path = variantPath(options.uid, options.imageId, spec.name);
      const token = randomUUID();
      await options.bucket.file(path).save(rendered.data, {
        resumable: false,
        contentType: "image/jpeg",
        metadata: {
          contentType: "image/jpeg",
          cacheControl: PHOTO_CACHE_CONTROL,
          metadata: {firebaseStorageDownloadTokens: token},
        },
      });
      out[spec.name] = {
        path,
        url: firebaseDownloadUrl(options.bucket.name, path, token),
        bytes: rendered.data.length,
        width: rendered.width,
        height: rendered.height,
      };
    } catch (error) {
      logger.warn("Profile photo variant was not generated", {
        uid: options.uid,
        imageId: options.imageId,
        variant: spec.name,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return out;
}

/** Removes every variant of a photo. Used when a published photo is taken down. */
export async function deletePhotoVariants(
  bucket: VariantBucket,
  uid: string,
  imageId: string,
): Promise<void> {
  for (const spec of PHOTO_VARIANTS) {
    try {
      await bucket.file(variantPath(uid, imageId, spec.name)).delete({ignoreNotFound: true});
    } catch (error) {
      logger.warn("Profile photo variant could not be deleted", {
        uid,
        imageId,
        variant: spec.name,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}
