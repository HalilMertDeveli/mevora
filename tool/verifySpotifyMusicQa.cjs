/**
 * Phase 7B — verify Firestore music summary + token isolation after real Spotify sync.
 * Never prints token/secret values.
 *
 * Usage:
 *   set GOOGLE_APPLICATION_CREDENTIALS=<adc>
 *   node tool/verifySpotifyMusicQa.cjs --uid <uid>
 *   node tool/verifySpotifyMusicQa.cjs --email <email>
 *   node tool/verifySpotifyMusicQa.cjs   # list connected summaries
 */
const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const PROJECT = "mevora-d6ed0";
const FORBIDDEN = [
  "accessToken",
  "refreshToken",
  "clientSecret",
  "SPOTIFY_CLIENT_SECRET",
  "access_token",
  "refresh_token",
];

function parseArgs(argv) {
  const out = {email: null, uid: null};
  for (let i = 2; i < argv.length; i += 1) {
    if (argv[i] === "--email" && argv[i + 1]) out.email = argv[++i];
    else if (argv[i] === "--uid" && argv[i + 1]) out.uid = argv[++i];
  }
  return out;
}

function findForbidden(obj, prefix = "") {
  const hits = [];
  if (!obj || typeof obj !== "object") return hits;
  for (const [key, value] of Object.entries(obj)) {
    const p = prefix ? `${prefix}.${key}` : key;
    if (FORBIDDEN.some((f) => f.toLowerCase() === key.toLowerCase())) hits.push(p);
    if (value && typeof value === "object") hits.push(...findForbidden(value, p));
  }
  return hits;
}

function validateSummary(summary) {
  const issues = [];
  if (!summary) return {ok: false, issues: ["summary missing"]};
  if (summary.provider !== "spotify") issues.push(`provider=${summary.provider}`);
  if (summary.spotifyConnected !== true && summary.connected !== true) {
    issues.push("not connected");
  }
  if (summary.musicProfileVersion !== 3) {
    issues.push(`musicProfileVersion=${summary.musicProfileVersion}`);
  }
  const profile = summary.musicProfile ?? {};
  for (const field of [
    "trackIds",
    "artistIds",
    "recentTrackIds",
    "recentArtistIds",
    "recentArtists",
    "genres",
    "genreNames",
  ]) {
    if (!Array.isArray(profile[field])) issues.push(`missing ${field}`);
  }
  const recentArtists = profile.recentArtists ?? [];
  if (recentArtists.length > 5) issues.push(`recentArtists>${5}`);
  const ids = recentArtists.map((a) => a?.id).filter(Boolean);
  if (new Set(ids).size !== ids.length) issues.push("recentArtists duplicate ids");
  if ((profile.recentArtistIds ?? []).length > 30) issues.push("recentArtistIds>30");
  const forbidden = findForbidden(summary);
  if (forbidden.length) issues.push(`forbidden:${forbidden.join(",")}`);
  return {
    ok: issues.length === 0,
    issues,
    stats: {
      trackIds: (profile.trackIds ?? []).length,
      artistIds: (profile.artistIds ?? []).length,
      recentTrackIds: (profile.recentTrackIds ?? []).length,
      recentArtistIds: (profile.recentArtistIds ?? []).length,
      recentArtists: recentArtists.length,
      genres: (profile.genres ?? []).length,
      genreNames: (profile.genreNames ?? []).length,
      topTracks: (summary.topTracks ?? []).length,
      topArtists: (summary.topArtists ?? []).length,
    },
    sample: {
      recentArtistNames: recentArtists.slice(0, 5).map((a) => a?.name ?? "?"),
      genreNames: (profile.genreNames ?? []).slice(0, 8),
      topArtistNames: (summary.topArtists ?? []).slice(0, 5).map((a) => a?.name ?? "?"),
    },
  };
}

async function main() {
  const args = parseArgs(process.argv);
  if (!admin.apps.length) admin.initializeApp({projectId: PROJECT});
  const db = admin.firestore();
  const auth = admin.auth();

  if (!args.uid && !args.email) {
    const snap = await db.collectionGroup("music").limit(30).get();
    const candidates = [];
    for (const doc of snap.docs) {
      const uid = doc.ref.parent.parent?.id;
      const data = doc.data();
      if (uid && (data.spotifyConnected === true || data.connected === true)) {
        candidates.push({
          uid,
          provider: data.provider ?? null,
          version: data.musicProfileVersion ?? null,
          displayName: data.displayName ?? null,
        });
      }
    }
    console.log(JSON.stringify({ok: true, mode: "list", candidates}, null, 2));
    return;
  }

  let uid = args.uid;
  if (!uid && args.email) {
    uid = (await auth.getUserByEmail(args.email)).uid;
  }

  const [summarySnap, secretSnap] = await Promise.all([
    db.doc(`users/${uid}/music/summary`).get(),
    db.doc(`spotifySecrets/${uid}`).get(),
  ]);
  const summary = summarySnap.exists ? summarySnap.data() : null;
  const validation = validateSummary(summary);
  const secretFields = secretSnap.exists ? Object.keys(secretSnap.data() ?? {}) : [];
  // Never print values — only field names and presence flags.
  const hasAccess = secretFields.includes("accessToken");
  const hasRefresh = secretFields.includes("refreshToken");

  console.log(
    JSON.stringify(
      {
        ok: validation.ok && secretSnap.exists && hasAccess,
        uid,
        summaryExists: summarySnap.exists,
        secretDocExists: secretSnap.exists,
        secretFieldNames: secretFields,
        tokenIsolation: {
          summaryForbiddenKeys: findForbidden(summary ?? {}),
          secretsSeparate: secretSnap.exists && summarySnap.exists,
          accessTokenPresentInSecrets: hasAccess,
          refreshTokenPresentInSecrets: hasRefresh,
        },
        validation,
      },
      null,
      2,
    ),
  );
  process.exit(validation.ok && secretSnap.exists && hasAccess ? 0 : 2);
}

main().catch((e) => {
  console.error(JSON.stringify({ok: false, error: String(e.message || e)}));
  process.exit(1);
});
