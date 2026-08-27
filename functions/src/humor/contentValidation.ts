import type {HumorSourceItem} from "./sourceAdapter.js";

export interface ContentValidationResult {
  ok: boolean;
  reason?: string;
}

const ALLOWED_HOST_HINTS = [
  "giphy.com",
  "giphy.gif",
  "media.giphy.com",
  "media0.giphy.com",
  "media1.giphy.com",
  "media2.giphy.com",
  "media3.giphy.com",
  "media4.giphy.com",
  "youtube.com",
  "www.youtube.com",
  "youtu.be",
  "i.ytimg.com",
  "yt3.ggpht.com",
  "commondatastorage.googleapis.com",
  "picsum.photos",
  "images.unsplash.com",
  "firebasestorage.googleapis.com",
];

function hostAllowed(host: string): boolean {
  const h = host.toLowerCase();
  return ALLOWED_HOST_HINTS.some(
    (hint) => h === hint || h.endsWith(`.${hint}`) || h.includes(hint),
  );
}

export function validateHumorSourceItem(
  item: HumorSourceItem,
): ContentValidationResult {
  if (!item.sourceId || !item.sourceId.trim()) {
    return {ok: false, reason: "missing-sourceId"};
  }
  const url = item.media?.downloadUrl?.trim() ?? "";
  if (!url) {
    return {ok: false, reason: "missing-media-url"};
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return {ok: false, reason: "invalid-url"};
  }
  if (parsed.protocol !== "https:") {
    return {ok: false, reason: "insecure-url"};
  }
  const host = parsed.hostname.toLowerCase();
  const allowed = hostAllowed(host);
  if (!allowed && item.sourceUrl) {
    try {
      const src = new URL(item.sourceUrl);
      if (
        !src.hostname.includes("giphy.com") &&
        !src.hostname.includes("youtube.com") &&
        !src.hostname.includes("youtu.be")
      ) {
        return {ok: false, reason: "host-not-allowed"};
      }
    } catch {
      return {ok: false, reason: "host-not-allowed"};
    }
  } else if (!allowed) {
    return {ok: false, reason: "host-not-allowed"};
  }
  if (item.media.embedUrl) {
    try {
      const embed = new URL(item.media.embedUrl);
      if (embed.protocol !== "https:" || !hostAllowed(embed.hostname)) {
        return {ok: false, reason: "embed-host-not-allowed"};
      }
    } catch {
      return {ok: false, reason: "invalid-embed-url"};
    }
  }
  return {ok: true};
}

/** Soft HEAD/GET probe — marks broken URLs inactive upstream. */
export async function probeMediaUrl(
  url: string,
  timeoutMs = 4000,
): Promise<boolean> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const head = await fetch(url, {
      method: "HEAD",
      signal: controller.signal,
      redirect: "follow",
    });
    if (head.ok) {
      return true;
    }
    // Some CDNs reject HEAD — try ranged GET.
    const get = await fetch(url, {
      method: "GET",
      headers: {Range: "bytes=0-0"},
      signal: controller.signal,
      redirect: "follow",
    });
    return get.ok || get.status === 206;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}
