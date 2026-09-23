import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {
  enrichMusicCompatibility,
  isoWeekId,
  interestedInAllows,
  isTasteEmpty,
  MUSIC_PROFILE_VERSION,
  RECENT_UNIQUE_TRACK_LIMIT,
  scoreMusicCompatibility,
  SYNC_MIN_INTERVAL_MS,
  type MusicTaste,
  type NamedMusicItem,
} from "./musicCompatibility.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {isUserPremium} from "./premium.js";
import {spotifyClientId, spotifyClientSecret} from "./spotifyConfig.js";
import {
  resolveIndexOwnership,
  resolveSpotifyIdentity,
  type IndexLookup,
} from "./spotifyIdentity.js";
import {
  buildPublicMusicProfile,
  emptyPublicMusicProfile,
  MAX_PUBLIC_ARTISTS,
  MAX_PUBLIC_TRACKS,
  normalizeSelectionIds,
  PublicMusicValidationError,
  reconcilePublicMusicProfile,
  toPublicMusicCard,
} from "./spotifyMusicProfile.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
  secrets: [spotifyClientSecret],
};

type SpotifyTokenSet = {
  /** Immutable Spotify account id when the API supplied one. */
  spotifyAccountId?: string | null;
  /** Every index key this account is reachable under. */
  indexKeys?: string[];
  accessToken: string;
  refreshToken?: string;
  expiresAt: number;
  scope?: string;
  spotifyUserId?: string;
};

type NamedItem = {
  playedAt?: string;
  id: string;
  name: string;
  artist?: string;
  image?: string | null;
  genres?: string[];
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpsError("invalid-argument", field);
  }
  return value.trim();
}

function credentials(): {clientId: string; clientSecret: string} {
  const clientId = process.env.SPOTIFY_CLIENT_ID || spotifyClientId.value();
  const clientSecret = process.env.SPOTIFY_CLIENT_SECRET || spotifyClientSecret.value();
  if (!clientId || !clientSecret) {
    throw new HttpsError("failed-precondition", "not-configured");
  }
  return {clientId, clientSecret};
}

function basicAuth(clientId: string, clientSecret: string): string {
  return `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`;
}

function imageUrl(images: Array<{url?: string}> | undefined): string | null {
  return images?.find((item) => typeof item.url === "string" && item.url)?.url ?? null;
}

function asStringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
}

function tasteFromSummary(data: DocumentData | undefined): MusicTaste | null {
  if (!data || data.spotifyConnected !== true) return null;
  const profile = (data.musicProfile ?? {}) as DocumentData;
  const genres = Array.isArray(profile.genres)
    ? profile.genres
      .map((item) => (item && typeof item === "object" ? String((item as {name?: string}).name ?? "") : String(item)))
      .filter((name) => name.length > 0)
    : asStringList(profile.genreNames);
  return {
    trackIds: asStringList(profile.trackIds),
    artistIds: asStringList(profile.artistIds),
    genres,
    recentTrackIds: asStringList(profile.recentTrackIds),
    recentArtistIds: asStringList(profile.recentArtistIds),
    playlistTrackIds: asStringList(profile.playlistTrackIds),
  };
}

function catalogFromSummary(data: DocumentData | undefined): NamedMusicItem[] {
  if (!data) return [];
  const out: NamedMusicItem[] = [];
  for (const key of ["topTracks", "recentlyPlayed"] as const) {
    const list = Array.isArray(data[key]) ? data[key] : [];
    for (const item of list) {
      if (!item || typeof item !== "object") continue;
      const id = String((item as NamedItem).id ?? "");
      const name = String((item as NamedItem).name ?? "");
      if (!id || !name) continue;
      out.push({
        id,
        name,
        artist: typeof (item as NamedItem).artist === "string" ? (item as NamedItem).artist : undefined,
      });
    }
  }
  const artists = Array.isArray(data.topArtists) ? data.topArtists : [];
  for (const item of artists) {
    if (!item || typeof item !== "object") continue;
    const id = String((item as NamedItem).id ?? "");
    const name = String((item as NamedItem).name ?? "");
    if (!id || !name) continue;
    out.push({id, name});
  }
  return out;
}

export function hasPlaylistScope(scope: string | undefined): boolean {
  if (!scope) return false;
  return scope.includes("playlist-read-private") || scope.includes("playlist-read-collaborative");
}

