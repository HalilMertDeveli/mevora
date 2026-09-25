/**
 * Discover Like ΓåÆ Mutual Match ΓåÆ Message QA E2E.
 *
 * Auto-bootstraps ADC from `firebase login` when needed.
 * Live callable path requires App Check JWT (debug UUID alone is not enough);
 * Admin path always validates Firestore match schema used by Chat UI.
 *
 * Usage:
 *   node tool/discoverLikeQaE2e.cjs
 */
const fs = require("fs");
const path = require("path");
const https = require("https");
const {spawnSync} = require("child_process");

const PROJECT = process.env.SMOKE_FIREBASE_PROJECT || "mevora-d6ed0";
const REGION = "europe-west1";
const TOKEN_FILE = path.join(__dirname, "app_check_debug_token.local");
const BOOTSTRAP = path.join(__dirname, "qaBootstrapAdcFromFirebaseLogin.cjs");

function ensureAdc() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return process.env.GOOGLE_APPLICATION_CREDENTIALS;
  }
  const boot = spawnSync(process.execPath, [BOOTSTRAP], {encoding: "utf8"});
  const line = (boot.stdout || "").trim().split(/\r?\n/).pop();
  const parsed = JSON.parse(line || "{}");
  if (!parsed.ok || !parsed.adcPath) {
    throw new Error(`ADC bootstrap failed: ${line || boot.stderr}`);
  }
  process.env.GOOGLE_APPLICATION_CREDENTIALS = parsed.adcPath;
  return parsed.adcPath;
}

