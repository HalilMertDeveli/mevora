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

/**
 * KLIPY Clips: a second curated source, reached only by the emulator-only
 * curator search (`searchHumorProviderCandidates`). Never commit a real key.
 *
 * Declared inside the Functions emulator and nowhere else. A deploy asks for
 * every secret a loaded module declares, bound to a deployed function or not,
 * so declaring this one unconditionally would make the next deploy prompt for
 * a KLIPY production key. Outside the emulator there is no KLIPY secret.
 *
 * Dashboard: https://partner.klipy.com/api-keys
 */
export const klipyApiKey =
  process.env.FUNCTIONS_EMULATOR === "true" ? defineSecret("KLIPY_API_KEY") : null;

export function resolveKlipyApiKey(): string | null {
  const fromEnv = (process.env.KLIPY_API_KEY ?? "").trim();
  if (fromEnv) {
    return fromEnv;
  }
  if (!klipyApiKey) {
    return null;
  }
  try {
    const value = klipyApiKey.value();
    return value && value.trim() ? value.trim() : null;
  } catch {
    return null;
  }
}

export function isKlipyConfigured(): boolean {
  return resolveKlipyApiKey() != null;
}
