/**
 * Ensure Firestore field override for collectionGroup boosts.status ASC.
 * Required by loadActiveBoostedUserIds / expireBoost.
 */
const fs = require("fs");
const path = require("path");
const https = require("https");

const token = JSON.parse(
  fs.readFileSync(
    path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json"),
    "utf8",
  ),
).tokens.access_token;

function request(method, url, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        method,
        hostname: u.hostname,
        path: u.pathname + u.search,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
      },
      (res) => {
        let d = "";
        res.on("data", (c) => (d += c));
        res.on("end", () => {
          try {
            resolve({status: res.statusCode, body: JSON.parse(d || "{}")});
          } catch (e) {
            resolve({status: res.statusCode, body: d});
          }
        });
      },
    );
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

(async () => {
  // Single-field exemption / override for collection group queries.
  const parent =
    "projects/mevora-d6ed0/databases/(default)/collectionGroups/boosts/fields/status";
  const patch = await request(
    "PATCH",
    `https://firestore.googleapis.com/v1/${parent}?updateMask.fieldPaths=indexConfig`,
    {
      name: parent,
      indexConfig: {
        indexes: [
          {queryScope: "COLLECTION", order: "ASCENDING"},
          {queryScope: "COLLECTION", order: "DESCENDING"},
          {queryScope: "COLLECTION", arrayConfig: "CONTAINS"},
          {queryScope: "COLLECTION_GROUP", order: "ASCENDING"},
        ],
      },
    },
  );
  console.log("patch_status", patch.status, JSON.stringify(patch.body).slice(0, 800));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
