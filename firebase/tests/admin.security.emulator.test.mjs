/**
 * Admin / Trust & Safety data boundaries, executed against the emulator.
 *
 * The admin console reaches its data only through server-side admin commands
 * (Admin SDK, rules bypassed). These tests prove the other half: no client —
 * an ordinary member, a curious attacker, or even a signed-in staff member
 * carrying the admin claim — can read or write the control-plane collections
 * directly, and the new member-facing surfaces (appeals, support thread) are
 * owner-only.
 */
import {after, before, beforeEach, describe, it} from "node:test";
import {
  UID,
  MATCH_AB,
  activeMatchAB,
  actorsFor,
  allow,
  baseAccount,
  createSecurityEnv,
  deny,
  encryptedMessage,
  resetState,
  seed,
} from "./helpers/securityHarness.mjs";

let env;
let who;

const CONTROL_PLANE_DOCS = [
  "adminStaff/staff-1",
  "moderationCases/case_1",
  "moderationCases/case_1/notes/note_1",
  "moderationCaseKeys/key_1",
  "moderationActions/act_1",
  "adminAuditLog/aud_1",
  "adminUserLookup/user-a",
  "adminRateLimits/staff-1_read",
  "appOperationsConfig/current",
  "appOperationsConfigWrites/w_1",
];

before(async () => {
  env = await createSecurityEnv({storage: true});
  who = actorsFor(env);
});

after(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await resetState(env, {storage: true});
  await seed(env, async (ctx) => {
    const db = ctx.firestore();
    for (const path of CONTROL_PLANE_DOCS) {
      await db.doc(path).set({seeded: true, userId: UID.A, subjectUserId: UID.A, targetUserId: UID.A});
    }
    await db.doc("appOperationsConfig/public").set({schemaVersion: 1, revision: 1, maintenance: {enabled: false}});
    await db.doc("reports/r1").set({reporterId: UID.B, reportedUserId: UID.A, reason: "spam", status: "open"});
    await db.doc(`appeals/appeal_1`).set({userId: UID.A, status: "open", reason: "please"});
    await db.doc("supportTickets/t1").set({userId: UID.A, status: "open", subject: "Help", message: "..."});
    await db.doc("supportTickets/t1/messages/m1").set({visibility: "user", type: "support", text: "Hello"});
    await db.doc("supportTickets/t1/internalNotes/n1").set({text: "internal", authorUid: "staff-1"});
    await db.doc(`users/${UID.A}`).set(baseAccount(UID.A));
    await db.doc(`users/${UID.B}`).set(baseAccount(UID.B));
    await db.doc(`matches/${MATCH_AB}`).set(activeMatchAB());
  });
});

const staff = (role) => env.authenticatedContext(`staff-${role}`, {admin: true, adminRole: role}).firestore();
const legacyAdmin = () => env.authenticatedContext("admin-1", {admin: true}).firestore();

describe("admin control-plane collections are closed to every client", () => {
  for (const path of CONTROL_PLANE_DOCS) {
    it(`${path}: members cannot read or write`, async () => {
      await deny(who.userA.db().doc(path).get());
      await deny(who.userC.db().doc(path).get());
      await deny(who.anon.db().doc(path).get());
      await deny(who.userA.db().doc(path).set({hacked: true}));
      await deny(who.userA.db().doc(path).delete());
    });

    it(`${path}: even a staff token cannot read or write directly`, async () => {
      await deny(staff("super_admin").doc(path).get());
      await deny(staff("super_admin").doc(path).set({hacked: true}, {merge: true}));
      await deny(staff("super_admin").doc(path).delete());
      await deny(legacyAdmin().doc(path).get());
    });
  }

  it("a member cannot promote themselves by writing an adminStaff record", async () => {
    await deny(who.userA.db().doc(`adminStaff/${UID.A}`).set({role: "super_admin", status: "active"}));
  });

  it("the audit log cannot be listed or appended to by a client", async () => {
    await deny(who.userA.db().collection("adminAuditLog").get());
    await deny(staff("trust_safety_admin").collection("adminAuditLog").get());
    await deny(who.userA.db().collection("adminAuditLog").add({action: "USER_BANNED"}));
  });
});

describe("App Control public projection", () => {
  it("anyone — signed in or not — can read the public projection", async () => {
    await allow(who.anon.db().doc("appOperationsConfig/public").get());
    await allow(who.userA.db().doc("appOperationsConfig/public").get());
  });

  it("nobody can write it, list the collection, or read the full record", async () => {
    await deny(who.userA.db().doc("appOperationsConfig/public").set({maintenance: {enabled: true}}));
    await deny(who.anon.db().doc("appOperationsConfig/public").set({maintenance: {enabled: true}}));
    await deny(staff("super_admin").doc("appOperationsConfig/public").set({features: {boost: false}}, {merge: true}));
    await deny(who.userA.db().doc("appOperationsConfig/public").delete());
    await deny(who.userA.db().collection("appOperationsConfig").get());
    await deny(who.anon.db().doc("appOperationsConfig/current").get());
  });
});

describe("legacy admin-claim read grants exclude support agents", () => {
  it("a support agent's token cannot read reports directly", async () => {
    await deny(staff("support_agent").doc("reports/r1").get());
  });

  it("moderation roles and legacy admins keep their read-only access", async () => {
    await allow(staff("moderator").doc("reports/r1").get());
    await allow(legacyAdmin().doc("reports/r1").get());
    await deny(staff("moderator").doc("reports/r1").update({status: "dismissed"}));
  });
});

