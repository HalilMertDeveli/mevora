import {defineSecret, defineString} from "firebase-functions/params";

/**
 * GIPHY is the licensed humor media provider (GIFs / Clips / MP4 renditions).
 * Set via Firebase params or env. Never commit real keys.
 *
 * Dashboard: https://developers.giphy.com/
 * Optional: `firebase functions:secrets:set GIPHY_API_KEY`
 */
export const giphyApiKey = defineSecret("GIPHY_API_KEY");
export const giphyApiBase = defineString("GIPHY_API_BASE", {
  default: "https://api.giphy.com/v1",
});

export function resolveGiphyApiKey(): string | null {
  const fromEnv = (process.env.GIPHY_API_KEY ?? "").trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    const value = giphyApiKey.value();
    return value && value.trim() ? value.trim() : null;
  } catch {
    return null;
  }
}

export function isGiphyConfigured(): boolean {
  return resolveGiphyApiKey() != null;
}
