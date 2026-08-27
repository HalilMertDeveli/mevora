/**
 * Live YouTube Data API verification — uses ADC + Secret Manager.
 * Never prints the API key or full URLs with query secrets.
 *
 * Usage:
 *   node tool/qaBootstrapAdcFromFirebaseLogin.cjs  (sets GOOGLE_APPLICATION_CREDENTIALS)
 *   node tool/verifyYoutubeLive.cjs
 */
const {spawnSync} = require("child_process");
const path = require("path");
const https = require("https");

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

function requestJson(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let raw = "";
        res.on("data", (c) => (raw += c));
        res.on("end", () => {
          try {
            resolve({status: res.statusCode, body: JSON.parse(raw || "{}")});
          } catch (e) {
            resolve({status: res.statusCode, body: raw});
          }
        });
      })
      .on("error", reject);
  });
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
  const report = {
    secretExists: false,
    secretConfigured: false,
    youtubeHttpOk: false,
    itemCount: 0,
    hasVideoId: false,
    hasThumb: false,
    hasTitle: false,
    overall: "FAIL",
  };

  const key = await accessSecret("YOUTUBE_DATA_API_KEY");
  report.secretExists = true;
  report.secretConfigured =
    key.length >= 20 && key !== "UNSET_PLACEHOLDER";

  if (!report.secretConfigured) {
    console.log(JSON.stringify(report, null, 2));
    process.exit(1);
  }

  const q = encodeURIComponent("komik shorts");
  const url =
    `https://www.googleapis.com/youtube/v3/search?part=snippet&type=video` +
    `&q=${q}&maxResults=5&safeSearch=strict&videoEmbeddable=true` +
    `&key=${encodeURIComponent(key)}`;
  const res = await requestJson(url);
  report.youtubeHttpOk = res.status === 200 && !res.body?.error;
  const items = Array.isArray(res.body?.items) ? res.body.items : [];
  report.itemCount = items.length;
  if (items[0]) {
    report.hasVideoId = Boolean(items[0].id?.videoId);
    report.hasThumb = Boolean(
      items[0].snippet?.thumbnails?.high?.url ||
        items[0].snippet?.thumbnails?.default?.url,
    );
    report.hasTitle = Boolean(items[0].snippet?.title);
  }

  report.overall =
    report.secretConfigured &&
    report.youtubeHttpOk &&
    report.itemCount > 0 &&
    report.hasVideoId
      ? "PASS"
      : "FAIL";

  console.log(JSON.stringify(report, null, 2));
  if (report.overall !== "PASS") process.exit(1);
}

main().catch((e) => {
  console.error(
    JSON.stringify({
      overall: "FAIL",
      error: String(e && e.message ? e.message : e).slice(0, 160),
    }),
  );
  process.exit(1);
});
