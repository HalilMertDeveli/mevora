/**
 * Simulates getMevoraPicks against a synthetic 3,000-member population in the
 * metered in-memory Firestore and reports billed reads per open.
 *
 *   npm --prefix functions run build
 *   node tool/simulatePicksCost.cjs [functionsDir] [target]
 *
 * [functionsDir] defaults to this checkout's functions/ (its lib/ must be
 * built); point it at another checkout's functions/ to measure that code
 * with the same population. [target] overrides the daily target (10, 15).
 * The metered in-memory Firestore always comes from this checkout.
 *
 * Only an estimate: the population is synthetic (see buildWorld), and the
 * in-memory Firestore bills like the real one but runs no indexes.
 */
const path = require("node:path");
const functionsDir = path.resolve(process.argv[2] ?? path.join(__dirname, "..", "functions"));
const target = Number(process.argv[3] ?? 0) || null;
const HELPERS = path.join(__dirname, "..", "functions", "test", "helpers");

process.env.FIREBASE_CONFIG = JSON.stringify({projectId: "demo-sim", storageBucket: "demo-sim.appspot.com"});
const {createFakeFirestore} = require(`${HELPERS}/fakeFirestore.cjs`);
const {installFirebaseAdminStubs, callAs} = require(`${HELPERS}/adminStubs.cjs`);
const {Timestamp} = require(require.resolve("firebase-admin/firestore", {paths: [HELPERS]}));

const db = createFakeFirestore();
installFirebaseAdminStubs({db});
const config = require(`${functionsDir}/lib/picks/config.js`);
if (target && config.picksSizing && config.PICKS_SIZING) {
  Object.assign(config.PICKS_SIZING, config.picksSizing(target));
} else if (target) {
  // Code from before sizing existed: the same counts, set directly.
  Object.assign(config.PICKS_CONFIG, {targetCount: target, maxDeliveredPerBatch: target + Math.ceil(target / 4), scanShortlistSize: target * 6, scanMaxPages: Math.ceil((target * 16) / 40)});
}
const {getMevoraPicks} = require(`${functionsDir}/lib/picks/index.js`);

// Deterministic pseudo-random numbers.
let seed = 42;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const pick = (list) => list[Math.floor(rand() * list.length)];
const some = (list, n) => [...list].sort(() => rand() - 0.5).slice(0, n);

const INTERESTS = ["hiking", "jazz", "cooking", "chess", "film", "travel"];
const LIFESTYLE = ["nonsmoker", "earlybird", "social", "homebody"];
const GOALS = ["longTerm", "longTerm", "longTerm", "casual"];
const ISTANBUL = {latitude: 41.0082, longitude: 28.9784};
const now = Date.now();
const DAY = 86_400_000;

function buildWorld({members = 3000, viewerHistory = 0}) {
  const seedDocs = {};
  for (let i = 0; i < members; i++) {
    const uid = `u${i}`;
    const man = i % 2 === 0;
    const active = rand() < 0.7;
    seedDocs[`users/${uid}`] = {uid, lastActiveAt: Timestamp.fromMillis(now - (active ? rand() * 5 * DAY : 120 * DAY))};
    seedDocs[`profiles/${uid}`] = {
      uid,
      displayName: uid,
      age: 20 + Math.floor(rand() * 26),
      gender: man ? "man" : "woman",
      interestedIn: man ? "women" : "men",
      isDiscoverable: rand() < 0.95,
      profileCompleted: true,
      photos: [1, 2, 3].map((n) => ({id: `p${n}`, downloadUrl: `https://x.test/${uid}/${n}.jpg`, moderationStatus: "approved", order: n})),
      relationshipGoal: pick(GOALS),
      interests: some(INTERESTS, 4),
      lifestyle: some(LIFESTYLE, 2),
      updatedAt: now - Math.floor(rand() * 30 * DAY),
    };
    seedDocs[`userPreferences/${uid}`] = {interestedIn: man ? "women" : "men", minAge: 18, maxAge: 45};
    const r = rand();
    if (r < 0.85) {
      // Most of Istanbul, within ~60 km; some abroad; the rest without location.
      seedDocs[`userLocation/${uid}`] = {latitude: ISTANBUL.latitude + (rand() - 0.5) * 0.9, longitude: ISTANBUL.longitude + (rand() - 0.5) * 0.9};
    } else if (r < 0.9) {
      seedDocs[`userLocation/${uid}`] = {latitude: 52.52, longitude: 13.405};
    }
    if (rand() < 0.4) {
      seedDocs[`users/${uid}/music/summary`] = {
        spotifyConnected: true,
        musicProfile: {trackIds: some(["t1", "t2", "t3", "t4", "t5", "t6"], 3), artistIds: some(["a1", "a2", "a3", "a4"], 2), genres: some(["indie", "rock", "pop", "jazz"], 2)},
      };
    }
    if (rand() < 0.5) {
      seedDocs[`users/${uid}/relationshipMatch/summary`] = {answers: {rq_001: pick(["a", "b"]), rq_002: pick(["a", "b", "c"]), rq_003: pick(["a", "c"])}};
    }
    if (rand() < 0.05) {
      seedDocs[`users/${uid}/boosts/b${i}`] = {userId: uid, status: "active", expiresAt: Timestamp.fromMillis(now + 7 * DAY), startedAt: Timestamp.fromMillis(now - DAY)};
    }
  }
  return seedDocs;
}

async function openTwice(world, viewer, history) {
  db.reset(world);
  // Sample viewers are active members in Istanbul with discovery on.
  await db.doc(`userLocation/${viewer}`).set({...ISTANBUL});
  await db.doc(`profiles/${viewer}`).set({isDiscoverable: true}, {merge: true});
  await db.doc(`users/${viewer}`).set({lastActiveAt: Timestamp.fromMillis(now)}, {merge: true});
  // The viewer's own history: likes and passes on people outside the sample.
  for (let i = 0; i < history; i++) {
    await db.doc(`likes/${viewer}_h${i}`).set({fromUserId: viewer, toUserId: `h${i}`, action: "like"});
    await db.doc(`users/${viewer}/passedUsers/p${i}`).set({toUserId: `p${i}`});
  }
  db.resetStats();
  const first = await callAs(getMevoraPicks, viewer);
  const generation = db.stats().reads;
  db.resetStats();
  await callAs(getMevoraPicks, viewer);
  const reopen = db.stats().reads;
  return {generation, reopen, picks: first.picks.length, status: first.status};
}

(async () => {
  const world = buildWorld({});
  const viewers = Array.from({length: 12}, (_, i) => `u${i * 97}`);
  for (const history of [0, 300]) {
    const rows = [];
    for (const viewer of viewers) rows.push(await openTwice(world, viewer, history));
    const mean = (key) => Math.round(rows.reduce((sum, row) => sum + row[key], 0) / rows.length);
    const picks = rows.map((row) => row.picks);
    console.log(JSON.stringify({
      functionsDir: path.basename(path.dirname(functionsDir)),
      target: target ?? "default",
      history,
      generationReadsMean: mean("generation"),
      reopenReadsMean: mean("reopen"),
      generationMax: Math.max(...rows.map((r) => r.generation)),
      reopenMax: Math.max(...rows.map((r) => r.reopen)),
      picksServed: `${Math.min(...picks)}-${Math.max(...picks)}`,
    }));
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