async function fetchPlaylistTaste(
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
    const page = await spotifyGet<PlaylistPage>(
      accessToken,
      "/me/playlists?limit=10",
    );
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

async function exchangeAuthorizationCode(input: {
  code: string;
  codeVerifier: string;
  redirectUri: string;
}): Promise<SpotifyTokenSet> {
  const {clientId, clientSecret} = credentials();
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code: input.code,
    redirect_uri: input.redirectUri,
    client_id: clientId,
    code_verifier: input.codeVerifier,
  });
  const response = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: basicAuth(clientId, clientSecret),
    },
    body,
  });
  if (!response.ok) {
    throw new HttpsError("unauthenticated", "oauth");
  }
  const json = await response.json() as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
  };
  if (!json.access_token) {
    throw new HttpsError("unauthenticated", "oauth");
  }
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    expiresAt: Date.now() + Math.max(30, Number(json.expires_in ?? 3600) - 60) * 1000,
    scope: json.scope,
  };
}

async function refreshAccessToken(refreshToken: string): Promise<SpotifyTokenSet> {
  const {clientId, clientSecret} = credentials();
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: clientId,
  });
  const response = await fetch("https://accounts.spotify.com/api/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: basicAuth(clientId, clientSecret),
    },
    body,
  });
  if (!response.ok) {
    throw new HttpsError("unauthenticated", "token-expired");
  }
  const json = await response.json() as {
    access_token?: string;
    refresh_token?: string;
    expires_in?: number;
    scope?: string;
  };
  if (!json.access_token) {
    throw new HttpsError("unauthenticated", "token-expired");
  }
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token ?? refreshToken,
    expiresAt: Date.now() + Math.max(30, Number(json.expires_in ?? 3600) - 60) * 1000,
    scope: json.scope,
  };
}

/**
 * Maps a Spotify Web API status onto the error the client sees. 401 means
 * the stored token died, 403 means the grant does not cover the call, and
 * anything else non-2xx is an upstream outage — three different UI states.
 */
export function spotifyErrorForStatus(status: number): HttpsError | null {
  if (status === 401) {
    return new HttpsError("unauthenticated", "token-expired");
  }
  if (status === 403) {
    return new HttpsError("permission-denied", "api-denied");
  }
  if (status < 200 || status >= 300) {
    return new HttpsError("unavailable", "spotify-unavailable");
  }
  return null;
}

