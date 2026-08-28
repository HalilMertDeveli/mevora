const fs = require("fs");
const path = require("path");

const ids = [
  "0Y2MTLkYRXQ","0m9WzaDjySQ","1DAd52daBNA","3JJGq7a7GLE","K2WIboOV2uA",
  "7jCiNDotPSg","K8n-dO5rpQ0","Nrk2_lEV7Hc","OS4NA9dLl5A","PqVg_u7VUwA",
  "PuxiIxy7cDU","QikbQjIEGOI","VBCuSmZv50E","XulN4FZCqJ4","iTreHSz7IIY",
  "izI3FVlR6kA","pBl5ADsdVMo","qwieOw60wkI","s0e24Oak93o","vqVq2RiBt5I",
];

(async () => {
  const results = [];
  for (const id of ids) {
    const watch = `https://www.youtube.com/watch?v=${id}`;
    const res = await fetch(
      `https://www.youtube.com/oembed?url=${encodeURIComponent(watch)}&format=json`,
    );
    results.push({videoId: id, pass: res.ok, status: res.status});
    await new Promise((r) => setTimeout(r, 80));
  }
  console.log(
    JSON.stringify(
      {
        tested: results.length,
        pass: results.filter((r) => r.pass).length,
        fail: results.filter((r) => !r.pass).length,
        results,
      },
      null,
      2,
    ),
  );
})();
