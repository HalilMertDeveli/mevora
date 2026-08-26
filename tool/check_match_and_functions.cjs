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

function request(method, url, token, body) {
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

async function main() {
  const token = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8")).tokens.access_token;
  const a = "F7CYZWNik3RGv3xQTZRLKWsMnTd2";
  const b = "CKLxiWTBtoXik888Wzqicqeuj6t2";
  const matchId = [a, b].sort().join("_");

  const docs = [
    `matches/${matchId}`,
    `likes/${a}_${b}`,
    `likes/${b}_${a}`,
    `users/${a}/passedUsers/${b}`,
    `users/${b}/passedUsers/${a}`,
  ];
  for (const doc of docs) {
    const res = await request(
      "GET",
      `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${doc}`,
      token,
    );
    console.log(doc, res.status, res.status === 200 ? "EXISTS" : res.body?.error?.status || "missing");
  }

  // list functions via cloudfunctions API
  const fn = await request(
    "GET",
    `https://cloudfunctions.googleapis.com/v2/projects/${PROJECT}/locations/-/functions?pageSize=100`,
    token,
  );
  const names = (fn.body.functions || []).map((f) => f.name.split("/").slice(-3).join("/"));
  console.log("functions_count", names.length);
  console.log(
    names
      .filter((n) => /discover|photo|Profile|swipe|match/i.test(n))
      .join("\n"),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
