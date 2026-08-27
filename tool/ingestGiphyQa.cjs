/**
 * Ingest a small GIPHY top-up into humorContent using Secret Manager + Admin.
 * Does not print the API key.
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
  const key = await accessSecret("GIPHY_API_KEY");
  if (!key || key === "UNSET_PLACEHOLDER" || key.length < 16) {
    throw new Error("GIPHY secret not configured");
  }
  process.env.GIPHY_API_KEY = key;
  process.env.GCLOUD_PROJECT = PROJECT;
  process.env.GCLOUD_PROJECT = PROJECT;

  const admin = require(
    path.join(__dirname, "../functions/node_modules/firebase-admin"),
  );
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  const db = admin.firestore();

  const {syncHumorFromGiphy} = require(
    path.join(__dirname, "../functions/lib/humor/ingest.js"),
  );
  const result = await syncHumorFromGiphy({
    db,
    language: "tr",
    limit: 12,
    probe: true,
  });

  const snap = await db
    .collection("humorContent")
    .where("source.provider", "==", "giphy")
    .limit(5)
    .get()
    .catch(async () => {
      // Fallback if composite index missing: scan recent docs by id prefix.
      const recent = await db
        .collection("humorContent")
        .orderBy("updatedAt", "desc")
        .limit(40)
        .get();
      const docs = recent.docs.filter(
        (d) => (d.data()?.source?.provider || d.data()?.provider) === "giphy",
      );
      return {docs, size: docs.length, empty: docs.length === 0};
    });

  let attribution = 0;
  let mediaOk = 0;
  for (const doc of snap.docs) {
    const d = doc.data() || {};
    const media = d.media || {};
    if (media.attributionRequired === true || d.attributionRequired === true) {
      attribution += 1;
    }
    if (media.downloadUrl || media.thumbUrl || d.thumbnailUrl) {
      mediaOk += 1;
    }
  }

  const report = {
    syncOk: result?.ok !== false,
    upserted: result?.upserted ?? result?.count ?? result?.written ?? null,
    giphyDocsSample: snap.size,
    attributionOnSample: attribution,
    mediaOnSample: mediaOk,
    overall: snap.size > 0 && mediaOk > 0 ? "PASS" : "FAIL",
  };
  // Avoid dumping result object in case it embeds URLs with keys.
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
