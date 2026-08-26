const fs = require("fs");
const path = require("path");
const https = require("https");

const token = JSON.parse(
  fs.readFileSync(
    path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json"),
    "utf8",
  ),
).tokens.access_token;

const indexName =
  "projects/mevora-d6ed0/databases/(default)/collectionGroups/profiles/indexes/CICAgJim14AK";

function get(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, {headers: {Authorization: `Bearer ${token}`}}, (res) => {
        let d = "";
        res.on("data", (c) => (d += c));
        res.on("end", () => resolve(JSON.parse(d || "{}")));
      })
      .on("error", reject);
  });
}

(async () => {
  for (let i = 0; i < 30; i++) {
    const body = await get(`https://firestore.googleapis.com/v1/${indexName}`);
    console.log(new Date().toISOString(), body.state || body.error?.message);
    if (body.state === "READY") {
      process.exit(0);
    }
    if (body.state === "NEEDS_REPAIR") {
      process.exit(2);
    }
    await new Promise((r) => setTimeout(r, 10000));
  }
  process.exit(1);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
