import {defineSecret, defineString} from "firebase-functions/params";

/**
 * Humor Lab provider secrets — server-side only.
 * Never put these in Flutter / commit them to git.
 *
 *   firebase functions:secrets:set GIPHY_API_KEY --project mevora-d6ed0
 *   firebase functions:secrets:set YOUTUBE_DATA_API_KEY --project mevora-d6ed0
 *
 * Emulator: copy names into functions/.env.mevora-d6ed0 (gitignored).
 *
 * Tenor: not configured — public API sunset 2026-06-30.
 */
export const giphyApiKey = defineSecret("GIPHY_API_KEY");
export const giphyApiBase = defineString("GIPHY_API_BASE", {
  default: "https://api.giphy.com/v1",
});

export const youtubeDataApiKey = defineSecret("YOUTUBE_DATA_API_KEY");

function readSecret(
  envName: string,
  secret: ReturnType<typeof defineSecret>,
): string | null {
  const fromEnv = (process.env[envName] ?? "").trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    const value = secret.value();
    return value && value.trim() ? value.trim() : null;
  } catch {
    return null;
  }
}

export function resolveGiphyApiKey(): string | null {
  return readSecret("GIPHY_API_KEY", giphyApiKey);
}

export function isGiphyConfigured(): boolean {
  return resolveGiphyApiKey() != null;
}

export function resolveYoutubeDataApiKey(): string | null {
  return readSecret("YOUTUBE_DATA_API_KEY", youtubeDataApiKey);
}

export function isYoutubeConfigured(): boolean {
  return resolveYoutubeDataApiKey() != null;
}

/** Secrets to attach when a callable may hit live providers. */
export const humorProviderSecrets = [giphyApiKey, youtubeDataApiKey] as const;

export type HumorProviderStatus = {
  youtube: {configured: boolean; freeTier: string};
  giphy: {configured: boolean; freeTier: string};
  tenor: {configured: boolean; freeTier: string; active: false};
  internal: {configured: true; freeTier: string};
};

export function humorProviderStatus(): HumorProviderStatus {
  return {
    youtube: {
      configured: isYoutubeConfigured(),
      freeTier: "YouTube Data API ~10k units/day; search.list=100 units (~100 searches/day)",
    },
    giphy: {
      configured: isGiphyConfigured(),
      freeTier: "Beta key ~100 req/hour; production key requires GIPHY review (may be paid)",
    },
    tenor: {
      configured: false,
      active: false,
      freeTier: "Public Tenor API sunset 2026-06-30 — disabled",
    },
    internal: {
      configured: true,
      freeTier: "Mevora-owned / licensed pool in Firestore (no third-party API cost)",
    },
  };
}
