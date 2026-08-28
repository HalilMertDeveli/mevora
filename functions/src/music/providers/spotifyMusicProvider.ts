import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import type {DocumentData} from "firebase-admin/firestore";
import {buildSpotifyNormalizedProfile, SPOTIFY_PROVIDER_ID} from "../normalize/normalizeMusicProfile.js";
import type {MusicProvider, MusicProviderFetchInput} from "./musicProvider.js";
import type {NormalizedMusicProfile} from "../types/normalizedMusicProfile.js";

type SpotifyGet = <T>(accessToken: string, path: string) => Promise<T>;

function hasPlaylistScope(scope: string | undefined): boolean {
  if (!scope) return false;
  return scope.includes("playlist-read-private") || scope.includes("playlist-read-collaborative");
}

async function fetchPlaylistTaste(
  spotifyGet: SpotifyGet,
  accessToken: string,
  scope: string | undefined,
): Promise<{
  playlistTrackIds: string[];
  playlists: Array<{id: string; name: string; trackCount: number}>;
}> {
  if (!hasPlaylistScope(scope)) {
    return {playlistTrackIds: [], playlists: []};
  }
  try {
    type PlaylistPage = {
      items?: Array<{
        id?: string;
        name?: string;
        tracks?: {total?: number; href?: string};
      }>;
    };
    type TracksPage = {
      items?: Array<{track?: {id?: string} | null}>;
    };
    const page = await spotifyGet<PlaylistPage>(accessToken, "/me/playlists?limit=10");
    const playlists: Array<{id: string; name: string; trackCount: number}> = [];
    const trackIds: string[] = [];
    const seen = new Set<string>();
    for (const playlist of page.items ?? []) {
      const id = typeof playlist.id === "string" ? playlist.id : "";
      const name = typeof playlist.name === "string" ? playlist.name.trim() : "";
      if (!id || !name) continue;
      const trackCount = typeof playlist.tracks?.total === "number"
        ? playlist.tracks.total
        : 0;
      if (playlists.length < 10) {
        playlists.push({id, name, trackCount});
      }
      if (playlists.length > 5 || trackIds.length >= 200) {
        continue;
      }
      try {
        const tracks = await spotifyGet<TracksPage>(
          accessToken,
          `/playlists/${id}/tracks?fields=items(track(id))&limit=50`,
        );
        for (const row of tracks.items ?? []) {
          const trackId = row.track?.id;
          if (!trackId || seen.has(trackId)) continue;
          seen.add(trackId);
          trackIds.push(trackId);
          if (trackIds.length >= 200) break;
        }
      } catch (error) {
        logger.warn("playlist tracks fetch failed", {playlistId: id, error});
      }
    }
    return {
      playlistTrackIds: trackIds.slice(0, 200),
      playlists: playlists.slice(0, 10),
    };
  } catch (error) {
    logger.warn("playlist taste unavailable", {error});
    return {playlistTrackIds: [], playlists: []};
  }
}

export class SpotifyMusicProvider implements MusicProvider {
  readonly providerId = SPOTIFY_PROVIDER_ID;

  constructor(private readonly spotifyGet: SpotifyGet) {}

  async fetchTaste(input: MusicProviderFetchInput): Promise<NormalizedMusicProfile> {
    type Me = {id?: string; display_name?: string};
    type Paging<T> = {items?: T[]};

    const me = input.providerUserId
      ? {id: input.providerUserId, display_name: input.displayName ?? undefined}
      : await this.spotifyGet<Me>(input.accessToken, "/me");
    if (!me.id) {
      throw new HttpsError("unauthenticated", "oauth");
    }

    const [topTracks, topArtists, recentlyPlayed, playlistTaste] = await Promise.all([
      this.spotifyGet<Paging<DocumentData>>(
        input.accessToken,
        "/me/top/tracks?time_range=medium_term&limit=50",
      ),
      this.spotifyGet<Paging<DocumentData>>(
        input.accessToken,
        "/me/top/artists?time_range=medium_term&limit=50",
      ),
      this.spotifyGet<Paging<DocumentData>>(
        input.accessToken,
        "/me/player/recently-played?limit=50",
      ),
      fetchPlaylistTaste(this.spotifyGet, input.accessToken, input.scope),
    ]);

    return buildSpotifyNormalizedProfile({
      providerUserId: me.id,
      displayName: me.display_name ?? null,
      topTracksRaw: topTracks.items ?? [],
      topArtistsRaw: topArtists.items ?? [],
      recentlyPlayedRaw: recentlyPlayed.items ?? [],
      playlistTrackIds: playlistTaste.playlistTrackIds,
      playlists: playlistTaste.playlists,
    });
  }
}
