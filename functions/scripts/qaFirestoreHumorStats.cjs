const admin = require("firebase-admin");
if (admin.apps.length === 0) admin.initializeApp({projectId: "mevora-d6ed0"});
const db = admin.firestore();

(async () => {
  const snap = await db.collection("humorContent").limit(400).get();
  let yt = 0,
    giphy = 0,
    internal = 0,
    other = 0;
  const ytItems = [];
  const giphyItems = [];
  for (const d of snap.docs) {
    const x = d.data();
    const p = x.source?.provider || "unknown";
    if (p === "youtube") {
      yt++;
      if (ytItems.length < 20) {
        ytItems.push({
          id: d.id,
          active: x.active,
          safety: x.safetyStatus,
          embed: x.media?.embedUrl || null,
          thumb: x.media?.thumbUrl || null,
          sourceId: x.sourceId || null,
          title: x.media?.textBody || null,
        });
      }
    } else if (p === "giphy") {
      giphy++;
      if (giphyItems.length < 5) giphyItems.push({id: d.id, active: x.active});
    } else if (p === "mevora-internal" || x.source?.type === "internal") {
      internal++;
    } else {
      other++;
    }
  }
  const cache = await db.collection("humorProviderCache").get();
  const cacheRows = cache.docs.map((d) => {
    const x = d.data();
    return {
      id: d.id,
      provider: x.provider,
      queryKey: x.queryKey,
      items: Array.isArray(x.items) ? x.items.length : 0,
      expired: Number(x.expiresAtMs || 0) < Date.now(),
      ttlMin: Math.max(0, Math.round((Number(x.expiresAtMs || 0) - Date.now()) / 60000)),
    };
  });
  console.log(
    JSON.stringify(
      {
        humorContentScanned: snap.size,
        counts: {youtube: yt, giphy, internal, other},
        youtubeSamples: ytItems,
        giphySamples: giphyItems,
        cache: cacheRows,
      },
      null,
      2,
    ),
  );
})().catch((e) => {
  console.error(String(e));
  process.exit(1);
});
