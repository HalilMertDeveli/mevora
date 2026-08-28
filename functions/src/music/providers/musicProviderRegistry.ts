import {HttpsError} from "firebase-functions/v2/https";
import type {DocumentData} from "firebase-admin/firestore";
import {isExternalMusicApiConfigured, EXTERNAL_PROVIDER_ID} from "../externalMusicConfig.js";
import {SPOTIFY_PROVIDER_ID} from "../normalize/normalizeMusicProfile.js";
import {ExternalMusicProvider} from "./externalMusicProvider.js";
import {SpotifyMusicProvider} from "./spotifyMusicProvider.js";
import type {MusicProvider} from "./musicProvider.js";

type SpotifyGet = <T>(accessToken: string, path: string) => Promise<T>;

export type MusicProviderDeps = {
  spotifyGet: SpotifyGet;
};

/** Default provider for existing Spotify-connected users. */
export function defaultMusicProviderId(): string {
  return SPOTIFY_PROVIDER_ID;
}

export function isKnownMusicProviderId(providerId: string): boolean {
  return providerId === SPOTIFY_PROVIDER_ID || providerId === EXTERNAL_PROVIDER_ID;
}

/** Reads provider from a stored summary; defaults to spotify for legacy rows. */
export function resolveProviderIdFromSummary(
  data: DocumentData | undefined,
): string {
  if (typeof data?.provider === "string" && data.provider.trim().length > 0) {
    return data.provider.trim();
  }
  if (data?.spotifyConnected === true) {
    return SPOTIFY_PROVIDER_ID;
  }
  if (data?.connected === true && data.provider === EXTERNAL_PROVIDER_ID) {
    return EXTERNAL_PROVIDER_ID;
  }
  return defaultMusicProviderId();
}

/** External sync remains disabled until API credentials and HTTP wiring exist. */
export function isExternalProviderProductionReady(): boolean {
  return isExternalMusicApiConfigured();
}

/**
 * Resolves a music provider by identifier without changing existing Spotify flows.
 * Spotify sync continues to use SpotifyMusicProvider directly until external API lands.
 */
export function resolveMusicProvider(
  providerId: string,
  deps?: MusicProviderDeps,
): MusicProvider {
  if (providerId === SPOTIFY_PROVIDER_ID) {
    if (!deps?.spotifyGet) {
      throw new HttpsError("internal", "spotify-provider-deps-missing");
    }
    return new SpotifyMusicProvider(deps.spotifyGet);
  }
  if (providerId === EXTERNAL_PROVIDER_ID) {
    if (!isExternalProviderProductionReady()) {
      throw new HttpsError("failed-precondition", "external-api-not-configured");
    }
    return new ExternalMusicProvider();
  }
  throw new HttpsError("invalid-argument", "unknown-music-provider");
}