async function spotifyGet<T>(accessToken: string, path: string): Promise<T> {
  const response = await fetch(`https://api.spotify.com/v1${path}`, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  const failure = spotifyErrorForStatus(response.status);
  if (failure) {
    throw failure;
  }
  return await response.json() as T;
}

async function loadSecrets(uid: string): Promise<SpotifyTokenSet | null> {
  const snap = await db.doc(`spotifySecrets/${uid}`).get();
  if (!snap.exists) return null;
  const data = snap.data() ?? {};
  if (typeof data.accessToken !== "string") return null;
  return {
    accessToken: data.accessToken,
    refreshToken: typeof data.refreshToken === "string" ? data.refreshToken : undefined,
    expiresAt: typeof data.expiresAt === "number" ? data.expiresAt : 0,
    scope: typeof data.scope === "string" ? data.scope : undefined,
    spotifyUserId: typeof data.spotifyUserId === "string" ? data.spotifyUserId : undefined,
  };
}

async function saveSecrets(uid: string, tokens: SpotifyTokenSet): Promise<void> {
  await db.doc(`spotifySecrets/${uid}`).set({
    accessToken: tokens.accessToken,
    refreshToken: tokens.refreshToken ?? null,
    expiresAt: tokens.expiresAt,
    scope: tokens.scope ?? null,
    spotifyUserId: tokens.spotifyUserId ?? null,
    spotifyAccountId: tokens.spotifyAccountId ?? null,
    indexKeys: tokens.indexKeys ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  });
}

/** Refresh a little before the real expiry so an in-flight call survives. */
export const TOKEN_REFRESH_SKEW_MS = 15_000;

export type TokenAction = "not-connected" | "use" | "refresh" | "expired";

/**
 * Decides what to do with the stored Spotify tokens. Split out from the
 * callable so the lifecycle — live token, refreshable token, and a dead
 * token with no refresh grant — is testable without Firestore.
 */
export function planTokenUse(
  existing: {refreshToken?: string; expiresAt?: number} | null | undefined,
  now: number = Date.now(),
): TokenAction {
  if (!existing) {
    return "not-connected";
  }
  if ((existing.expiresAt ?? 0) > now + TOKEN_REFRESH_SKEW_MS) {
    return "use";
  }
  if (!existing.refreshToken) {
    return "expired";
  }
  return "refresh";
}

async function validAccessToken(uid: string): Promise<SpotifyTokenSet> {
  const existing = await loadSecrets(uid);
  const action = planTokenUse(existing);
  if (action === "not-connected") {
    throw new HttpsError("failed-precondition", "not-connected");
  }
  if (action === "expired") {
    throw new HttpsError("unauthenticated", "token-expired");
  }
  const tokens = existing as SpotifyTokenSet;
  if (action === "use") {
    return tokens;
  }
  const refreshed = await refreshAccessToken(tokens.refreshToken as string);
  const next = {
    ...refreshed,
    spotifyUserId: tokens.spotifyUserId,
  };
  await saveSecrets(uid, next);
  return next;
}

export function summarizeTracks(items: Array<DocumentData>, limit = 20): NamedItem[] {
  const out: NamedItem[] = [];
  const seen = new Set<string>();
  for (const item of items) {
    const track = (item.track ?? item) as DocumentData;
    const id = typeof track.id === "string" ? track.id : "";
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const artists = Array.isArray(track.artists)
      ? track.artists.map((artist: DocumentData) => String(artist.name ?? "")).filter(Boolean)
      : [];
    const playedAt = typeof item.played_at === "string" ? item.played_at : undefined;
    out.push({
      id,
      name: String(track.name ?? ""),
      artist: artists.join(", "),
      image: imageUrl((track.album as DocumentData | undefined)?.images as Array<{url?: string}> | undefined),
      ...(playedAt ? {playedAt} : {}),
    });
    if (out.length >= limit) break;
  }
  return out;
}

export function summarizeArtists(items: Array<DocumentData>, limit = 20): NamedItem[] {
  const out: NamedItem[] = [];
  for (const item of items) {
    const id = typeof item.id === "string" ? item.id : "";
    if (!id) continue;
    out.push({
      id,
      name: String(item.name ?? ""),
      image: imageUrl(item.images as Array<{url?: string}> | undefined),
      genres: asStringList(item.genres),
    });
    if (out.length >= limit) break;
  }
  return out;
}

export function genreShares(artists: NamedItem[]): Array<{name: string; percent: number}> {
  const counts = new Map<string, number>();
  for (const artist of artists) {
    for (const genre of artist.genres ?? []) {
      const key = genre.trim().toLowerCase();
      if (!key) continue;
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  }
  const total = [...counts.values()].reduce((sum, value) => sum + value, 0);
  if (total === 0) return [];
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([name, count]) => ({
      name,
      percent: Math.max(1, Math.round((count / total) * 100)),
    }));
}

async function fetchAndStoreTaste(uid: string, tokens: SpotifyTokenSet): Promise<DocumentData> {
  type Me = {id?: string; display_name?: string};
  type Paging<T> = {items?: T[]};
  const me = await spotifyGet<Me>(tokens.accessToken, "/me");
  if (!me.id) {
    throw new HttpsError("unauthenticated", "oauth");
  }
  const [topTracks, topArtists, recentlyPlayed, playlistTaste] = await Promise.all([
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/top/tracks?time_range=medium_term&limit=50"),
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/top/artists?time_range=medium_term&limit=50"),
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/player/recently-played?limit=50"),
    fetchPlaylistTaste(tokens.accessToken, tokens.scope),
  ]);
  const tracks = summarizeTracks(topTracks.items ?? []);
  const artists = summarizeArtists(topArtists.items ?? []);
  // Last N unique recently-played tracks by Spotify track id (no string-name matching).
  const recent = summarizeTracks(recentlyPlayed.items ?? [], RECENT_UNIQUE_TRACK_LIMIT);
  const genres = genreShares(artists);
  const musicProfile = {
    genres,
    genreNames: genres.map((item) => item.name),
    artistIds: artists.map((item) => item.id),
    trackIds: tracks.map((item) => item.id),
    recentTrackIds: recent.map((item) => item.id),
    recentArtistIds: [...new Set(
      (recentlyPlayed.items ?? [])
        .flatMap((item) => {
          const track = (item.track ?? {}) as DocumentData;
          const list = Array.isArray(track.artists) ? track.artists : [];
          return list.map((artist: DocumentData) => String(artist.id ?? "")).filter(Boolean);
        }),
    )].slice(0, 30),
    playlistTrackIds: playlistTaste.playlistTrackIds,
    playlists: playlistTaste.playlists,
    // Compact fingerprint used by Music Compatibility (IDs only).
    musicFingerprint: {
      version: MUSIC_PROFILE_VERSION,
      trackIds: tracks.map((item) => item.id),
      artistIds: artists.map((item) => item.id),
      recentTrackIds: recent.map((item) => item.id),
      genreNames: genres.map((item) => item.name),
    },
  };
  const summaryRef = db.doc(`users/${uid}/music/summary`);
  const existing = await summaryRef.get();
  const accountId = tokens.spotifyAccountId ??
    (existing.data()?.spotifyAccountId as string | undefined) ?? null;
  const summary = {
    spotifyConnected: true,
    spotifyUserId: me.id,
    spotifyAccountId: accountId,
    displayName: me.display_name ?? null,
    topTracks: tracks,
    topArtists: artists,
    recentlyPlayed: recent,
    playlists: playlistTaste.playlists,
    musicProfile,
    musicProfileVersion: MUSIC_PROFILE_VERSION,
    lastSyncedAt: FieldValue.serverTimestamp(),
    ...(existing.data()?.connectedAt ? {} : {connectedAt: FieldValue.serverTimestamp()}),
  };
  await summaryRef.set(summary, {merge: true});

  // A re-sync must not rewrite what the member chose to publish. Their
  // selections are re-resolved against the new import: still-present items
  // keep their place with refreshed metadata, and anything Spotify no
  // longer returns drops out because nothing can vouch for it.
  const profileRef = db.doc(`profiles/${uid}`);
  const profileSnap = await profileRef.get();
  const publicMusic = reconcilePublicMusicProfile(
    profileSnap.data()?.publicMusic,
    {topArtists: artists, topTracks: tracks, musicProfile},
  );
  await profileRef.set(
    {
      spotifyConnected: true,
      publicMusic: {...publicMusic, updatedAt: FieldValue.serverTimestamp()},
    },
    {merge: true},
  );

  for (const key of tokens.indexKeys ?? [me.id]) {
    await db.doc(`musicSpotifyIndex/${key}`).set(
      {
        uid,
        spotifyAccountId: accountId,
        spotifyUserId: me.id,
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  }
  await saveSecrets(uid, {...tokens, spotifyUserId: me.id});
  return {
    ...summary,
    lastSyncedAt: new Date().toISOString(),
    connectedAt: new Date().toISOString(),
  };
}

export function toClientProfile(data: DocumentData | undefined): Record<string, unknown> {
  if (!data || data.spotifyConnected !== true) {
    return {spotifyConnected: false, connected: false};
  }
  return {
    spotifyConnected: true,
    connected: true,
    spotifyUserId: data.spotifyUserId ?? null,
    displayName: data.displayName ?? null,
    topTracks: data.topTracks ?? [],
    topArtists: data.topArtists ?? [],
    recentlyPlayed: data.recentlyPlayed ?? [],
    playlists: data.playlists ?? data.musicProfile?.playlists ?? [],
    musicProfile: data.musicProfile ?? {},
    musicProfileVersion: data.musicProfileVersion ?? MUSIC_PROFILE_VERSION,
    lastSyncedAt: data.lastSyncedAt ?? null,
    connectedAt: data.connectedAt ?? null,
  };
}

/** Re-export so callers have one import site for the public card shape. */
export {toPublicMusicCard};

/**
 * A Spotify account belongs to one Mevora uid. Linking one that another
 * account already holds is rejected instead of moving the ownership.
 */
export function assertMusicOwnership(
  index: {exists: boolean; uid?: unknown},
  uid: string,
): void {
  if (index.exists && index.uid !== uid) {
    throw new HttpsError("failed-precondition", "account-exists");
  }
}

/**
 * Everything a disconnect must remove, plus the profile state to reset.
 *
 * `extraIndexKeys` covers accounts reachable under both the legacy Spotify
 * user id and the newer immutable account id: leaving either document behind
 * would keep the account looking owned and block a future re-link.
 */
export function disconnectPlan(
  uid: string,
  spotifyUserId?: string | null,
  extraIndexKeys: Array<string | null | undefined> = [],
) {
  const deletes = [`spotifySecrets/${uid}`, `users/${uid}/music/summary`];
  const seen = new Set<string>();
  for (const key of [spotifyUserId, ...extraIndexKeys]) {
    if (!key || seen.has(key)) {
      continue;
    }
    seen.add(key);
    deletes.push(`musicSpotifyIndex/${key}`);
  }
  return {
    deletes,
    profilePath: `profiles/${uid}`,
    profileData: {
      spotifyConnected: false,
      publicMusic: emptyPublicMusicProfile(),
    },
  };
}

/** Spotify is rate limited and the taste barely moves — throttle re-syncs. */
export function isSyncThrottled(
  lastSyncedAt: Date | null,
  now: number = Date.now(),
): boolean {
  if (!lastSyncedAt) {
    return false;
  }
  return now - lastSyncedAt.getTime() < SYNC_MIN_INTERVAL_MS;
}

export const spotifyLinkMusic = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const code = requireString(request.data?.code, "code");
  const codeVerifier = requireString(request.data?.codeVerifier, "codeVerifier");
  const redirectUri = requireString(request.data?.redirectUri, "redirectUri");
  const tokens = await exchangeAuthorizationCode({code, codeVerifier, redirectUri});
  const me = await spotifyGet<{id?: string; account_id?: string}>(
    tokens.accessToken,
    "/me",
  );
  const identity = resolveSpotifyIdentity(me);
  if (!identity) {
    throw new HttpsError("unauthenticated", "oauth");
  }
  // Both the legacy and the account_id key are checked so an account linked
  // before Spotify shipped account_id is still recognised as owned.
  const lookups: IndexLookup[] = await Promise.all(
    identity.lookupKeys.map(async (key) => {
      const snap = await db.doc(`musicSpotifyIndex/${key}`).get();
      return {key, exists: snap.exists, uid: snap.data()?.uid};
    }),
  );
  const ownership = resolveIndexOwnership(lookups);
  assertMusicOwnership(
    ownership.ownerUid === null
      ? {exists: false}
      : {exists: true, uid: ownership.ownerUid},
    uid,
  );
  const summary = await fetchAndStoreTaste(uid, {
    ...tokens,
    spotifyUserId: identity.userId,
    spotifyAccountId: identity.accountId,
    indexKeys: identity.lookupKeys,
  });
  return toClientProfile(summary);
});

export const getMusicAccount = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const [snap, profileSnap] = await Promise.all([
      db.doc(`users/${uid}/music/summary`).get(),
      db.doc(`profiles/${uid}`).get(),
    ]);
    const account = toClientProfile(snap.data());
    // Owners see their own selection so the Music tab can pre-tick it.
    const stored = profileSnap.data()?.publicMusic;
    return {
      ...account,
      publicMusic: stored
        ? {
          enabled: stored.enabled === true,
          artists: Array.isArray(stored.artists) ? stored.artists : [],
          tracks: Array.isArray(stored.tracks) ? stored.tracks : [],
          genres: Array.isArray(stored.genres) ? stored.genres : [],
        }
        : emptyPublicMusicProfile(),
    };
  },
);

