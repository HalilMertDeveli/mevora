const fs = require("fs");
const path = require("path");
const https = require("https");

const token = JSON.parse(
  fs.readFileSync(
    path.join(process.env.USERPROFILE, ".config", "configstore", "firebase-tools.json"),
    "utf8",
  ),
).tokens.access_token;

https
  .get(
    "https://storage.googleapis.com/storage/v1/b/mevora-d6ed0.firebasestorage.app",
    {headers: {Authorization: `Bearer ${token}`}},
    (res) => {
      let d = "";
      res.on("data", (c) => (d += c));
      res.on("end", () => {
        const j = JSON.parse(d);
        console.log({
          name: j.name,
          location: j.location,
          locationType: j.locationType,
          storageClass: j.storageClass,
        });
      });
    },
  )
  .on("error", (e) => {
    console.error(e);
    process.exit(1);
  });
