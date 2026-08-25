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
  const list = await request(
    "GET",
    "https://firestore.googleapis.com/v1/projects/mevora-d6ed0/databases/(default)/collectionGroups/profiles/indexes",
  );
  console.log("list_status", list.status);
  const indexes = list.body.indexes || [];
  console.log(
    indexes.map((i) => ({
      state: i.state,
      fields: (i.fields || []).map((f) => `${f.fieldPath}:${f.order || f.arrayConfig}`),
    })),
  );

  const needed = indexes.find((i) => {
    const fields = (i.fields || []).map((f) => f.fieldPath).join(",");
    return fields.startsWith("profileCompleted,isDiscoverable,updatedAt");
  });
  if (needed) {
    console.log("discovery_index", needed.state, needed.name);
    return;
  }

  const created = await request(
    "POST",
    "https://firestore.googleapis.com/v1/projects/mevora-d6ed0/databases/(default)/collectionGroups/profiles/indexes",
    {
      queryScope: "COLLECTION",
      fields: [
        {fieldPath: "profileCompleted", order: "ASCENDING"},
        {fieldPath: "isDiscoverable", order: "ASCENDING"},
        {fieldPath: "updatedAt", order: "DESCENDING"},
        {fieldPath: "__name__", order: "DESCENDING"},
      ],
    },
  );
  console.log("create_status", created.status, JSON.stringify(created.body).slice(0, 500));
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
