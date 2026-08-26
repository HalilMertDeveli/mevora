/**
 * Diagnose why two users cannot discover each other.
 * Uses Firebase CLI tokens from configstore (no ADC required).
 */
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

function loadAccessToken() {
  const raw = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf8"));
  const token = raw?.tokens?.access_token;
  if (!token) throw new Error("No firebase-tools access_token");
  return token;
}

function httpsJson(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const req = https.request(
      {
        method,
        hostname: u.hostname,
        path: u.pathname + u.search,
        headers,
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          try {
            resolve({status: res.statusCode, body: JSON.parse(data || "{}")});
          } catch (e) {
            reject(new Error(`JSON parse failed ${res.statusCode}: ${data.slice(0, 300)}`));
          }
        });
      },
    );
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
  });
}

async function getDoc(token, docPath) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}`;
  const res = await httpsJson("GET", url, {Authorization: `Bearer ${token}`});
  if (res.status !== 200) {
    return {exists: false, status: res.status, error: res.body?.error?.message};
  }
  return {exists: true, fields: res.body.fields || {}};
}

function sval(f) {
  if (!f) return null;
  if (f.stringValue !== undefined) return f.stringValue;
  if (f.integerValue !== undefined) return Number(f.integerValue);
  if (f.doubleValue !== undefined) return Number(f.doubleValue);
  if (f.booleanValue !== undefined) return f.booleanValue;
  if (f.nullValue !== undefined) return null;
  if (f.timestampValue !== undefined) return f.timestampValue;
  if (f.mapValue) {
    const out = {};
    for (const [k, v] of Object.entries(f.mapValue.fields || {})) out[k] = sval(v);
    return out;
  }
  if (f.arrayValue) {
    return (f.arrayValue.values || []).map(sval);
  }
  return f;
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function interestedInAllows(want, gender) {
  const w = String(want || "").trim().toLowerCase();
  if (!w || w === "everyone") return true;
  const g = String(gender || "").trim().toLowerCase();
  if (!g) return true;
  if (w === "men") return g === "man" || g === "male" || g === "men";
  if (w === "women") return g === "woman" || g === "female" || g === "women";
  return true;
}

function datingPreference(prefs, profile) {
  return prefs.preferredGender || prefs.showMe || prefs.interestedIn || profile.interestedIn;
}

async function diagnoseUser(token, uid) {
  const [profile, prefs, loc, user, rel] = await Promise.all([
    getDoc(token, `profiles/${uid}`),
    getDoc(token, `userPreferences/${uid}`),
    getDoc(token, `userLocation/${uid}`),
    getDoc(token, `users/${uid}`),
    getDoc(token, `users/${uid}/relationshipMatch/summary`),
  ]);
  const p = Object.fromEntries(
    Object.entries(profile.fields || {}).map(([k, v]) => [k, sval(v)]),
  );
  const pr = Object.fromEntries(
    Object.entries(prefs.fields || {}).map(([k, v]) => [k, sval(v)]),
  );
  const l = Object.fromEntries(
    Object.entries(loc.fields || {}).map(([k, v]) => [k, sval(v)]),
  );
  const u = Object.fromEntries(
    Object.entries(user.fields || {}).map(([k, v]) => [k, sval(v)]),
  );
  const r = Object.fromEntries(
    Object.entries(rel.fields || {}).map(([k, v]) => [k, sval(v)]),
  );
  const photos = Array.isArray(p.photos) ? p.photos : [];
  const statuses = photos.map((ph) => String(ph?.moderationStatus ?? "missing"));
  return {
    uid,
    displayName: p.displayName,
    gender: p.gender,
    interestedIn: p.interestedIn,
    age: p.age,
    isDiscoverable: p.isDiscoverable,
    profileCompleted: p.profileCompleted,
    onboardingCompleted: p.onboardingCompleted,
    profileModerationStatus: p.profileModerationStatus ?? null,
    photoCount: photos.length,
    photoStatuses: statuses,
    approvedPhotos: statuses.filter((s) => s === "approved").length,
    pendingPhotos: statuses.filter((s) => s === "pending" || s === "processing").length,
    prefs: {
      preferredGender: pr.preferredGender ?? null,
      showMe: pr.showMe ?? null,
      interestedIn: pr.interestedIn ?? null,
      minAge: pr.minAge ?? 18,
      maxAge: pr.maxAge ?? 99,
      discoveryEnabled: pr.discoveryEnabled ?? true,
      maxDistance: pr.maxDistance ?? null,
    },
    location: {
      exists: loc.exists,
      latitude: l.latitude ?? null,
      longitude: l.longitude ?? null,
    },
    account: {
      lastActiveAt: u.lastActiveAt ?? null,
      accountStatus: u.accountStatus ?? null,
      isBanned: u.isBanned ?? null,
      isSmokeTestUser: u.isSmokeTestUser ?? null,
    },
    relationship: {
      exists: rel.exists,
      answers: r.answers ?? {},
      answerCount: Object.keys(r.answers || {}).length,
      compatibilityKey: r.compatibilityKey ?? null,
      setId: r.setId ?? null,
    },
    _rawPrefs: pr,
    _rawProfile: p,
  };
}

function simulateFilter(viewer, candidate) {
  const reasons = [];
  const pass = (name, ok, detail) => {
    reasons.push({check: name, result: ok ? "PASS" : "REJECT", detail: detail || null});
    return ok;
  };

  let ok = true;
  ok = pass("self", viewer.uid !== candidate.uid) && ok;
  ok = pass("isDiscoverable", candidate.isDiscoverable === true) && ok;
  ok = pass("profileCompleted", candidate.profileCompleted === true) && ok;
  const mod = String(candidate.profileModerationStatus ?? "approved");
  ok =
    pass(
      "profileModeration",
      !["suspended", "rejected", "manual_review"].includes(mod),
      mod,
    ) && ok;
  ok =
    pass(
      "accountEligible",
      candidate.account.isBanned !== true &&
        !["banned", "suspended", "deleted"].includes(
          String(candidate.account.accountStatus ?? "active"),
        ),
    ) && ok;
  ok = pass("ageAdult", Number(candidate.age) >= 18, String(candidate.age)) && ok;
  const minAge = Number(viewer.prefs.minAge ?? 18);
  const maxAge = Number(viewer.prefs.maxAge ?? 99);
  ok =
    pass(
      "ageRange",
      candidate.age >= minAge && candidate.age <= maxAge,
      `${candidate.age} in [${minAge},${maxAge}]`,
    ) && ok;
  ok =
    pass(
      "usablePhotos>=3",
      candidate.approvedPhotos + candidate.pendingPhotos >= 3 &&
        (candidate.approvedPhotos > 0 || candidate.pendingPhotos > 0),
      `approved=${candidate.approvedPhotos} pending=${candidate.pendingPhotos} statuses=${candidate.photoStatuses.join(",")}`,
    ) && ok;

  const viewerWant = datingPreference(viewer.prefs, viewer);
  const candWant = datingPreference(candidate.prefs, candidate);
  const genderOk =
    interestedInAllows(viewerWant, candidate.gender) &&
    interestedInAllows(candWant, viewer.gender);
  ok =
    pass(
      "reciprocalGender",
      genderOk,
      `viewerWant=${viewerWant} candGender=${candidate.gender}; candWant=${candWant} viewerGender=${viewer.gender}`,
    ) && ok;

  let distanceKm = null;
  if (
    viewer.location.latitude != null &&
    candidate.location.latitude != null
  ) {
    distanceKm = haversineKm(
      viewer.location.latitude,
      viewer.location.longitude,
      candidate.location.latitude,
      candidate.location.longitude,
    );
  }
  pass(
    "locationPresent",
    viewer.location.exists && candidate.location.exists,
    `viewerLoc=${viewer.location.exists} candLoc=${candidate.location.exists} distanceKm=${
      distanceKm == null ? "n/a" : distanceKm.toFixed(1)
    }`,
  );
  // Distance is soft in CF (tiers), not hard reject.
  pass("distanceSoft", true, `tier would use distanceKm=${distanceKm == null ? "no_location" : distanceKm.toFixed(1)}`);

  const va = viewer.relationship.answers || {};
  const ca = candidate.relationship.answers || {};
  const shared = Object.keys(va).filter((q) => ca[q] != null);
  const aligned = shared.filter((q) => String(va[q]) === String(ca[q]));
  const score = shared.length ? Math.round((aligned.length / shared.length) * 100) : null;
  pass(
    "relationshipAnswers",
    shared.length > 0,
    `shared=${shared.length} aligned=${aligned.length} score=${score}% keyA=${viewer.relationship.compatibilityKey} keyB=${candidate.relationship.compatibilityKey}`,
  );

  const smokeV = viewer.account.isSmokeTestUser === true;
  const smokeC = candidate.account.isSmokeTestUser === true;
  ok = pass("smokeIsolation", smokeV === smokeC || (!smokeV && !smokeC), `viewerSmoke=${smokeV} candSmoke=${smokeC}`) && ok;

  ok = pass("discoveryEnabled", viewer.prefs.discoveryEnabled !== false) && ok;

  return {
    viewer: viewer.displayName,
    candidate: candidate.displayName,
    final: ok ? "INCLUDED" : "REJECTED",
    distanceKm,
    relationshipScore: score,
    checks: reasons,
  };
}

async function main() {
  const token = loadAccessToken();
  const uids = process.argv.slice(2);
  const defaultUids = [
    "F7CYZWNik3RGv3xQTZRLKWsMnTd2", // Ahmet (woman)
    "CKLxiWTBtoXik888Wzqicqeuj6t2", // Hilal (man)
    "i4tBpHo08NfJbSUCNHgYDTagEuv1", // HMD (man)
    "tnXYzkFf1tM8vaRkBgBQlE5jh6U2", // Halil
  ];
  const targets = uids.length ? uids : defaultUids;
  const users = [];
  for (const uid of targets) {
    users.push(await diagnoseUser(token, uid));
  }
  console.log("=== USER SNAPSHOTS ===");
  for (const u of users) {
    const copy = {...u};
    delete copy._rawPrefs;
    delete copy._rawProfile;
    console.log(JSON.stringify(copy, null, 2));
  }
  console.log("=== PAIRWISE FILTER SIMULATION ===");
  for (let i = 0; i < users.length; i++) {
    for (let j = 0; j < users.length; j++) {
      if (i === j) continue;
      const sim = simulateFilter(users[i], users[j]);
      console.log(JSON.stringify(sim, null, 2));
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
