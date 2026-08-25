const fs = require("fs");
const path = require("path");
const https = require("https");

const token = JSON.parse(
  fs.readFileSync(
    path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json"),
    "utf8",
  ),
).tokens.access_token;

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
  let pageToken = "";
  const all = [];
  do {
    const url =
      `https://cloudfunctions.googleapis.com/v2/projects/mevora-d6ed0/locations/-/functions?pageSize=100` +
      (pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : "");
    const body = await get(url);
    for (const f of body.functions || []) {
      all.push(f.name);
    }
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  console.log("count", all.length);
  all.sort().forEach((n) => console.log(n.replace(/^.*locations\//, "")));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
