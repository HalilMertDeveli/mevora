#!/usr/bin/env node
/**
 * Seeds the Trust & Safety console's manual-QA world into the Firebase
 * Emulator Suite: staff accounts for every role and members in every state
 * the console has to handle. EMULATOR ONLY — it refuses to run otherwise.
 *
 * Staff (email / password, emulator-only credentials, see STAFF below):
 *   super@mevora.test       super_admin
 *   tsa@mevora.test         trust_safety_admin
 *   senior@mevora.test      senior_moderator
 *   moderator@mevora.test   moderator
 *   support@mevora.test     support_agent
 *
 * Members (uids prefixed qa_ts_, never overlapping the app's qa_user_*):
 *   qa_ts_active        ordinary active member
 *   qa_ts_suspended     suspended for 7 days (with its moderation action)
 *   qa_ts_banned        permanently banned, Auth disabled
 *   qa_ts_reported      three open reports (harassment ×2, underage) → cases
 *   qa_ts_photo         one photo in manual review (bytes in the Storage emulator)
 *   qa_ts_verified      identity verified by the provider (for re-verification QA)
 *   qa_ts_verifying     identity verification in review
 *   qa_ts_support       an app support ticket (+ a website ticket naming them)
 *   qa_ts_appeal        suspended, with an open appeal against it
 *   automation job      account_deletion_verify in manual_review
 *   humor item          reported humor content needing review
 *
 * Usage (repo root, emulators running with firebase.qa.json, functions built):
 *   $env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"
 *   $env:FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099"
 *   $env:FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199"
 *   node tool/seedEmulatorAdminQa.cjs
 *
 * Re-running resets exactly these accounts and documents; nothing else is
 * touched.
 */
const path = require("node:path");
const {createRequire} = require("node:module");

const PROJECT = process.env.QA_PROJECT_ID || "mevora-d6ed0";
// Emulator-only password for the seeded staff and member logins.
const PASSWORD = process.env.ADMIN_QA_PASSWORD || "MevoraAdminQa!2026";

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const storageHost = process.env.FIREBASE_STORAGE_EMULATOR_HOST;
if (!firestoreHost || !authHost) {
  console.error("REFUSING TO RUN: FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST must both be set. This script only ever seeds the Emulator Suite.");
  process.exit(1);
}
for (const [name, value] of [
  ["FIRESTORE_EMULATOR_HOST", firestoreHost],
  ["FIREBASE_AUTH_EMULATOR_HOST", authHost],
  ...(storageHost ? [["FIREBASE_STORAGE_EMULATOR_HOST", storageHost]] : []),
]) {
  if (!/^(127\.0\.0\.1|localhost|0\.0\.0\.0|10\.0\.2\.2):\d+$/.test(value)) {
    console.error(`REFUSING TO RUN: ${name}="${value}" is not a local emulator host.`);
    process.exit(1);
  }
}
if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  // Belt and braces: never run with a real credential in the environment.
  console.error("REFUSING TO RUN: unset GOOGLE_APPLICATION_CREDENTIALS; the seed needs no credential.");
  process.exit(1);
}

const functionsDir = path.join(__dirname, "..", "functions");
const fromFunctions = createRequire(path.join(functionsDir, "package.json"));
let admin;
try {
  admin = fromFunctions("firebase-admin");
} catch (_) {
  console.error("firebase-admin not found — run: npm --prefix functions ci");
  process.exit(1);
}
let intakeUserReport;
let openAppeal;
try {
  ({intakeUserReport} = require(path.join(functionsDir, "lib", "admin", "reports", "reportIntake.js")));
  ({openAppeal} = require(path.join(functionsDir, "lib", "admin", "appeals", "appealService.js")));
} catch (_) {
  console.error("functions/lib is missing — run: npm --prefix functions run build");
  process.exit(1);
}

admin.initializeApp({projectId: PROJECT, storageBucket: process.env.QA_STORAGE_BUCKET || `${PROJECT}.firebasestorage.app`});
const db = admin.firestore();
const auth = admin.auth();
const {FieldValue, Timestamp} = admin.firestore;
const now = Date.now();
const DAY = 24 * 60 * 60 * 1000;

