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
  scoreMusicCompatibility,
  SYNC_MIN_INTERVAL_MS,
  type MusicTaste,
  type NamedMusicItem,
} from "./musicCompatibility.js";
import {
  normalizedToSummaryFields,
  tasteFromSummaryDocument,
} from "./music/normalize/normalizeMusicProfile.js";
import {SpotifyMusicProvider} from "./music/providers/spotifyMusicProvider.js";
import {calculateCompatibility} from "./compatibility/compatibilityEngine.js";
import {relationshipScoreForPair} from "./relationshipMatch.js";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {isUserPremium} from "./premium.js";
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

function tasteFromSummary(data: DocumentData | undefined): MusicTaste | null {
  return tasteFromSummaryDocument(data);
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

type RecentArtistPayload = {id: string; name: string; image: string | null};

function recentArtistsFromSummary(data: DocumentData | undefined): RecentArtistPayload[] {
  if (!data) return [];
  const profile = (data.musicProfile ?? {}) as DocumentData;
  const raw = profile.recentArtists;
  if (!Array.isArray(raw)) return [];
  const out: RecentArtistPayload[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const id = typeof (item as {id?: string}).id === "string" ? (item as {id: string}).id : "";
    const name = typeof (item as {name?: string}).name === "string" ? (item as {name: string}).name : "";
    if (!id || !name) continue;
    out.push({
      id,
      name,
      image: typeof (item as {image?: string}).image === "string" ? (item as {image: string}).image : null,
    });
  }
  return out.slice(0, 5);
}

async function overallCompatibilityForMatch(
  viewerUid: string,
  otherUid: string,
  musicScore: number,
): Promise<number | null> {
  const [viewerProfileSnap, otherProfileSnap, relationship] = await Promise.all([
    db.doc(`users/${viewerUid}`).get(),
    db.doc(`users/${otherUid}`).get(),
    relationshipScoreForPair(viewerUid, otherUid),
  ]);
  const viewerProfile = viewerProfileSnap.data();
  const otherProfile = otherProfileSnap.data();
  if (!viewerProfile || !otherProfile) {
    return null;
  }
  const compat = calculateCompatibility({
    viewerProfile,
    candidateProfile: otherProfile,
    relationship: relationship
      ? {
          score: relationship.score,
          alignedCount: relationship.alignedCount,
          sharedQuestionCount: relationship.sharedQuestionCount,
          topTopics: relationship.topTopics ?? [],
        }
      : null,
    musicScore,
  });
  return compat.overallScore;
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

const spotifyMusicProvider = new SpotifyMusicProvider(spotifyGet);

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

async function fetchAndStoreTaste(uid: string, tokens: SpotifyTokenSet): Promise<DocumentData> {
  const normalized = await spotifyMusicProvider.fetchTaste({
    accessToken: tokens.accessToken,
    scope: tokens.scope,
    providerUserId: tokens.spotifyUserId,
  });
  const summaryRef = db.doc(`users/${uid}/music/summary`);
  const existing = await summaryRef.get();
  const summary = {
    ...normalizedToSummaryFields(normalized),
    lastSyncedAt: FieldValue.serverTimestamp(),
    ...(existing.data()?.connectedAt ? {} : {connectedAt: FieldValue.serverTimestamp()}),
  };
  await summaryRef.set(summary, {merge: true});
  await db.doc(`profiles/${uid}`).set({spotifyConnected: true}, {merge: true});
  await db.doc(`musicSpotifyIndex/${normalized.providerUserId}`).set({
    uid,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await saveSecrets(uid, {...tokens, spotifyUserId: normalized.providerUserId});
  return {
    ...summary,
    lastSyncedAt: new Date().toISOString(),
    connectedAt: new Date().toISOString(),
  };
}

function toClientProfile(data: DocumentData | undefined): Record<string, unknown> {
  if (!data || (data.spotifyConnected !== true && data.connected !== true)) {
    return {spotifyConnected: false, connected: false, provider: null};
  }
  const musicProfile = (data.musicProfile ?? {}) as DocumentData;
  return {
    spotifyConnected: true,
    connected: true,
    provider: data.provider ?? "spotify",
    spotifyUserId: data.spotifyUserId ?? null,
    displayName: data.displayName ?? null,
    topTracks: data.topTracks ?? [],
    topArtists: data.topArtists ?? [],
    recentlyPlayed: data.recentlyPlayed ?? [],
    recentArtists: musicProfile.recentArtists ?? [],
    playlists: data.playlists ?? musicProfile.playlists ?? [],
    musicProfile,
    musicProfileVersion: data.musicProfileVersion ?? MUSIC_PROFILE_VERSION,
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

    const overallCompatibilityScore = await overallCompatibilityForMatch(
      uid,
      otherUid,
      enriched.score,
    );

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
      overallCompatibilityScore: overallCompatibilityScore ?? undefined,
      sharedTrackCount: enriched.sharedTracks.length,
      sharedArtistCount: enriched.sharedArtists.length,
      sharedRecentTrackCount: enriched.sharedRecentTracks.length,
      sharedTracks: sharedTracksDetailed,
      sharedArtists: sharedArtistsDetailed,
      sharedGenres: enriched.sharedGenres.slice(0, 5),
      musicInsights: enriched.insights,
      viewerRecentArtists: recentArtistsFromSummary(viewerSummary.data()),
      peerRecentArtists: recentArtistsFromSummary(otherSummary.data()),
    };
  },
);
