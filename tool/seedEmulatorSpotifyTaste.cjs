#!/usr/bin/env node
/**
 * Seeds imported Spotify taste for the QA users, so the music experience can
 * be driven end to end without a live Spotify authorization.
 *
 * What this does NOT do: it never fakes the OAuth handshake or writes tokens.
 * `spotifySecrets` stays empty, so anything that needs a real access token —
 * connect, re-sync — still goes to Spotify for real. What it seeds is the
 * *result* of an import: the private `users/{uid}/music/summary` document and
 * the `spotifyConnected` flag, which is what the selection screen, the public
 * card, the profile section and music compatibility all read.
 *
 * The two users are given a deliberate, known overlap so compatibility
 * assertions have an expected answer rather than a plausible-looking one:
 *
 *   shared artists : The Weeknd, Arctic Monkeys      (2)
 *   shared tracks  : Blinding Lights, Do I Wanna Know (2)
 *   shared genres  : r&b, indie, alternative
 *
 * User C is seeded with almost nothing, for the limited-data state.
 *
 * Usage, from the repo root (PowerShell):
 *
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   node tool/seedEmulatorSpotifyTaste.cjs [--published] [--reset]
 *
 *   --published  also publishes a 3+3 card for user A, as if they had been
 *                through the selection screen. Without it A is connected with
 *                nothing published, which is where the selection QA starts.
 *   --reset      clears every Spotify artifact for the QA users instead of
 *                seeding, leaving them genuinely disconnected.
 *
 * Run tool/seedEmulatorQaUsers.cjs first: this script adds music to accounts
 * that already exist and refuses to invent them.
 */

const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = "mevora-d6ed0";
const PUBLISHED = process.argv.slice(2).includes("--published");
const RESET = process.argv.slice(2).includes("--reset");

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
if (!firestoreHost) {
  console.error(
    "REFUSING TO RUN: FIRESTORE_EMULATOR_HOST must be set. This script only " +
      "ever writes to the Emulator Suite.",
  );
  process.exit(1);
}
if (!/^(127\.0\.0\.1|localhost|0\.0\.0\.0|10\.0\.2\.2):\d+$/.test(firestoreHost)) {
  console.error(
    `REFUSING TO RUN: FIRESTORE_EMULATOR_HOST="${firestoreHost}" is not a ` +
      "local emulator host.",
  );
  process.exit(1);
}

const fromFunctions = createRequire(
  path.join(__dirname, "..", "functions", "package.json"),
);
let admin;
try {
  admin = fromFunctions("firebase-admin");
} catch (_) {
  console.error("firebase-admin not found — run: npm --prefix functions ci");
  process.exit(1);
}

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const {FieldValue} = admin.firestore;

const ARTISTS = {
  weeknd: {id: "sp_art_weeknd", name: "The Weeknd", image: "https://i.scdn.co/image/qa-weeknd", genres: ["r&b", "pop"]},
  arctic: {id: "sp_art_arctic", name: "Arctic Monkeys", image: "https://i.scdn.co/image/qa-arctic", genres: ["indie", "alternative"]},
  lana: {id: "sp_art_lana", name: "Lana Del Rey", image: "https://i.scdn.co/image/qa-lana", genres: ["indie", "pop"]},
  tame: {id: "sp_art_tame", name: "Tame Impala", image: "https://i.scdn.co/image/qa-tame", genres: ["psychedelic", "alternative"]},
  radiohead: {id: "sp_art_radiohead", name: "Radiohead", image: null, genres: ["alternative", "rock"]},
  sza: {id: "sp_art_sza", name: "SZA", image: "https://i.scdn.co/image/qa-sza", genres: ["r&b"]},
  tyler: {id: "sp_art_tyler", name: "Tyler, The Creator", image: null, genres: ["hip hop", "alternative"]},
  fkatwigs: {id: "sp_art_fka", name: "FKA twigs", image: null, genres: ["r&b", "electronic"]},
  boniver: {id: "sp_art_boniver", name: "Bon Iver", image: null, genres: ["indie", "folk"]},
  portishead: {id: "sp_art_portis", name: "Portishead", image: null, genres: ["trip hop"]},
  massive: {id: "sp_art_massive", name: "Massive Attack", image: null, genres: ["trip hop", "electronic"]},
  caroline: {id: "sp_art_caroline", name: "Caroline Polachek", image: null, genres: ["pop", "art pop"]},
  mitski: {id: "sp_art_mitski", name: "Mitski", image: null, genres: ["indie", "rock"]},
};