export const syncSpotifyTaste = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const snap = await db.doc(`users/${uid}/music/summary`).get();
  const last = snap.data()?.lastSyncedAt as {toDate?: () => Date} | undefined;
  const lastDate = last && typeof last.toDate === "function" ? last.toDate() : null;
  if (isSyncThrottled(lastDate)) {
    return {...toClientProfile(snap.data()), throttled: true};
  }
  const tokens = await validAccessToken(uid);
  const summary = await fetchAndStoreTaste(uid, tokens);
  return toClientProfile(summary);
});

export const disconnectMusicAccount = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const [snap, secretSnap] = await Promise.all([
      db.doc(`users/${uid}/music/summary`).get(),
      db.doc(`spotifySecrets/${uid}`).get(),
    ]);
    const spotifyUserId = snap.data()?.spotifyUserId as string | undefined;
    const accountId = snap.data()?.spotifyAccountId as string | undefined;
    const storedKeys = secretSnap.data()?.indexKeys as string[] | undefined;
    const plan = disconnectPlan(uid, spotifyUserId, [
      ...(storedKeys ?? []),
      ...(accountId ? [accountId] : []),
    ]);
    for (const docPath of plan.deletes) {
      await db.doc(docPath).delete().catch(() => undefined);
    }
    // The public card goes with the connection: leaving it would keep a
    // Music Taste section on the dating profile of somebody who just
    // disconnected Spotify.
    await db.doc(plan.profilePath).set(plan.profileData, {merge: true});
    return {ok: true, spotifyConnected: false};
  },
);

