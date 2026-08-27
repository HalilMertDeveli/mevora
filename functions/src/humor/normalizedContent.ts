/**
 * Normalized humor content model shared across providers.
 * Media is always streamed/embedded — never copied into Firebase Storage
 * unless the content is Mevora-licensed internal pool.
 */

export type NormalizedHumorProvider =
  | "youtube"
  | "giphy"
  | "tenor"
  | "mevora-internal";

export type NormalizedHumorType = "video" | "gif";

export type NormalizedHumorContent = {
  id: string;
  provider: NormalizedHumorProvider;
  providerContentId: string;
  type: NormalizedHumorType;
  title: string;
  thumbnailUrl: string | null;
  /** Direct streamable media (GIF/MP4 CDN). Prefer over embed when present. */
  contentUrl: string | null;
  /** YouTube/iframe embed URL — display only, do not download. */
  embedUrl: string | null;
  durationMs: number | null;
  category: string;
  language: string;
  tags: string[];
  sourceUrl: string | null;
  attributionRequired: boolean;
  createdAt: string;
};

export function contentIdFromProvider(
  provider: NormalizedHumorProvider,
  providerContentId: string,
): string {
  return `ext_${provider}_${providerContentId}`
    .replace(/[^a-zA-Z0-9_-]/g, "_")
    .slice(0, 120);
}
