import {defineSecret, defineString} from "firebase-functions/params";

/** External music provider identifier stored on user summaries. */
export const EXTERNAL_PROVIDER_ID = "external";

/**
 * Server-side credentials for the future external music API.
 * Values are supplied via Firebase secrets when API documentation arrives.
 * Never expose to clients.
 */
export const externalMusicApiKey = defineSecret("EXTERNAL_MUSIC_API_KEY");
export const externalMusicApiSecret = defineSecret("EXTERNAL_MUSIC_API_SECRET");

/** API base URL — empty until configured in Phase 4. */
export const externalMusicApiBaseUrl = defineString("EXTERNAL_MUSIC_API_BASE_URL", {
  default: "",
});

export const externalMusicSecrets = [
  externalMusicApiKey,
  externalMusicApiSecret,
] as const;

export type ExternalMusicRuntimeConfig = {
  apiKey: string;
  apiSecret: string;
  baseUrl: string;
};

function readSecretValue(
  envKey: string,
  secret: ReturnType<typeof defineSecret>,
): string | undefined {
  const fromEnv = process.env[envKey]?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    const value = secret.value()?.trim();
    return value || undefined;
  } catch {
    return undefined;
  }
}

function readBaseUrl(): string | undefined {
  const fromEnv = process.env.EXTERNAL_MUSIC_API_BASE_URL?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    const value = externalMusicApiBaseUrl.value()?.trim();
    return value || undefined;
  } catch {
    return undefined;
  }
}

/** True when all required external API credentials and base URL are present. */
export function isExternalMusicApiConfigured(): boolean {
  return resolveExternalMusicConfig() !== null;
}

/**
 * Resolves runtime external music config from Firebase secrets / env vars.
 * Returns null when credentials are missing — never throws.
 */
export function resolveExternalMusicConfig(): ExternalMusicRuntimeConfig | null {
  const apiKey = readSecretValue("EXTERNAL_MUSIC_API_KEY", externalMusicApiKey);
  const apiSecret = readSecretValue("EXTERNAL_MUSIC_API_SECRET", externalMusicApiSecret);
  const baseUrl = readBaseUrl();

  if (!apiKey || !apiSecret || !baseUrl) {
    return null;
  }

  return {apiKey, apiSecret, baseUrl};
}