describe("appeals — owner may read, nobody may write", () => {
  it("the appellant reads their own appeal", async () => {
    await allow(who.userA.db().doc("appeals/appeal_1").get());
  });

  it("another member cannot read it", async () => {
    await deny(who.userC.db().doc("appeals/appeal_1").get());
  });

  it("clients cannot file, edit or decide an appeal directly", async () => {
    await deny(who.userA.db().doc("appeals/appeal_2").set({userId: UID.A, status: "open"}));
    await deny(who.userA.db().doc("appeals/appeal_1").update({status: "resolved", decision: "accepted"}));
    await deny(who.userA.db().doc("appeals/appeal_1").delete());
  });
});

describe("support thread and internal notes", () => {
  it("the ticket owner reads the user-visible thread", async () => {
    await allow(who.userA.db().doc("supportTickets/t1/messages/m1").get());
  });

  it("another member cannot read the thread", async () => {
    await deny(who.userC.db().doc("supportTickets/t1/messages/m1").get());
  });

  it("nobody — the owner included — reads internal notes", async () => {
    await deny(who.userA.db().doc("supportTickets/t1/internalNotes/n1").get());
    await deny(staff("support_agent").doc("supportTickets/t1/internalNotes/n1").get());
  });

  it("clients cannot write into the thread or the notes", async () => {
    await deny(who.userA.db().doc("supportTickets/t1/messages/m2").set({visibility: "user", text: "fake support"}));
    await deny(who.userA.db().doc("supportTickets/t1/internalNotes/n2").set({text: "x"}));
  });

  it("a client cannot pre-set server-owned ticket fields at creation", async () => {
    const base = {
      userId: UID.A,
      status: "open",
      category: "account",
      subject: "Help",
      message: "Something is wrong",
      attachments: [],
    };
    await allow(who.userA.db().doc("supportTickets/ok").set(base));
    await deny(who.userA.db().doc("supportTickets/p1").set({...base, priority: "urgent"}));
    await deny(who.userA.db().doc("supportTickets/p2").set({...base, assignedTo: "staff-1"}));
    await deny(who.userA.db().doc("supportTickets/p3").set({...base, resolvedBy: "staff-1"}));
  });
});

describe("restricted accounts cannot message through direct writes", () => {
  const send = (id) =>
    who.userA.db().doc(`matches/${MATCH_AB}/messages/${id}`).set(
      encryptedMessage({senderId: UID.A, receiverId: UID.B}),
    );

  it("an active account still sends encrypted messages", async () => {
    await allow(send("ok1"));
  });

  it("a suspended account cannot send", async () => {
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {
      accountStatus: "suspended",
      isSuspended: true,
      suspendedUntil: new Date(Date.now() + 24 * 60 * 60 * 1000),
    })));
    await deny(send("s1"));
  });

  it("a suspension without an end date blocks until restored", async () => {
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {
      accountStatus: "suspended",
      isSuspended: true,
    })));
    await deny(send("s2"));
  });

  it("a suspension that has ended no longer blocks", async () => {
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {
      accountStatus: "suspended",
      isSuspended: true,
      suspendedUntil: new Date(Date.now() - 60 * 1000),
    })));
    await allow(send("s3"));
  });

  it("a banned account cannot send, by canonical status or legacy flag", async () => {
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {accountStatus: "banned"})));
    await deny(send("b1"));
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {isBanned: true})));
    await deny(send("b2"));
  });

  it("the E2EE contract is unchanged: plaintext is still refused", async () => {
    await deny(
      who.userA.db().doc(`matches/${MATCH_AB}/messages/plain`).set(
        encryptedMessage({senderId: UID.A, receiverId: UID.B, overrides: {encrypted: false, text: "hello"}}),
      ),
    );
  });

  it("a member cannot lift their own restriction", async () => {
    await seed(env, (ctx) => ctx.firestore().doc(`users/${UID.A}`).set(baseAccount(UID.A, {accountStatus: "suspended", isSuspended: true})));
    await deny(who.userA.db().doc(`users/${UID.A}`).update({accountStatus: "active"}));
    await deny(who.userA.db().doc(`users/${UID.A}`).update({isSuspended: false}));
    await deny(who.userA.db().doc(`users/${UID.A}`).update({suspendedUntil: null}));
    await deny(who.userA.db().doc(`users/${UID.A}`).update({statusActionId: "forged"}));
  });
});

describe("storage — quarantined photos are server-only", () => {
  it("nobody can read or write the moderation quarantine prefix", async () => {
    await seed(env, async (ctx) => {
      await ctx.storage().ref(`moderation/quarantine/${UID.A}/p1.jpg`).put(new Uint8Array([1, 2, 3]), {contentType: "image/jpeg"});
    });
    await deny(who.userA.bucket().ref(`moderation/quarantine/${UID.A}/p1.jpg`).getDownloadURL());
    await deny(who.userC.bucket().ref(`moderation/quarantine/${UID.A}/p1.jpg`).getDownloadURL());
    await deny(who.userA.bucket().ref(`moderation/quarantine/${UID.A}/p2.jpg`).put(new Uint8Array([1]), {contentType: "image/jpeg"}));
  });
});