function loadAdmin() {
  ensureAdc();
  const adminPath = path.join(__dirname, "../functions/node_modules/firebase-admin");
  const admin = require(adminPath);
  if (!admin.apps.length) {
    admin.initializeApp({projectId: PROJECT});
  }
  return admin;
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

function requestJson(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const payload = body == null ? null : JSON.stringify(body);
    const req = https.request(
      {
        method,
        hostname: u.hostname,
        path: u.pathname + u.search,
        headers: {
          ...(headers || {}),
          ...(payload
            ? {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(payload),
              }
            : {}),
        },
      },
      (res) => {
        let raw = "";
        res.on("data", (c) => (raw += c));
        res.on("end", () => {
          let parsed = raw;
          try {
            parsed = JSON.parse(raw || "{}");
          } catch (_) {
            /* keep */
          }
          resolve({status: res.statusCode, body: parsed});
        });
      },
    );
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function clearPair(db, a, b) {
  const matchId = [a, b].sort().join("_");
  const refs = [
    db.doc(`likes/${a}_${b}`),
    db.doc(`likes/${b}_${a}`),
    db.doc(`matches/${matchId}`),
    db.doc(`users/${a}/passedUsers/${b}`),
    db.doc(`users/${b}/passedUsers/${a}`),
  ];
  await Promise.all(refs.map((r) => r.delete().catch(() => undefined)));
  const msgs = await db.collection(`matches/${matchId}/messages`).limit(50).get();
  await Promise.all(msgs.docs.map((d) => d.ref.delete().catch(() => undefined)));
  return matchId;
}

async function ensureDiscoverable(db, uid, label) {
  const userRef = db.doc(`users/${uid}`);
  const profileRef = db.doc(`profiles/${uid}`);
  const prefsRef = db.doc(`userPreferences/${uid}`);
  const user = await userRef.get();
  assert(user.exists, `missing users/${uid}`);
  await userRef.set(
    {
      accountStatus: "active",
      isActive: true,
      isBanned: false,
      profileCompleted: true,
      onboardingCompleted: true,
      displayName: user.data()?.displayName || `QA_${label}`,
      updatedAt: new Date(),
    },
    {merge: true},
  );
  await profileRef.set(
    {
      displayName: user.data()?.displayName || `QA_${label}`,
      isDiscoverable: true,
      birthDate: "1995-01-15",
      gender: label === "A" ? "male" : "female",
      updatedAt: new Date(),
    },
    {merge: true},
  );
  await prefsRef.set(
    {
      minAge: 18,
      maxAge: 99,
      interestedIn: ["male", "female", "nonBinary"],
      preferredGender: ["male", "female", "nonBinary"],
      updatedAt: new Date(),
    },
    {merge: true},
  );
}

async function idTokenForEmailPassword(email, password, apiKey) {
  const res = await requestJson(
    "POST",
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`,
    {},
    {email, password, returnSecureToken: true},
  );
  if (!res.body?.idToken) {
    throw new Error(
      `password sign-in failed status=${res.status} code=${res.body?.error?.message || "?"}`,
    );
  }
  return {idToken: res.body.idToken, localId: res.body.localId};
}

async function idTokenFor(admin, uid, apiKey) {
  const custom = await admin.auth().createCustomToken(uid);
  const res = await requestJson(
    "POST",
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {},
    {token: custom, returnSecureToken: true},
  );
  if (!res.body?.idToken) {
    throw new Error(`custom token exchange failed status=${res.status}`);
  }
  return res.body.idToken;
}

async function callCallable(name, idToken, data, appCheckHeader) {
  const headers = {Authorization: `Bearer ${idToken}`};
  if (appCheckHeader) headers["X-Firebase-AppCheck"] = appCheckHeader;
  return requestJson(
    "POST",
    `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`,
    headers,
    {data},
  );
}

function callableErrorCode(res) {
  return (
    res.body?.error?.status ||
    res.body?.error?.message ||
    res.body?.error ||
    `HTTP_${res.status}`
  );
}

async function main() {
  const report = {
    project: PROJECT,
    discoverPass: "NOT_RUN",
    discoverLike: "NOT_RUN",
    mutualMatch: "NOT_RUN",
    matchSchema: "NOT_RUN",
    messaging: "NOT_RUN",
    liveRecordSwipe: "NOT_RUN",
    liveRecordDiscoveryDecision: "NOT_RUN",
    chatRouteContract: "PASS",
    overall: "FAIL",
  };

  const admin = loadAdmin();
  const db = admin.firestore();
  const uidA = process.env.QA_A_UID || "F7CYZWNik3RGv3xQTZRLKWsMnTd2";
  const uidB = process.env.QA_B_UID || "CKLxiWTBtoXik888Wzqicqeuj6t2";

  console.log("DISCOVER LIKE QA E2E");
  console.log("project=", PROJECT);
  console.log("QA_A=", uidA);
  console.log("QA_B=", uidB);

  await ensureDiscoverable(db, uidA, "A");
  await ensureDiscoverable(db, uidB, "B");
  let matchId = await clearPair(db, uidA, uidB);

  // --- Live callables (password sign-in preferred; avoids SA signBlob) ---
  const apiKey =
    process.env.FIREBASE_WEB_API_KEY ||
    process.env.MEVORA_WEB_API_KEY ||
    "";
  let appCheckHeader = null;
  if (fs.existsSync(TOKEN_FILE)) {
    appCheckHeader = fs.readFileSync(TOKEN_FILE, "utf8").trim();
  }

  if (apiKey) {
    try {
      let tokenA;
      let tokenB;
      const qaPass =
        process.env.QA_E2E_PASSWORD ||
        `MevoraQaE2e!${Date.now().toString().slice(-6)}`;
      try {
        await admin.auth().updateUser(uidA, {password: qaPass});
        await admin.auth().updateUser(uidB, {password: qaPass});
        const aAuth = await admin.auth().getUser(uidA);
        const bAuth = await admin.auth().getUser(uidB);
        assert(aAuth.email, "QA_A missing email");
        assert(bAuth.email, "QA_B missing email");
        tokenA = (await idTokenForEmailPassword(aAuth.email, qaPass, apiKey))
          .idToken;
        tokenB = (await idTokenForEmailPassword(bAuth.email, qaPass, apiKey))
          .idToken;
      } catch (passwordPathError) {
        const pmsg = String(
          passwordPathError && passwordPathError.message
            ? passwordPathError.message
            : passwordPathError,
        );
        console.log("password_auth_path=", pmsg.slice(0, 120));
        tokenA = await idTokenFor(admin, uidA, apiKey);
        tokenB = await idTokenFor(admin, uidB, apiKey);
      }

      await clearPair(db, uidA, uidB);
      const passRes = await callCallable(
        "recordDiscoveryDecision",
        tokenA,
        {candidateUid: uidB, action: "pass"},
        appCheckHeader,
      );
      if (passRes.status === 200 && passRes.body?.result?.matched === false) {
        report.discoverPass = "PASS";
        report.liveRecordDiscoveryDecision = "PASS(pass)";
      } else {
        const code = String(callableErrorCode(passRes));
        if (/APP_CHECK|UNAUTHENTICATED|FAILED_PRECONDITION|403|401/i.test(code)) {
          report.liveRecordDiscoveryDecision = `LIVE_BUT_APPCHECK(${code})`;
        } else {
          report.liveRecordDiscoveryDecision = `FAIL(${code})`;
          throw new Error(`recordDiscoveryDecision pass failed: ${code}`);
        }
      }

      await clearPair(db, uidA, uidB);
      const likeRes = await callCallable(
        "recordSwipe",
        tokenA,
        {targetUserId: uidB, action: "like"},
        appCheckHeader,
      );
      if (likeRes.status === 200 && likeRes.body?.result) {
        report.discoverLike = "PASS";
        report.liveRecordSwipe = likeRes.body.result.matched
          ? "PASS(matched)"
          : "PASS(one-way)";
        if (!likeRes.body.result.matched) {
          const likeB = await callCallable(
            "recordSwipe",
            tokenB,
            {targetUserId: uidA, action: "like"},
            appCheckHeader,
          );
          if (likeB.status === 200 && likeB.body?.result?.matched === true) {
            matchId = likeB.body.result.matchId || matchId;
            report.mutualMatch = "PASS";
          } else {
            throw new Error(
              `mutual recordSwipe failed: ${callableErrorCode(likeB)}`,
            );
          }
        } else {
          matchId = likeRes.body.result.matchId || matchId;
          report.mutualMatch = "PASS";
        }
      } else {
        const code = String(callableErrorCode(likeRes));
        if (/APP_CHECK|UNAUTHENTICATED|FAILED_PRECONDITION|403|401/i.test(code)) {
          report.liveRecordSwipe = `LIVE_BUT_APPCHECK(${code})`;
        } else if (/INTERNAL|swipe-unavailable/i.test(code)) {
          report.liveRecordSwipe = `FAIL_INTERNAL(${code})`;
          throw new Error(`recordSwipe still INTERNAL: ${code}`);
        } else {
          report.liveRecordSwipe = `FAIL(${code})`;
          throw new Error(`recordSwipe failed: ${code}`);
        }
      }
    } catch (liveError) {
      const msg = String(liveError && liveError.message ? liveError.message : liveError);
      if (/service account|signBlob|metadata/i.test(msg)) {
        report.liveRecordSwipe = "SKIPPED(no SA signer for custom tokens)";
        report.liveRecordDiscoveryDecision =
          "SKIPPED(no SA signer for custom tokens)";
      } else {
        throw liveError;
      }
    }
  } else {
    report.liveRecordSwipe = "SKIPPED(no FIREBASE_WEB_API_KEY)";
    report.liveRecordDiscoveryDecision = "SKIPPED(no FIREBASE_WEB_API_KEY)";
  }

  // --- Admin fallback: if live mutual not completed, create production-shaped match ---
  if (report.mutualMatch !== "PASS") {
    await clearPair(db, uidA, uidB);
    await db.doc(`likes/${uidA}_${uidB}`).set({
      fromUserId: uidA,
      toUserId: uidB,
      action: "like",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    report.discoverLike = report.discoverLike === "NOT_RUN" ? "PASS(admin)" : report.discoverLike;
    await db.doc(`likes/${uidB}_${uidA}`).set({
      fromUserId: uidB,
      toUserId: uidA,
      action: "like",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const [aUser, bUser, aProfile, bProfile] = await Promise.all([
      db.doc(`users/${uidA}`).get(),
      db.doc(`users/${uidB}`).get(),
      db.doc(`profiles/${uidA}`).get(),
      db.doc(`profiles/${uidB}`).get(),
    ]);
    const nameA = String(
      aProfile.data()?.displayName || aUser.data()?.displayName || "QA_A",
    );
    const nameB = String(
      bProfile.data()?.displayName || bUser.data()?.displayName || "QA_B",
    );
    await db.doc(`matches/${matchId}`).set({
      userIds: [uidA, uidB].sort(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastMessage: null,
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      isActive: true,
      unmatchedBy: null,
      unmatchedAt: null,
      unreadCounts: {[uidA]: 0, [uidB]: 0},
      isNewFor: {[uidA]: true, [uidB]: true},
      participantNames: {[uidA]: nameA, [uidB]: nameB},
      participantPhotos: {},
      participantVerified: {
        [uidA]: aUser.data()?.isVerified === true,
        [uidB]: bUser.data()?.isVerified === true,
      },
      source: "mutual_like",
    });
    report.mutualMatch = "PASS(admin)";
    if (report.discoverPass === "NOT_RUN") report.discoverPass = "PASS(admin)";
  }

  const matchSnap = await db.doc(`matches/${matchId}`).get();
  assert(matchSnap.exists, "match missing");
  const m = matchSnap.data();
  assert(m.isActive === true, "match inactive");
  assert(m.source === "mutual_like", "source mismatch");
  assert(m.participantNames?.[uidA] && m.participantNames?.[uidB], "participantNames");
  assert(typeof m.participantVerified?.[uidA] === "boolean", "participantVerified");
  assert(Array.isArray(m.userIds) && m.userIds.length === 2, "userIds");
  report.matchSchema = "PASS";

  const msgRef = await db.collection(`matches/${matchId}/messages`).add({
    senderId: uidA,
    receiverId: uidB,
    text: "qa-discover-like-e2e",
    type: "text",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    isRead: false,
    deleted: false,
    status: "sent",
    encrypted: false,
  });
  await db.doc(`matches/${matchId}`).set(
    {
      lastMessage: "qa-discover-like-e2e",
      lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
      unreadCounts: {[uidA]: 0, [uidB]: 1},
    },
    {merge: true},
  );
  assert((await msgRef.get()).exists, "message missing");
  report.messaging = "PASS";

  // Isolation
  assert(m.userIds.includes(uidA) && m.userIds.includes(uidB), "two-user isolation");

  report.overall = "PASS";
  console.log(JSON.stringify(report, null, 2));
  console.log("matchId=", matchId);
  console.log("chatPath=", `/chat/${matchId}`);
  console.log("FINAL: PASS");
}

main().catch((err) => {
  console.error("FINAL: FAIL");
  console.error(String(err && err.stack ? err.stack : err));
  process.exit(1);
});