/**
 * Publishes the member's chosen artists and tracks to their dating profile.
 *
 * The client sends identifiers and a visibility flag — never names, artwork
 * or links. Everything rendered to other members is resolved here from the
 * caller's own imported Spotify data, so a selection cannot be fabricated and
 * cannot reference music the caller never listened to. The target uid comes
 * from the auth context, so there is no cross-user write path at all.
 */
export const updatePublicMusicProfile = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const summarySnap = await db.doc(`users/${uid}/music/summary`).get();
    if (summarySnap.data()?.spotifyConnected !== true) {
      throw new HttpsError("failed-precondition", "not-connected");
    }

    let profile;
    try {
      profile = buildPublicMusicProfile({
        enabled: request.data?.enabled !== false,
        artistIds: normalizeSelectionIds(
          request.data?.artistIds,
          MAX_PUBLIC_ARTISTS,
          "artists",
        ),
        trackIds: normalizeSelectionIds(
          request.data?.trackIds,
          MAX_PUBLIC_TRACKS,
          "tracks",
        ),
        summary: summarySnap.data(),
      });
    } catch (error) {
      if (error instanceof PublicMusicValidationError) {
        throw new HttpsError("invalid-argument", error.reason, {
          mevoraCode: error.reason,
        });
      }
      throw error;
    }

    await db.doc(`profiles/${uid}`).set(
      {publicMusic: {...profile, updatedAt: FieldValue.serverTimestamp()}},
      {merge: true},
    );
    return {publicMusic: profile};
  },
);

