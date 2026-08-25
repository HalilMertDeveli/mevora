const fs = require("fs");
const path = require("path");
const https = require("https");

const PROJECT = "mevora-d6ed0";
const TOKEN_PATH = path.join(
  process.env.USERPROFILE || "",
  ".config",
  "configstore",
  "firebase-tools.json",
);

function get(url, token) {
  return new Promise((resolve, reject) => {
    https
      .get(url, {headers: {Authorization: `Bearer ${token}`}}, (res) => {
        let d = "";
        res.on("data", (c) => (d += c));
        res.on("end", () => {
          try {
            resolve({status: res.statusCode, body: JSON.parse(d || "{}")});
          } catch (e) {
            reject(e);
          }
        });
      })
      .on("error", reject);
  });
}

async function main() {
  const token = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8")).tokens.access_token;
  const uids = [
    "F7CYZWNik3RGv3xQTZRLKWsMnTd2",
    "CKLxiWTBtoXik888Wzqicqeuj6t2",
  ];
  for (const uid of uids) {
    const url =
      `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/profiles/${uid}` +
      `?mask.fieldPaths=photos`;
    const res = await get(url, token);
    const values = res.body?.fields?.photos?.arrayValue?.values || [];
    const photos = values.map((v) => {
      const f = v.mapValue.fields || {};
      return {
        id: f.id?.stringValue,
        moderationStatus: f.moderationStatus?.stringValue,
        storagePath: f.storagePath?.stringValue,
        hasDownloadUrl: Boolean(f.downloadUrl?.stringValue),
        downloadUrlStart: (f.downloadUrl?.stringValue || "").slice(0, 100),
      };
    });
    console.log(uid, JSON.stringify(photos, null, 2));
  }

  // storage bucket location
  const buckets = await get(
    `https://firebasestorage.googleapis.com/v1beta/projects/${PROJECT}/buckets`,
    token,
  );
  console.log("buckets", JSON.stringify(buckets.body, null, 2).slice(0, 2000));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
