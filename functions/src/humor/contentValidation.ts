import type {HumorSourceItem} from "./sourceAdapter.js";

export interface ContentValidationResult {
  ok: boolean;
  reason?: string;
}

/**
 * Media hosts we are willing to serve from.
 *
 * Matched by exact host or true subdomain suffix only. The previous
 * implementation also did a substring test, which accepted
 * `giphy.com.attacker.tld` and `evil-picsum.photos.cdn.tld` — the allowlist
 * was doing the opposite of its job. Suffix matching covers every
 * `media0..4.giphy.com` and `i.giphy.com` CDN shard, so those no longer need
 * listing one by one.
 */
const ALLOWED_MEDIA_HOSTS = [
  "giphy.com",
  "commondatastorage.googleapis.com",
  "picsum.photos",
  "images.unsplash.com",
  "firebasestorage.googleapis.com",
];

function isAllowedMediaHost(host: string): boolean {
  return ALLOWED_MEDIA_HOSTS.some(
    (allowed) => host === allowed || host.endsWith(`.${allowed}`),
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
  // The host we will actually fetch bytes from is the only one that matters.
  // There used to be an escape hatch here: if `sourceUrl` merely contained
  // "giphy.com", media on *any* https host was accepted. Both fields come from
  // the same provider payload, so that let one attacker-supplied field vouch
  // for another. Removed — Giphy's own CDN shards all end in `.giphy.com` and
  // pass on their own.
  if (!isAllowedMediaHost(parsed.hostname.toLowerCase())) {
    return {ok: false, reason: "host-not-allowed"};
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