export const getSameTasteProfiles = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const viewerSnap = await db.doc(`users/${uid}/music/summary`).get();
    const viewerTaste = tasteFromSummary(viewerSnap.data());
    if (!viewerTaste || isTasteEmpty(viewerTaste)) {
      return {items: []};
    }
    const [prefsSnap, profileSnap, blockedSnap, passedSnap] = await Promise.all([
      db.doc(`userPreferences/${uid}`).get(),
      db.doc(`profiles/${uid}`).get(),
      db.collection(`users/${uid}/blockedUsers`).get(),
      db.collection(`users/${uid}/passedUsers`).get(),
    ]);
    const blocked = new Set(blockedSnap.docs.map((doc) => doc.id));
    const passed = new Set(passedSnap.docs.map((doc) => doc.id));
    const prefs = prefsSnap.data() ?? {};
    const viewerGender = profileSnap.data()?.gender as string | undefined;
    const musicSnap = await db.collectionGroup("music")
      .where("spotifyConnected", "==", true)
      .limit(80)
      .get();
    const otherUids: string[] = [];
    for (const doc of musicSnap.docs) {
      const otherUid = doc.ref.parent.parent?.id;
      if (!otherUid || otherUid === uid || blocked.has(otherUid) || passed.has(otherUid)) {
        continue;
      }
      otherUids.push(otherUid);
    }
    const lastActiveByUid = await loadLastActiveAt(db, otherUids);
    const scored: Array<Record<string, unknown>> = [];
    for (const doc of musicSnap.docs) {
      const otherUid = doc.ref.parent.parent?.id;
      if (!otherUid || otherUid === uid || blocked.has(otherUid) || passed.has(otherUid)) {
        continue;
      }
      if (!isActiveForDiscovery(lastActiveByUid.get(otherUid))) continue;
      const otherTaste = tasteFromSummary(doc.data());
      if (!otherTaste || isTasteEmpty(otherTaste)) continue;
      const music = scoreMusicCompatibility(viewerTaste, otherTaste);
      if (music.score <= 0) continue;
      const enriched = enrichMusicCompatibility(music, [
        ...catalogFromSummary(viewerSnap.data()),
        ...catalogFromSummary(doc.data()),
      ]);
      const otherProfile = await db.doc(`profiles/${otherUid}`).get();
      if (!otherProfile.exists) continue;
      const data = otherProfile.data() ?? {};
      if (data.isDiscoverable === false) continue;
      const otherPrefs = (await db.doc(`userPreferences/${otherUid}`).get()).data() ?? {};
      if (!interestedInAllows(prefs.interestedIn, data.gender)) continue;
      if (!interestedInAllows(otherPrefs.interestedIn, viewerGender)) continue;
      scored.push({
        uid: otherUid,
        musicScore: enriched.score,
        sharedArtists: enriched.sharedArtistNames.slice(0, 5),
        sharedTracks: enriched.sharedTrackNames.slice(0, 5),
        sharedGenres: enriched.sharedGenres.slice(0, 3),
        sharedArtistCount: enriched.sharedArtists.length,
        sharedTrackCount: enriched.sharedTracks.length,
        sharedGenreCount: enriched.sharedGenres.length,
        sharedPlaylistTrackCount: enriched.sharedPlaylistTracks.length,
        sharedRecentTrackCount: enriched.sharedRecentTracks.length,
        musicInsights: enriched.insights,
        musicBreakdown: enriched.breakdown,
        profile: {
          uid: otherUid,
          displayName: data.displayName ?? "",
          age: data.age ?? null,
          gender: data.gender ?? null,
          bio: data.bio ?? null,
          photos: data.photos ?? [],
          interests: data.interests ?? [],
          city: data.city ?? null,
        },
      });
    }
    scored.sort((a, b) => Number(b.musicScore) - Number(a.musicScore));
    return {items: scored.slice(0, 20)};
  },
);

