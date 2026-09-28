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
 *
 * Only production media hosts remain. The stock hosts the curated seed used
 * to borrow backdrops from (`picsum.photos`, `test-videos.co.uk`,
 * `interactive-examples.mdn.mozilla.net`, plus the never-used
 * `images.unsplash.com`) are gone: curated content is text-only now, and
 * media comes from the licensed provider (Giphy) or our own Storage bucket.
 * `commondatastorage.googleapis.com` is gone too: its sample bucket answers
 * 403, and that host fronts every public Cloud Storage bucket, so allowing
 * it allowed anyone's bucket.
 */
const ALLOWED_MEDIA_HOSTS = [
  "giphy.com",
  "firebasestorage.googleapis.com",
];

function isAllowedMediaHost(host: string): boolean {
  return ALLOWED_MEDIA_HOSTS.some(
    (allowed) => host === allowed || host.endsWith(`.${allowed}`),
  );
}

/** Why a URL is not servable, or null when it is (https + allowed host). */
export function mediaUrlProblem(raw: string | null | undefined): string | null {
  const url = raw?.trim() ?? "";
  if (!url) {
    return "missing-media-url";
  }
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return "invalid-url";
  }
  if (parsed.protocol !== "https:") {
    return "insecure-url";
  }
  // The host we will actually fetch bytes from is the only one that matters.
  // There used to be an escape hatch here: if `sourceUrl` merely contained
  // "giphy.com", media on *any* https host was accepted. Both fields come from
  // the same provider payload, so that let one attacker-supplied field vouch
  // for another. Removed — Giphy's own CDN shards all end in `.giphy.com` and
  // pass on their own.
  if (!isAllowedMediaHost(parsed.hostname.toLowerCase())) {
    return "host-not-allowed";
  }
  return null;
}

/** True for an https URL on an allowed media host. */
export function isAllowedMediaUrl(raw: string | null | undefined): boolean {
  return mediaUrlProblem(raw) === null;
}

export function validateHumorSourceItem(
  item: HumorSourceItem,
): ContentValidationResult {
  if (!item.sourceId || !item.sourceId.trim()) {
    return {ok: false, reason: "missing-sourceId"};
  }
  const problem = mediaUrlProblem(item.media?.downloadUrl);
  if (problem) {
    return {ok: false, reason: problem};
  }
  // The poster is fetched by the client just like the media, so it is held
  // to the same rule. The provider mapping never produces a bad one; this is
  // the backstop for any other caller.
  const thumb = item.media?.thumbUrl;
  if (thumb != null && mediaUrlProblem(thumb) !== null) {
    return {ok: false, reason: "poster-not-allowed"};
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