const TRACKS = {
  blinding: {id: "sp_trk_blinding", name: "Blinding Lights", artist: "The Weeknd", image: "https://i.scdn.co/image/qa-t1"},
  doiwanna: {id: "sp_trk_doiwanna", name: "Do I Wanna Know?", artist: "Arctic Monkeys", image: "https://i.scdn.co/image/qa-t2"},
  summertime: {id: "sp_trk_summertime", name: "Summertime Sadness", artist: "Lana Del Rey", image: "https://i.scdn.co/image/qa-t3"},
  letit: {id: "sp_trk_letit", name: "Let It Happen", artist: "Tame Impala", image: "https://i.scdn.co/image/qa-t4"},
  creep: {id: "sp_trk_creep", name: "Creep", artist: "Radiohead", image: null},
  kill: {id: "sp_trk_kill", name: "Kill Bill", artist: "SZA", image: "https://i.scdn.co/image/qa-t5"},
  earfquake: {id: "sp_trk_earfquake", name: "EARFQUAKE", artist: "Tyler, The Creator", image: null},
  cellophane: {id: "sp_trk_cellophane", name: "cellophane", artist: "FKA twigs", image: null},
  holocene: {id: "sp_trk_holocene", name: "Holocene", artist: "Bon Iver", image: null},
  glory: {id: "sp_trk_glory", name: "Glory Box", artist: "Portishead", image: null},
  teardrop: {id: "sp_trk_teardrop", name: "Teardrop", artist: "Massive Attack", image: null},
  soLong: {id: "sp_trk_solong", name: "Bunny Is A Rider", artist: "Caroline Polachek", image: null},
  nobody: {id: "sp_trk_nobody", name: "Nobody", artist: "Mitski", image: null},
};

function genreShares(artists) {
  const counts = new Map();
  for (const artist of artists) {
    for (const genre of artist.genres ?? []) {
      counts.set(genre, (counts.get(genre) ?? 0) + 1);
    }
  }
  const total = [...counts.values()].reduce((sum, n) => sum + n, 0);
  if (total === 0) return [];
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([name, count]) => ({
      name,
      percent: Math.max(1, Math.round((count / total) * 100)),
    }));
}


/**
 * The same general-taste shape the sync derives, so seeded QA exercises the
 * V2 profile without a live Spotify authorization. The long-term window is
 * the first three artists — the ones a seeded member has 'always' listened to
 * — so some artists are stable across windows and some are not.
 */
function generalTasteFor(artists, tracks) {
  const lasting = artists.slice(0, 3);
  const genreScore = new Map();
  const bump = (list, weight) => {
    for (const artist of list) {
      for (const genre of artist.genres ?? []) {
        genreScore.set(genre, (genreScore.get(genre) ?? 0) + weight);
      }
    }
  };
  bump(lasting, 3);
  bump(artists, 2);
  const genres = [...genreScore.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name]) => name);
  return {
    dominantGenre: genres[0] ?? null,
    secondaryGenres: genres.slice(1),
    genres,
    signatureArtists: lasting.slice(0, 3).map((a) => ({id: a.id, name: a.name})),
    stableArtistCount: lasting.length,
    stableTrackCount: Math.min(2, tracks.length),
    artistBreadth: artists.length,
  };
}

function summaryFor(uid, artists, tracks, recent, followed = []) {
  const genres = genreShares(artists);
  return {
    spotifyConnected: true,
    spotifyUserId: `sp_${uid}`,
    spotifyAccountId: `sp_acct_${uid}`,
    displayName: `QA ${uid}`,
    topArtists: artists,
    topTracks: tracks,
    recentlyPlayed: recent.map((track, i) => ({
      ...track,
      playedAt: new Date(Date.now() - (i + 1) * 3600_000).toISOString(),
    })),
    playlists: Array.from({length: 10}, (_, i) => ({
      id: `pl_${uid}_${i}`,
      name: `QA playlist ${i + 1}`,
      trackCount: 8 + i,
    })),
    musicProfile: {
      genres,
      genreNames: genres.map((g) => g.name),
      artistIds: artists.map((a) => a.id),
      trackIds: tracks.map((t) => t.id),
      recentTrackIds: recent.map((t) => t.id),
      recentArtistIds: artists.slice(0, 2).map((a) => a.id),
      playlistTrackIds: tracks.slice(0, 3).map((t) => t.id),
      musicFingerprint: {
        version: 2,
        trackIds: tracks.map((t) => t.id),
        artistIds: artists.map((a) => a.id),
        recentTrackIds: recent.map((t) => t.id),
        genreNames: genres.map((g) => g.name),
      },
    },
    musicProfileVersion: 2,
    // The four collections the Music Profile is built from. Followed
    // artists deliberately overlap the top list only partly, so QA can
    // see that publishing a followed artist is possible.
    followedArtists: followed,
    followScopeGranted: true,
    profileTopArtists: artists.slice(0, 5),
    profileTopTracks: tracks.slice(0, 5),
    generalTaste: generalTasteFor(artists, tracks),
    lastSyncedAt: FieldValue.serverTimestamp(),
    connectedAt: FieldValue.serverTimestamp(),
  };
}