export const getWeeklyMusicStats = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    requireUid(request);
    const weekId = isoWeekId();
    const snap = await db.doc(`weeklyMusicStats/${weekId}`).get();
    if (!snap.exists) {
      return {weekId, tracks: []};
    }
    return {weekId, tracks: snap.data()?.tracks ?? []};
  },
);

export const aggregateWeeklyMusicStats = onSchedule(
  {schedule: "every monday 06:00", region: "europe-west1", timeZone: "Europe/Istanbul"},
  async () => {
    const weekId = isoWeekId();
    const snap = await db.collectionGroup("music")
      .where("spotifyConnected", "==", true)
      .limit(200)
      .get();
    const counts = new Map<string, {id: string; name: string; artist: string; image?: string | null; playCount: number}>();
    for (const doc of snap.docs) {
      const recent = Array.isArray(doc.data().recentlyPlayed) ? doc.data().recentlyPlayed : [];
      for (const item of recent) {
        if (!item || typeof item !== "object") continue;
        const id = String((item as NamedItem).id ?? "");
        const name = String((item as NamedItem).name ?? "");
        if (!id || !name) continue;
        const current = counts.get(id) ?? {
          id,
          name,
          artist: String((item as NamedItem).artist ?? ""),
          image: (item as NamedItem).image ?? null,
          playCount: 0,
        };
        current.playCount += 1;
        counts.set(id, current);
      }
    }
    const tracks = [...counts.values()]
      .sort((a, b) => b.playCount - a.playCount)
      .slice(0, 10);
    await db.doc(`weeklyMusicStats/${weekId}`).set({
      weekId,
      tracks,
      updatedAt: FieldValue.serverTimestamp(),
    });
    logger.info("weekly music stats aggregated", {weekId, count: tracks.length});
  },
);

export async function musicScoreForPair(
  viewerUid: string,
  candidateUid: string,
): Promise<(ReturnType<typeof enrichMusicCompatibility>) | null> {
  const [viewer, candidate] = await Promise.all([
    db.doc(`users/${viewerUid}/music/summary`).get(),
    db.doc(`users/${candidateUid}/music/summary`).get(),
  ]);
  const viewerTaste = tasteFromSummary(viewer.data());
  const candidateTaste = tasteFromSummary(candidate.data());
  if (!viewerTaste || !candidateTaste || isTasteEmpty(viewerTaste) || isTasteEmpty(candidateTaste)) {
    return null;
  }
  const scored = scoreMusicCompatibility(viewerTaste, candidateTaste);
  return enrichMusicCompatibility(scored, [
    ...catalogFromSummary(viewer.data()),
    ...catalogFromSummary(candidate.data()),
  ]);
}

