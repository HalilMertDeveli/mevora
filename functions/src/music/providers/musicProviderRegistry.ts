import {HttpsError} from "firebase-functions/v2/https";
import {SPOTIFY_PROVIDER_ID} from "../normalize/normalizeMusicProfile.js";
import {EXTERNAL_PROVIDER_ID} from "../externalMusicConfig.js";
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

/**
 * Resolves a music provider by identifier without changing existing Spotify flows.
 * Spotify sync continues to use SpotifyMusicProvider directly until Phase 4.
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
    return new ExternalMusicProvider();
  }
  throw new HttpsError("invalid-argument", "unknown-music-provider");
}
