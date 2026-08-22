import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {
  isoWeekId,
  interestedInAllows,
  isTasteEmpty,
  scoreMusicCompatibility,
  SYNC_MIN_INTERVAL_MS,
  type MusicTaste,
} from "./musicCompatibility.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {spotifyClientId, spotifyClientSecret} from "./spotifyConfig.js";

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
  accessToken: string;
  refreshToken?: string;
  expiresAt: number;
  scope?: string;
  spotifyUserId?: string;
};

type NamedItem = {
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
  };
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

async function spotifyGet<T>(accessToken: string, path: string): Promise<T> {
  const response = await fetch(`https://api.spotify.com/v1${path}`, {
    headers: {Authorization: `Bearer ${accessToken}`},
  });
  if (response.status === 401) {
    throw new HttpsError("unauthenticated", "token-expired");
  }
  if (response.status === 403) {
    throw new HttpsError("permission-denied", "api-denied");
  }
  if (!response.ok) {
    throw new HttpsError("unavailable", "spotify-unavailable");
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
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function validAccessToken(uid: string): Promise<SpotifyTokenSet> {
  const existing = await loadSecrets(uid);
  if (!existing) {
    throw new HttpsError("failed-precondition", "not-connected");
  }
  if (existing.expiresAt > Date.now() + 15_000) {
    return existing;
  }
  if (!existing.refreshToken) {
    throw new HttpsError("unauthenticated", "token-expired");
  }
  const refreshed = await refreshAccessToken(existing.refreshToken);
  const next = {
    ...refreshed,
    spotifyUserId: existing.spotifyUserId,
  };
  await saveSecrets(uid, next);
  return next;
}

function summarizeTracks(items: Array<DocumentData>, limit = 20): NamedItem[] {
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
    out.push({
      id,
      name: String(track.name ?? ""),
      artist: artists.join(", "),
      image: imageUrl((track.album as DocumentData | undefined)?.images as Array<{url?: string}> | undefined),
    });
    if (out.length >= limit) break;
  }
  return out;
}

function summarizeArtists(items: Array<DocumentData>, limit = 20): NamedItem[] {
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

function genreShares(artists: NamedItem[]): Array<{name: string; percent: number}> {
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
  const [topTracks, topArtists, recentlyPlayed] = await Promise.all([
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/top/tracks?time_range=medium_term&limit=50"),
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/top/artists?time_range=medium_term&limit=50"),
    spotifyGet<Paging<DocumentData>>(tokens.accessToken, "/me/player/recently-played?limit=50"),
  ]);
  const tracks = summarizeTracks(topTracks.items ?? []);
  const artists = summarizeArtists(topArtists.items ?? []);
  const recent = summarizeTracks(recentlyPlayed.items ?? [], 20);
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
  };
  const summaryRef = db.doc(`users/${uid}/music/summary`);
  const existing = await summaryRef.get();
  const summary = {
    spotifyConnected: true,
    spotifyUserId: me.id,
    displayName: me.display_name ?? null,
    topTracks: tracks,
    topArtists: artists,
    recentlyPlayed: recent,
    musicProfile,
    lastSyncedAt: FieldValue.serverTimestamp(),
    ...(existing.data()?.connectedAt ? {} : {connectedAt: FieldValue.serverTimestamp()}),
  };
  await summaryRef.set(summary, {merge: true});
  await db.doc(`profiles/${uid}`).set({spotifyConnected: true}, {merge: true});
  await db.doc(`musicSpotifyIndex/${me.id}`).set({uid, updatedAt: FieldValue.serverTimestamp()});
  await saveSecrets(uid, {...tokens, spotifyUserId: me.id});
  return {
    ...summary,
    lastSyncedAt: new Date().toISOString(),
    connectedAt: new Date().toISOString(),
  };
}

function toClientProfile(data: DocumentData | undefined): Record<string, unknown> {
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
    musicProfile: data.musicProfile ?? {},
    lastSyncedAt: data.lastSyncedAt ?? null,
    connectedAt: data.connectedAt ?? null,
  };
}

export const spotifyLinkMusic = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const code = requireString(request.data?.code, "code");
  const codeVerifier = requireString(request.data?.codeVerifier, "codeVerifier");
  const redirectUri = requireString(request.data?.redirectUri, "redirectUri");
  const tokens = await exchangeAuthorizationCode({code, codeVerifier, redirectUri});
  const me = await spotifyGet<{id?: string}>(tokens.accessToken, "/me");
  if (!me.id) {
    throw new HttpsError("unauthenticated", "oauth");
  }
  const indexSnap = await db.doc(`musicSpotifyIndex/${me.id}`).get();
  if (indexSnap.exists && indexSnap.data()?.uid !== uid) {
    throw new HttpsError("failed-precondition", "account-exists");
  }
  const summary = await fetchAndStoreTaste(uid, {...tokens, spotifyUserId: me.id});
  return toClientProfile(summary);
});

export const getMusicAccount = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = requireUid(request);
    const snap = await db.doc(`users/${uid}/music/summary`).get();
    return toClientProfile(snap.data());
  },
);

export const syncSpotifyTaste = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const snap = await db.doc(`users/${uid}/music/summary`).get();
  const last = snap.data()?.lastSyncedAt as {toDate?: () => Date} | undefined;
  const lastDate = last && typeof last.toDate === "function" ? last.toDate() : null;
  if (lastDate && Date.now() - lastDate.getTime() < SYNC_MIN_INTERVAL_MS) {
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
    const snap = await db.doc(`users/${uid}/music/summary`).get();
    const spotifyUserId = snap.data()?.spotifyUserId as string | undefined;
    await db.doc(`spotifySecrets/${uid}`).delete().catch(() => undefined);
    await db.doc(`users/${uid}/music/summary`).delete().catch(() => undefined);
    if (spotifyUserId) {
      await db.doc(`musicSpotifyIndex/${spotifyUserId}`).delete().catch(() => undefined);
    }
    await db.doc(`profiles/${uid}`).set({spotifyConnected: false}, {merge: true});
    return {ok: true, spotifyConnected: false};
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
      const otherProfile = await db.doc(`profiles/${otherUid}`).get();
      if (!otherProfile.exists) continue;
      const data = otherProfile.data() ?? {};
      if (data.isDiscoverable === false) continue;
      const otherPrefs = (await db.doc(`userPreferences/${otherUid}`).get()).data() ?? {};
      if (!interestedInAllows(prefs.interestedIn, data.gender)) continue;
      if (!interestedInAllows(otherPrefs.interestedIn, viewerGender)) continue;
      scored.push({
        uid: otherUid,
        musicScore: music.score,
        sharedArtists: music.sharedArtists.slice(0, 3),
        sharedTracks: music.sharedTracks.slice(0, 3),
        sharedGenres: music.sharedGenres.slice(0, 3),
        sharedArtistCount: music.sharedArtists.length,
        sharedTrackCount: music.sharedTracks.length,
        sharedGenreCount: music.sharedGenres.length,
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
): Promise<ReturnType<typeof scoreMusicCompatibility> | null> {
  const [viewer, candidate] = await Promise.all([
    db.doc(`users/${viewerUid}/music/summary`).get(),
    db.doc(`users/${candidateUid}/music/summary`).get(),
  ]);
  const viewerTaste = tasteFromSummary(viewer.data());
  const candidateTaste = tasteFromSummary(candidate.data());
  if (!viewerTaste || !candidateTaste || isTasteEmpty(viewerTaste) || isTasteEmpty(candidateTaste)) {
    return null;
  }
  return scoreMusicCompatibility(viewerTaste, candidateTaste);
}