/**
 * Match-only music compatibility. Hidden unless both users are Spotify-connected
 * with usable taste data and share an active match. Premium unlocks detailed lists.
 */
export const getMatchMusicCompatibility = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const matchId = requireString(request.data?.matchId, "matchId");
    const matchSnap = await db.doc(`matches/${matchId}`).get();
    if (!matchSnap.exists || matchSnap.data()?.isActive !== true) {
      return {available: false, reason: "no_match"};
    }
    const userIds = (matchSnap.data()?.userIds as string[]) ?? [];
    if (!userIds.includes(uid) || userIds.length !== 2) {
      throw new HttpsError("permission-denied", "not-participant");
    }
    const otherUid = userIds.find((id) => id !== uid) ?? "";
    if (!otherUid) {
      return {available: false, reason: "no_match"};
    }

    const [viewerSummary, otherSummary] = await Promise.all([
      db.doc(`users/${uid}/music/summary`).get(),
      db.doc(`users/${otherUid}/music/summary`).get(),
    ]);
    const viewerTaste = tasteFromSummary(viewerSummary.data());
    const otherTaste = tasteFromSummary(otherSummary.data());
    if (
      !viewerTaste ||
      !otherTaste ||
      isTasteEmpty(viewerTaste) ||
      isTasteEmpty(otherTaste)
    ) {
      return {available: false, reason: "data_unavailable"};
    }

    const scored = scoreMusicCompatibility(viewerTaste, otherTaste);
    if (scored.score <= 0) {
      return {available: false, reason: "data_unavailable"};
    }
    const enriched = enrichMusicCompatibility(scored, [
      ...catalogFromSummary(viewerSummary.data()),
      ...catalogFromSummary(otherSummary.data()),
    ]);

    const premium = await isUserPremium(uid);
    if (!premium) {
      return {
        available: true,
        premiumRequired: true,
        teaser: true,
      };
    }

    const mediaById = new Map<string, {name: string; artist: string; image: string | null}>();
    for (const data of [viewerSummary.data(), otherSummary.data()]) {
      for (const key of ["topTracks", "recentlyPlayed", "topArtists"] as const) {
        const list = Array.isArray(data?.[key]) ? data![key] : [];
        for (const raw of list) {
          if (!raw || typeof raw !== "object") continue;
          const item = raw as DocumentData;
          const id = typeof item.id === "string" ? item.id : "";
          if (!id || mediaById.has(id)) continue;
          mediaById.set(id, {
            name: String(item.name ?? ""),
            artist: String(item.artist ?? ""),
            image: typeof item.image === "string" ? item.image : null,
          });
        }
      }
    }

    const sharedTracksDetailed = enriched.sharedTracks.slice(0, 8).map((id) => {
      const hit = mediaById.get(id);
      return {
        id,
        name: hit?.name || enriched.sharedTrackNames.find((_, i) => enriched.sharedTracks[i] === id) || id,
        artist: hit?.artist ?? "",
        image: hit?.image ?? null,
      };
    });
    const sharedArtistsDetailed = enriched.sharedArtists.slice(0, 8).map((id) => {
      const hit = mediaById.get(id);
      return {
        id,
        name: hit?.name || enriched.sharedArtistNames.find((_, i) => enriched.sharedArtists[i] === id) || id,
        image: hit?.image ?? null,
      };
    });

    return {
      available: true,
      premiumRequired: false,
      teaser: false,
      score: enriched.score,
      sharedTrackCount: enriched.sharedTracks.length,
      sharedArtistCount: enriched.sharedArtists.length,
      sharedRecentTrackCount: enriched.sharedRecentTracks.length,
      sharedTracks: sharedTracksDetailed,
      sharedArtists: sharedArtistsDetailed,
      sharedGenres: enriched.sharedGenres.slice(0, 5),
      musicInsights: enriched.insights,
    };
  },
);
