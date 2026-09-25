/**
 * Read-only backend evidence collector for the Core Dating Flow acceptance.
 * Emulator-only: refuses to run without FIRESTORE_EMULATOR_HOST.
 *
 * Usage: node inspectCoreQa.cjs <uidA> <uidB>
 */
if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("refusing to run: set FIRESTORE_EMULATOR_HOST");
  process.exit(2);
}

/** firebase-admin lives in functions/node_modules, not at the repo root. */
function requireAdmin() {
  const {createRequire} = require("node:module");
  const path = require("node:path");
  const fromFunctions = createRequire(
    path.join(__dirname, "..", "functions", "package.json"),
  );
  try {
    return fromFunctions("firebase-admin");
  } catch (_) {
    try {
      return require("firebase-admin");
    } catch (_err) {
      console.error(
        "firebase-admin not found — run: npm --prefix functions ci",
      );
      process.exit(2);
    }
  }
}
const admin = requireAdmin();

const [uidA, uidB] = process.argv.slice(2);
if (!uidA || !uidB) {
  console.error("usage: node inspectCoreQa.cjs <uidA> <uidB>");
  process.exit(2);
}

admin.initializeApp({projectId: process.env.QA_PROJECT || "mevora-d6ed0"});
const db = admin.firestore();

const ts = (v) => {
  if (!v) return null;
  if (typeof v.toDate === "function") return v.toDate().toISOString();
  return String(v);
};

async function collectionDump(name, field, uid) {
  const snap = await db.collection(name).where(field, "==", uid).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

(async () => {
  const out = {};

  // --- matches -------------------------------------------------------------
  const aMatches = await db.collection("matches").where("userIds", "array-contains", uidA).get();
  const pairMatches = aMatches.docs.filter((d) => (d.data().userIds || []).includes(uidB));
  out.matches = {
    totalContainingA: aMatches.size,
    pairMatchCount: pairMatches.length,
    docs: pairMatches.map((d) => {
      const m = d.data();
      return {
        id: d.id,
        userIds: m.userIds,
        isActive: m.isActive,
        createdAt: ts(m.createdAt),
        compatibilityScore: m.compatibilityScore ?? null,
        compatibilityCalculatedAt: ts(m.compatibilityCalculatedAt),
        hasSnapshots: !!m.compatibilitySnapshots,
        lastMessage: m.lastMessage ?? null,
        unmatchedBy: m.unmatchedBy ?? null,
      };
    }),
  };

  // --- likes / decisions ---------------------------------------------------
  for (const coll of ["likes", "passes", "swipes", "decisions", "userDecisions"]) {
    try {
      const snap = await db.collection(coll).limit(50).get();
      if (!snap.empty) {
        out[coll] = snap.docs
          .map((d) => ({id: d.id, ...d.data()}))
          .filter((r) => {
            const vals = Object.values(r).map(String);
            return vals.includes(uidA) || vals.includes(uidB);
          })
          .map((r) => ({
            id: r.id,
            fromUserId: r.fromUserId ?? r.from ?? r.userId ?? null,
            toUserId: r.toUserId ?? r.to ?? r.targetUserId ?? null,
            type: r.type ?? r.action ?? r.decision ?? null,
            createdAt: ts(r.createdAt ?? r.timestamp),
          }));
      }
    } catch (_) {
      /* collection absent */
    }
  }

  // --- messages per pair match --------------------------------------------
  out.conversations = [];
  for (const d of pairMatches) {
    const msgs = await db.collection(`matches/${d.id}/messages`).orderBy("createdAt", "asc").get()
      .catch(async () => db.collection(`matches/${d.id}/messages`).get());
    out.conversations.push({
      matchId: d.id,
      messageCount: msgs.size,
      messages: msgs.docs.map((m) => {
        const x = m.data();
        return {
          id: m.id,
          senderId: x.senderId ?? x.from ?? null,
          hasPlaintextText: typeof x.text === "string" && x.text.length > 0,
          textPreview: typeof x.text === "string" ? x.text.slice(0, 60) : null,
          hasCiphertext: !!(x.ciphertext || x.encryptedContent || x.payload),
          type: x.type ?? null,
          deleted: x.deleted ?? false,
          createdAt: ts(x.createdAt ?? x.timestamp),
          readAt: ts(x.readAt),
        };
      }),
    });
  }

  // --- separate conversations collection, if the schema has one -----------
  try {
    const conv = await db.collection("conversations").limit(50).get();
    out.conversationsCollection = conv.docs
      .filter((d) => {
        const p = d.data().participants || d.data().userIds || [];
        return p.includes(uidA) && p.includes(uidB);
      })
      .map((d) => ({id: d.id, ...d.data()}));
  } catch (_) {
    /* absent */
  }

  // --- identity sanity ----------------------------------------------------
  for (const [label, uid] of [["A", uidA], ["B", uidB]]) {
    const [u, p] = await Promise.all([db.doc(`users/${uid}`).get(), db.doc(`profiles/${uid}`).get()]);
    out[`identity${label}`] = {
      uid,
      userExists: u.exists,
      profileExists: p.exists,
      displayName: p.data()?.displayName ?? null,
      isDiscoverable: p.data()?.isDiscoverable ?? null,
      profileCompleted: p.data()?.profileCompleted ?? null,
      approvedPhotos: (p.data()?.photos || []).filter((x) => x.moderationStatus === "approved").length,
      accountStatus: u.data()?.accountStatus ?? null,
      isSmokeTestUser: u.data()?.isSmokeTestUser ?? null,
    };
  }

  console.log(JSON.stringify(out, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error("inspect failed:", err && err.message ? err.message : err);
  process.exit(1);
});