const STAFF = [
  {uid: "qa_staff_super", email: "super@mevora.test", role: "super_admin", name: "Selin (Super admin)"},
  {uid: "qa_staff_tsa", email: "tsa@mevora.test", role: "trust_safety_admin", name: "Tolga (T&S admin)"},
  {uid: "qa_staff_senior", email: "senior@mevora.test", role: "senior_moderator", name: "Sena (Senior moderator)"},
  {uid: "qa_staff_mod", email: "moderator@mevora.test", role: "moderator", name: "Mert (Moderator)"},
  {uid: "qa_staff_support", email: "support@mevora.test", role: "support_agent", name: "Sude (Support)"},
];

const MEMBERS = {
  active: {uid: "qa_ts_active", name: "Aylin Active"},
  suspended: {uid: "qa_ts_suspended", name: "Sarp Suspended"},
  banned: {uid: "qa_ts_banned", name: "Bora Banned"},
  reported: {uid: "qa_ts_reported", name: "Rüzgar Reported"},
  photo: {uid: "qa_ts_photo", name: "Pınar Photo"},
  verified: {uid: "qa_ts_verified", name: "Veli Verified"},
  verifying: {uid: "qa_ts_verifying", name: "Vera Verifying"},
  support: {uid: "qa_ts_support", name: "Suna Support"},
  appeal: {uid: "qa_ts_appeal", name: "Arda Appeal"},
};