const PLAN = {
  qa_user_a: {
    followed: [ARTISTS.weeknd, ARTISTS.sza, ARTISTS.radiohead],
    artists: [ARTISTS.weeknd, ARTISTS.arctic, ARTISTS.lana, ARTISTS.tame, ARTISTS.radiohead,
      ARTISTS.tyler, ARTISTS.fkatwigs, ARTISTS.boniver, ARTISTS.portishead, ARTISTS.massive,
      ARTISTS.caroline, ARTISTS.mitski],
    tracks: [TRACKS.blinding, TRACKS.doiwanna, TRACKS.summertime, TRACKS.letit, TRACKS.creep,
      TRACKS.earfquake, TRACKS.cellophane, TRACKS.holocene, TRACKS.glory, TRACKS.teardrop,
      TRACKS.soLong, TRACKS.nobody],
    recent: [TRACKS.blinding, TRACKS.letit],
  },
  qa_user_b: {
    followed: [ARTISTS.arctic, ARTISTS.tame],
    artists: [ARTISTS.weeknd, ARTISTS.arctic, ARTISTS.sza],
    tracks: [TRACKS.blinding, TRACKS.doiwanna, TRACKS.kill],
    recent: [TRACKS.doiwanna],
  },
  // Connected, but with barely any history: the limited-data state.
  qa_user_c: {artists: [], tracks: [], recent: []},
};

async function reset() {
  for (const uid of Object.keys(PLAN)) {
    await db.doc(`users/${uid}/music/summary`).delete().catch(() => {});
    await db.doc(`spotifySecrets/${uid}`).delete().catch(() => {});
    await db.doc(`profiles/${uid}`).set(
      {
        spotifyConnected: false,
        publicMusic: {enabled: false, artists: [], tracks: [], genres: []},
      },
      {merge: true},
    );
    console.log(`  ${uid}: Spotify artifacts cleared`);
  }
}

async function seed() {
  for (const [uid, plan] of Object.entries(PLAN)) {
    const profile = await db.doc(`profiles/${uid}`).get();
    if (!profile.exists) {
      console.error(
        `  ${uid}: no profile — run tool/seedEmulatorQaUsers.cjs first`,
      );
      continue;
    }
    await db
      .doc(`users/${uid}/music/summary`)
      .set(summaryFor(uid, plan.artists, plan.tracks, plan.recent, plan.followed ?? []), {merge: true});

    const profileUpdate = {spotifyConnected: true};
    if (PUBLISHED && uid === "qa_user_a") {
      const artists = plan.artists.slice(0, 3);
      const tracks = plan.tracks.slice(0, 3);
      profileUpdate.publicMusic = {
        enabled: true,
        artists: artists.map((a) => ({
          id: a.id,
          name: a.name,
          imageUrl: a.image,
          spotifyUrl: `https://open.spotify.com/artist/${a.id}`,
        })),
        tracks: tracks.map((t) => ({
          id: t.id,
          name: t.name,
          artist: t.artist,
          imageUrl: t.image,
          spotifyUrl: `https://open.spotify.com/track/${t.id}`,
        })),
        genres: genreShares(artists).slice(0, 5).map((g) => g.name),
        updatedAt: FieldValue.serverTimestamp(),
      };
      await db.doc(`users/${uid}/music/summary`).set(
        {
          publicSelection: {
            enabled: true,
            artistIds: artists.map((a) => a.id),
            trackIds: tracks.map((t) => t.id),
          },
        },
        {merge: true},
      );
    }
    await db.doc(`profiles/${uid}`).set(profileUpdate, {merge: true});
    console.log(
      `  ${uid}: ${plan.artists.length} artists, ${plan.tracks.length} tracks` +
        (profileUpdate.publicMusic ? ", card published" : ""),
    );
  }
}

(async () => {
  if (RESET) {
    console.log("Clearing Spotify taste for the QA users...");
    await reset();
  } else {
    console.log("Seeding Spotify taste for the QA users...");
    await seed();
    console.log(
      "\nExpected overlap between A and B: 2 artists (The Weeknd, Arctic " +
        "Monkeys), 2 tracks (Blinding Lights, Do I Wanna Know?).",
    );
  }
  process.exit(0);
})().catch((error) => {
  console.error("FAILED:", error.message);
  process.exit(1);
});
