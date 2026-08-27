/**
 * Ingest a small YouTube top-up into humorContent using Secret Manager + Admin.
 * Does not print the API key.
 *
 * Usage:
 *   node tool/qaBootstrapAdcFromFirebaseLogin.cjs
 *   node tool/ingestYoutubeQa.cjs
 */
const {spawnSync} = require("child_process");
const path = require("path");

const PROJECT = "mevora-d6ed0";
const BOOTSTRAP = path.join(__dirname, "qaBootstrapAdcFromFirebaseLogin.cjs");

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) return;
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok) throw new Error("ADC bootstrap failed");
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
}

async function accessSecret(name) {
  const {GoogleAuth} = require(
    path.join(__dirname, "../functions/node_modules/google-auth-library"),
  );
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-platform"],
  });
  const client = await auth.getClient();
  const url =
    `https://secretmanager.googleapis.com/v1/projects/${PROJECT}/secrets/${name}/versions/latest:access`;
  const res = await client.request({url});
  const data = res.data?.payload?.data;
  if (!data) throw new Error("secret empty");
  return Buffer.from(data, "base64").toString("utf8").trim();
}

async function main() {
  ensureAdc();
  const key = await accessSecret("YOUTUBE_DATA_API_KEY");
  if (!key || key === "UNSET_PLACEHOLDER" || key.length < 20) {
    throw new Error("YouTube secret not configured");
  }
  process.env.YOUTUBE_DATA_API_KEY = key;
  process.env.GCLOUD_PROJECT = PROJECT;

  const admin = require(
    path.join(__dirname, "../functions/node_modules/firebase-admin"),
  );
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();

  const {topUpHumorFromProviders} = require(
    path.join(__dirname, "../functions/lib/humor/providerOrchestrator.js"),
  );
  const result = await topUpHumorFromProviders({
    db,
    languages: ["tr", "en"],
    needed: 8,
    excludeIds: new Set(),
    probe: false,
  });

  const snap = await db
    .collection("humorContent")
    .where("source.provider", "==", "youtube")
    .limit(5)
    .get()
    .catch(async () => {
      const recent = await db
        .collection("humorContent")
        .orderBy("updatedAt", "desc")
        .limit(40)
        .get();
      const docs = recent.docs.filter(
        (d) => (d.data()?.source?.provider || d.data()?.provider) === "youtube",
      );
      return {docs, size: docs.length, empty: docs.length === 0};
    });

  let embedOk = 0;
  let posterOk = 0;
  let embedAsDownload = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const media = d.media || {};
    if (media.embedUrl && String(media.embedUrl).includes("youtube.com/embed")) {
      embedOk += 1;
    }
    const download = String(media.downloadUrl || "");
    if (
      download.includes("ytimg.com") ||
      download.includes("ggpht.com") ||
      (!download && media.thumbUrl)
    ) {
      posterOk += 1;
    }
    if (download.includes("youtube.com/embed") || download.includes("youtu.be/")) {
      embedAsDownload += 1;
    }
  }

  const youtubeAttempt = (result?.attempts || []).find(
    (a) => a.provider === "youtube",
  );
  const report = {
    topUpOk: result != null,
    contentIds: Array.isArray(result?.contentIds)
      ? result.contentIds.length
      : 0,
    youtubeAttemptOk: youtubeAttempt?.ok === true || youtubeAttempt == null,
    youtubeDocsSample: snap.size,
    embedOnSample: embedOk,
    posterOnSample: posterOk,
    embedAsDownloadUrl: embedAsDownload,
    overall:
      snap.size > 0 && embedOk > 0 && embedAsDownload === 0 ? "PASS" : "FAIL",
  };
  console.log(JSON.stringify(report, null, 2));
  if (report.overall !== "PASS") process.exit(1);
}

main().catch((e) => {
  console.error(
    JSON.stringify({
      overall: "FAIL",
      error: String(e && e.message ? e.message : e).slice(0, 200),
    }),
  );
  process.exit(1);
});