// A 160×160 PNG: below the pipeline's 200px minimum, so the real moderation
// trigger routes it to manual_review ("dimensions-unverified"). Flat colour.
function tinyPng() {
  const {deflateSync} = require("node:zlib");
  const width = 160;
  const height = 160;
  const raw = Buffer.alloc((width * 3 + 1) * height);
  for (let y = 0; y < height; y++) {
    const row = y * (width * 3 + 1);
    raw[row] = 0;
    for (let x = 0; x < width; x++) {
      raw[row + 1 + x * 3] = 120;
      raw[row + 2 + x * 3] = 90;
      raw[row + 3 + x * 3] = 200;
    }
  }
  const crcTable = Array.from({length: 256}, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const c = Buffer.alloc(4);
    c.writeUInt32BE(crc(td));
    return Buffer.concat([len, td, c]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(raw)),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

async function resetAuthUser(uid, props) {
  try {
    await auth.deleteUser(uid);
  } catch (_) {
    // not there yet
  }
  await auth.createUser({uid, password: PASSWORD, emailVerified: true, ...props});
}

async function deleteWhere(collection, field, value) {
  const snap = await db.collection(collection).where(field, "==", value).get();
  for (const doc of snap.docs) {
    for (const sub of ["notes", "messages", "internalNotes"]) {
      const inner = await doc.ref.collection(sub).get();
      await Promise.all(inner.docs.map((d) => d.ref.delete()));
    }
    await doc.ref.delete();
  }
}

async function purgeMember(uid) {
  await Promise.all([
    deleteWhere("reports", "reportedUserId", uid),
    deleteWhere("reports", "reporterId", uid),
    deleteWhere("moderationCases", "subjectUserId", uid),
    deleteWhere("moderationActions", "targetUserId", uid),
    deleteWhere("appeals", "userId", uid),
    deleteWhere("supportTickets", "userId", uid),
  ]);
  const ledger = await db.collection(`users/${uid}/photoModeration`).get();
  await Promise.all(ledger.docs.map((d) => d.ref.delete()));
  const keys = await db.collection("moderationCaseKeys").get();
  await Promise.all(keys.docs.filter((d) => String(d.get("correlationKey") ?? "").includes(uid)).map((d) => d.ref.delete()));
  for (const p of [`users/${uid}/verification/identity`, `profiles/${uid}`, `users/${uid}`, `adminUserLookup/${uid}`]) {
    await db.doc(p).delete();
  }
}

function fold(name) {
  return name
    .replace(/[ıİ]/g, "i").replace(/[şŞ]/g, "s").replace(/[ğĞ]/g, "g")
    .replace(/[çÇ]/g, "c").replace(/[öÖ]/g, "o").replace(/[üÜ]/g, "u")
    .normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

async function createMember({uid, name}, account = {}, profile = {}) {
  await resetAuthUser(uid, {email: `${uid}@mevora.test`, displayName: name});
  await db.doc(`users/${uid}`).set({
    uid,
    id: uid,
    email: `${uid}@mevora.test`,
    displayName: name,
    isBanned: false,
    isSuspended: false,
    isVerified: false,
    phoneVerified: false,
    accountStatus: "active",
    createdAt: Timestamp.fromMillis(now - 40 * DAY),
    lastActiveAt: Timestamp.fromMillis(now - DAY),
    ...account,
  });
  await db.doc(`profiles/${uid}`).set({
    uid,
    displayName: name,
    city: "Istanbul",
    bio: "Seeded for Trust & Safety console QA.",
    relationshipGoal: "long_term",
    interests: ["travel", "music"],
    photos: [],
    profileCompleted: true,
    isDiscoverable: true,
    createdAt: Timestamp.fromMillis(now - 40 * DAY),
    ...profile,
  });
  await db.doc(`adminUserLookup/${uid}`).set({uid, displayNameLower: fold(name), updatedAt: FieldValue.serverTimestamp()});
}

async function recordAction(id, {effectiveAtMs, ...data}) {
  await db.doc(`moderationActions/${id}`).set({
    actionId: id,
    caseId: null,
    internalNote: "Seeded for QA",
    userMessage: null,
    requestId: null,
    idempotencyKey: `seed-${id}`,
    previousState: {accountStatus: "active"},
    relatedActionId: null,
    subject: {},
    overturnedByActionId: null,
    appealId: null,
    createdAt: Timestamp.fromMillis(effectiveAtMs),
    effectiveAt: Timestamp.fromMillis(effectiveAtMs),
    ...data,
  });
}

async function main() {
  console.log(`Seeding admin QA world into project ${PROJECT} (emulator)…`);

  for (const s of STAFF) {
    await resetAuthUser(s.uid, {email: s.email, displayName: s.name});
    await auth.setCustomUserClaims(s.uid, {admin: true, adminRole: s.role});
    await db.doc(`adminStaff/${s.uid}`).set({
      uid: s.uid,
      role: s.role,
      status: "active",
      displayName: s.name,
      email: s.email,
      permissionsVersion: 1,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      createdBy: "seed",
    });
  }

  for (const member of Object.values(MEMBERS)) {
    await purgeMember(member.uid);
  }
  await db.doc("automationJobs/deletion_verify_qa_ts_deleted").delete();
  await db.doc("humorModerationQueue/qa_ts_humor_1").delete();
  await db.doc("humorContent/qa_ts_humor_1").delete();

  // Active.
  await createMember(MEMBERS.active);

  // Suspended for 7 days.
  await createMember(MEMBERS.suspended);
  const suspension = "act_seed_suspension";
  await recordAction(suspension, {
    type: "TEMPORARY_SUSPENSION", targetUserId: MEMBERS.suspended.uid, reasonCode: "HARASSMENT",
    actorAdminId: "qa_staff_mod", actorRole: "moderator", effectiveAtMs: now - DAY,
    expiresAt: Timestamp.fromMillis(now + 6 * DAY), newState: {accountStatus: "suspended"}, authEffect: "none", authSync: {status: "not_required"},
  });
  await db.doc(`users/${MEMBERS.suspended.uid}`).set({
    accountStatus: "suspended", isSuspended: true, suspendedUntil: Timestamp.fromMillis(now + 6 * DAY),
    statusReasonCode: "HARASSMENT", statusActionId: suspension, statusUpdatedAt: Timestamp.fromMillis(now - DAY),
  }, {merge: true});

  // Banned, Auth disabled.
  await createMember(MEMBERS.banned);
  const ban = "act_seed_ban";
  await recordAction(ban, {
    type: "PERMANENT_BAN", targetUserId: MEMBERS.banned.uid, reasonCode: "SCAM_FRAUD",
    actorAdminId: "qa_staff_senior", actorRole: "senior_moderator", effectiveAtMs: now - 2 * DAY,
    expiresAt: null, newState: {accountStatus: "banned"}, authEffect: "disable", authSync: {status: "done"},
  });
  await db.doc(`users/${MEMBERS.banned.uid}`).set({
    accountStatus: "banned", isBanned: true, statusReasonCode: "SCAM_FRAUD", statusActionId: ban,
    statusUpdatedAt: Timestamp.fromMillis(now - 2 * DAY),
  }, {merge: true});
  await auth.updateUser(MEMBERS.banned.uid, {disabled: true});

  // Reported three times → two correlated cases (harassment, underage).
  await createMember(MEMBERS.reported);
  const reports = [
    {id: "qa_ts_report_1", reporter: MEMBERS.active.uid, reason: "harassment", text: "Keeps messaging after I asked them to stop."},
    {id: "qa_ts_report_2", reporter: MEMBERS.support.uid, reason: "harassment", text: "Rude and threatening."},
    {id: "qa_ts_report_3", reporter: MEMBERS.verified.uid, reason: "underage", text: "Said they are 16."},
  ];
  const priorities = {harassment: ["high", 3], underage: ["critical", 4]};
  for (const [i, r] of reports.entries()) {
    await db.doc(`reports/${r.id}`).set({
      reporterId: r.reporter, reportedUserId: MEMBERS.reported.uid, reason: r.reason, description: r.text,
      matchId: [r.reporter, MEMBERS.reported.uid].sort().join("_"), messageId: `msg_seed_${i}`,
      priority: priorities[r.reason][0], priorityRank: priorities[r.reason][1],
      status: "open", createdAt: Timestamp.fromMillis(now - (3 - i) * 60 * 60 * 1000),
    });
    await intakeUserReport(db, {reportId: r.id, reporterId: r.reporter, reportedUserId: MEMBERS.reported.uid, reason: r.reason}, now);
  }

  // A photo in manual review, bytes in pending/.
  const imageId = "qa_ts_photo_img1";
  const pendingPath = `users/${MEMBERS.photo.uid}/profile/pending/${imageId}.png`;
  await createMember(MEMBERS.photo, {}, {
    profileModerationStatus: "manual_review",
    photos: [{id: imageId, storagePath: pendingPath, order: 0, isPrimary: true, moderationStatus: "manual_review"}],
  });
  await db.doc(`users/${MEMBERS.photo.uid}/photoModeration/${imageId}`).set({
    imageId, status: "manual_review", reason: "dimensions-unverified", moderatedBy: "system",
    moderatedAt: Timestamp.fromMillis(now - 2 * 60 * 60 * 1000), updatedAt: Timestamp.fromMillis(now - 2 * 60 * 60 * 1000),
  });
  if (storageHost) {
    await admin.storage().bucket().file(pendingPath).save(tinyPng(), {contentType: "image/png", resumable: false});
  } else {
    console.warn("FIREBASE_STORAGE_EMULATOR_HOST not set: the photo preview will be empty.");
  }

  // Verified by the provider, and one in review.
  await createMember(MEMBERS.verified, {isVerified: true}, {isVerified: true});
  await db.doc(`users/${MEMBERS.verified.uid}/verification/identity`).set({
    schemaVersion: 1, provider: "didit", providerSessionId: "seed-session-verified-0001", status: "verified",
    attemptCount: 1, lastEventId: "seed-evt-1", lastEventAtMs: now - 10 * DAY,
    createdAt: Timestamp.fromMillis(now - 11 * DAY), updatedAt: Timestamp.fromMillis(now - 10 * DAY), verifiedAt: Timestamp.fromMillis(now - 10 * DAY),
  });
  await createMember(MEMBERS.verifying);
  await db.doc(`users/${MEMBERS.verifying.uid}/verification/identity`).set({
    schemaVersion: 1, provider: "didit", providerSessionId: "seed-session-review-0002", status: "in_review",
    reason: "manual_review", attemptCount: 2, lastEventId: "seed-evt-2", lastEventAtMs: now - 3 * 60 * 60 * 1000,
    createdAt: Timestamp.fromMillis(now - DAY), updatedAt: Timestamp.fromMillis(now - 3 * 60 * 60 * 1000),
  });

  // Support: one app ticket, one website ticket naming the same member.
  await createMember(MEMBERS.support);
  await db.doc("supportTickets/qa_ts_ticket_app").set({
    userId: MEMBERS.support.uid, category: "safety", subject: "Someone keeps contacting me",
    message: "A match I unmatched created a new account and messaged me again.", attachments: [],
    status: "open", createdAt: Timestamp.fromMillis(now - 5 * 60 * 60 * 1000), updatedAt: Timestamp.fromMillis(now - 5 * 60 * 60 * 1000),
  });
  await db.doc("supportTickets/qa_ts_ticket_web").set({
    id: "qa_ts_ticket_web", userId: MEMBERS.support.uid, name: "Suna", email: "suna@example.com",
    category: "account_login", subject: "Cannot sign in", description: "Code never arrives.", message: "Code never arrives.",
    priority: "Urgent", status: "Open", source: "website", attachments: [],
    createdAt: Timestamp.fromMillis(now - 60 * 60 * 1000), updatedAt: Timestamp.fromMillis(now - 60 * 60 * 1000),
  });

  // Suspended with an open appeal.
  await createMember(MEMBERS.appeal);
  const appealed = "act_seed_appealed";
  await recordAction(appealed, {
    type: "TEMPORARY_SUSPENSION", targetUserId: MEMBERS.appeal.uid, reasonCode: "SPAM",
    actorAdminId: "qa_staff_mod", actorRole: "moderator", effectiveAtMs: now - 12 * 60 * 60 * 1000,
    expiresAt: Timestamp.fromMillis(now + 3 * DAY), newState: {accountStatus: "suspended"}, authEffect: "none", authSync: {status: "not_required"},
  });
  await db.doc(`users/${MEMBERS.appeal.uid}`).set({
    accountStatus: "suspended", isSuspended: true, suspendedUntil: Timestamp.fromMillis(now + 3 * DAY),
    statusReasonCode: "SPAM", statusActionId: appealed, statusUpdatedAt: Timestamp.fromMillis(now - 12 * 60 * 60 * 1000),
  }, {merge: true});
  await openAppeal(db, {
    userId: MEMBERS.appeal.uid, moderationActionId: appealed,
    reason: "I only sent the same greeting to a few matches; I did not know that counts as spam.",
    source: "app", sourceTicketId: null, openedBy: MEMBERS.appeal.uid, openedByRole: "member", requestId: null,
  }, now);

  // Automation job needing a human.
  await db.doc("automationJobs/deletion_verify_qa_ts_deleted").set({
    jobId: "deletion_verify_qa_ts_deleted", kind: "account_deletion_verify", status: "manual_review",
    idempotencyKey: "deletion_verify_qa_ts_deleted", attempts: 5, maxAttempts: 5, payload: {uid: "qa_ts_deleted"},
    error: "incomplete:account_deletion_verify", requiresHumanReview: true, createdBy: "deleteUserAccount",
    result: {complete: false, issues: ["storage_remnant:users/qa_ts_deleted/"], checkedAt: new Date(now).toISOString()},
    createdAt: Timestamp.fromMillis(now - 2 * DAY), updatedAt: Timestamp.fromMillis(now - DAY),
  });

  // Humor content needing review.
  await db.doc("humorContent/qa_ts_humor_1").set({
    contentId: "qa_ts_humor_1", type: "text", language: "en", category: "sarcasm", humorTags: [], humorVector: {sarcasm: 0.8},
    media: {textBody: "Seeded borderline joke for moderation QA."}, safetyStatus: "needs_review",
    safetyFlags: {nsfw: false, hate: false, harassment: true, violent: false, illegal: false, sexual: false, minorRelated: false, extreme: false},
    source: {type: "internal", provider: null}, active: false, stats: {viewCount: 0, ratingCount: 0, avgRating: 0},
    calibration: {eligible: false, slot: null, version: 1}, createdAt: Timestamp.fromMillis(now - DAY), updatedAt: Timestamp.fromMillis(now - DAY),
  });
  await db.doc("humorModerationQueue/qa_ts_humor_1").set({
    contentId: "qa_ts_humor_1", status: "needs_review", source: "user_report", reportCount: 2,
    lastReportedAt: Timestamp.fromMillis(now - 3 * 60 * 60 * 1000), createdAt: Timestamp.fromMillis(now - DAY), updatedAt: Timestamp.fromMillis(now - 3 * 60 * 60 * 1000),
  });

  console.log("\nStaff logins (emulator only), password from ADMIN_QA_PASSWORD or the default in this file:");
  for (const s of STAFF) console.log(`  ${s.email.padEnd(24)} ${s.role}`);
  console.log("\nMembers:", Object.values(MEMBERS).map((m) => m.uid).join(", "));
  console.log("Done.");
}

main().then(() => process.exit(0), (error) => {
  console.error(error);
  process.exit(1);
});
