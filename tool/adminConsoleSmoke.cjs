#!/usr/bin/env node
/**
 * End-to-end smoke test of the Trust & Safety console against the Emulator
 * Suite: drives mevora-admin-web over HTTP exactly as a browser would
 * (cookies, antiforgery tokens, form posts), with the real admin callables
 * and the seeded world from tool/seedEmulatorAdminQa.cjs behind it. Then
 * checks the resulting Firestore state directly.
 *
 * Local only: refuses any non-localhost console URL or non-emulator Firestore.
 *
 *   node tool/seedEmulatorAdminQa.cjs          (fresh seed first)
 *   $env:ADMIN_WEB_URL = "http://localhost:5310"
 *   node tool/adminConsoleSmoke.cjs
 */
const path = require("node:path");
const {createRequire} = require("node:module");
const assert = require("node:assert/strict");

const BASE = process.env.ADMIN_WEB_URL || "http://localhost:5310";
const PASSWORD = process.env.ADMIN_QA_PASSWORD || "MevoraAdminQa!2026";
if (!/^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(BASE)) {
  console.error(`REFUSING TO RUN: ADMIN_WEB_URL=${BASE} is not a local console.`);
  process.exit(1);
}
if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || "")) {
  console.error("REFUSING TO RUN: FIRESTORE_EMULATOR_HOST must point at a local emulator.");
  process.exit(1);
}
const admin = createRequire(path.join(__dirname, "..", "functions", "package.json"))("firebase-admin");
admin.initializeApp({projectId: process.env.QA_PROJECT_ID || "mevora-d6ed0"});
const db = admin.firestore();

class Browser {
  constructor(name) {
    this.name = name;
    // The console defaults to Turkish; the assertions below read the English source text.
    this.cookies = new Map([[".AspNetCore.Culture", "c%3Den%7Cuic%3Den"]]);
  }
  cookieHeader() {
    return [...this.cookies].map(([k, v]) => `${k}=${v}`).join("; ");
  }
  absorb(response) {
    for (const line of response.headers.getSetCookie?.() ?? []) {
      const [pair] = line.split(";");
      const eq = pair.indexOf("=");
      const key = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      if (/expires=Thu, 01 Jan 1970/i.test(line) || value === "") this.cookies.delete(key);
      else this.cookies.set(key, value);
    }
  }
  async get(p) {
    const response = await fetch(BASE + p, {headers: {cookie: this.cookieHeader()}, redirect: "manual"});
    this.absorb(response);
    return {status: response.status, location: response.headers.get("location"), html: await response.text(), type: response.headers.get("content-type")};
  }
  token(html) {
    const m = html.match(/name="__RequestVerificationToken" type="hidden" value="([^"]+)"/);
    assert.ok(m, `${this.name}: no antiforgery token`);
    return m[1];
  }
  async post(pagePath, handlerPath, fields) {
    const page = await this.get(pagePath);
    const body = new URLSearchParams({...fields, __RequestVerificationToken: this.token(page.html)});
    const response = await fetch(BASE + handlerPath, {
      method: "POST",
      headers: {cookie: this.cookieHeader(), "content-type": "application/x-www-form-urlencoded"},
      body,
      redirect: "manual",
    });
    this.absorb(response);
    return {status: response.status, location: response.headers.get("location"), html: await response.text()};
  }
  /** Follows a post/redirect/get and returns the page that shows the flash. */
  async act(pagePath, handlerPath, fields) {
    const r = await this.post(pagePath, handlerPath, fields);
    assert.equal(r.status, 302, `${this.name}: ${handlerPath} → ${r.status}`);
    return this.get(r.location.replace(BASE, ""));
  }
  async login(email) {
    const r = await this.post("/Login", "/Login?handler=Password", {Email: email, Password: PASSWORD});
    return r;
  }
}

const key = (label) => `web-smoke-${label}-${Date.now().toString(36)}`;
const results = [];
async function step(name, fn) {
  try {
    await fn();
    results.push(["PASS", name]);
    console.log(`PASS  ${name}`);
  } catch (error) {
    results.push(["FAIL", name]);
    console.log(`FAIL  ${name}\n      ${error.message.split("\n")[0]}`);
  }
}
const flash = (html) => (html.match(/class="alert alert-(ok|error)"[^>]*>([^<]+)</) ?? [])[2] ?? "";

async function main() {
  const mod = new Browser("moderator");
  const senior = new Browser("senior");
  const support = new Browser("support");
  const tsa = new Browser("tsa");
  const superAdmin = new Browser("super");

  await step("T2 a member account cannot sign in to the console", async () => {
    const member = new Browser("member");
    const r = await member.login("qa_ts_active@mevora.test");
    assert.equal(r.status, 200);
    assert.match(r.html, /does not have access/);
    assert.equal((await member.get("/Dashboard")).status, 302);
  });

  await step("T2b an unauthenticated request is sent to sign in", async () => {
    const r = await new Browser("anon").get("/Users");
    assert.equal(r.status, 302);
    assert.match(r.location, /\/Login/);
  });

  await step("T1/T3 moderator signs in and the dashboard loads with live counters", async () => {
    const r = await mod.login("moderator@mevora.test");
    assert.equal(r.status, 302);
    const d = await mod.get("/Dashboard");
    assert.equal(d.status, 200);
    assert.match(d.html, /Critical cases/);
  });

  await step("T4 user search by name and by exact email", async () => {
    const byName = await mod.get("/Users?q=ruzgar");
    assert.match(byName.html, /qa_ts_reported/);
    const byEmail = await mod.get("/Users?q=qa_ts_photo%40mevora.test");
    assert.match(byEmail.html, /qa_ts_photo/);
  });

  let underageCase = "";
  await step("T11/T12 report queue is prioritised; moderator claims the critical case", async () => {
    const reports = await mod.get("/Reports");
    assert.match(reports.html, /Underage/);
    const cases = await mod.get("/Cases");
    underageCase = (cases.html.match(/href="\/Cases\/(case_[a-z0-9_]+)"/) ?? [])[1];
    assert.ok(underageCase);
    const claimed = await mod.act(`/Cases/${underageCase}`, `/Cases/${underageCase}?handler=Claim`, {});
    assert.match(flash(claimed.html), /assigned to you/);
  });

  await step("T5/T7 moderator suspends the reported member, linked to the case", async () => {
    const page = await mod.act(`/Users/qa_ts_reported?caseId=${underageCase}`, "/Users/qa_ts_reported?handler=Suspend", {
      reasonCode: "UNDERAGE", duration: "24", internalNote: "Pending age check", caseId: underageCase, idempotencyKey: key("suspend"),
    });
    assert.match(flash(page.html), /suspended for 24 hour/);
    const user = await db.doc("users/qa_ts_reported").get();
    assert.equal(user.get("accountStatus"), "suspended");
    const c = await db.doc(`moderationCases/${underageCase}`).get();
    assert.equal(c.get("actionIds").length, 1);
  });

  await step("T6 moderator warns a member", async () => {
    const page = await mod.act("/Users/qa_ts_active", "/Users/qa_ts_active?handler=Warn", {
      reasonCode: "SPAM", userMessage: "Please avoid copy-paste openers.", caseId: "", idempotencyKey: key("warn"),
    });
    assert.match(flash(page.html), /Warning issued/);
  });

  await step("T8 moderator cannot ban — not offered, and refused by the server when forced", async () => {
    const page = await mod.get("/Users/qa_ts_active");
    assert.doesNotMatch(page.html, /Ban permanently/);
    const forced = await mod.act("/Users/qa_ts_active", "/Users/qa_ts_active?handler=Ban", {
      reasonCode: "SPAM", internalNote: "forced", confirmWord: "BAN", caseId: "", idempotencyKey: key("forced-ban"),
    });
    assert.match(flash(forced.html), /role does not allow/);
    assert.equal((await db.doc("users/qa_ts_active").get()).get("accountStatus"), "active");
  });

  await step("T14 photo manual review: preview served privately, approve publishes via the ledger", async () => {
    const queue = await mod.get("/Photos");
    assert.match(queue.html, /qa_ts_photo_img1/);
    const preview = await mod.get("/Photos?handler=Preview&uid=qa_ts_photo&imageId=qa_ts_photo_img1");
    assert.equal(preview.status, 200);
    assert.equal(preview.type, "image/png");
    const page = await mod.act("/Photos", "/Photos?handler=Decide", {
      uid: "qa_ts_photo", imageId: "qa_ts_photo_img1", decision: "approve", reasonCode: "", internalNote: "", filter: "manual_review", idempotencyKey: key("photo"),
    });
    assert.match(flash(page.html), /approved/);
    const ledger = await db.doc("users/qa_ts_photo/photoModeration/qa_ts_photo_img1").get();
    assert.equal(ledger.get("status"), "approved");
    assert.match(String(ledger.get("storagePath")), /\/profile\/photos\//);
  });

  await step("T13 moderator closes the case; its report closes with it", async () => {
    const page = await mod.act(`/Cases/${underageCase}`, `/Cases/${underageCase}?handler=Resolve`, {
      outcome: "resolved", code: "action_taken", note: "Suspended pending age verification.",
    });
    assert.match(flash(page.html), /resolved/);
    assert.equal((await db.doc("reports/qa_ts_report_3").get()).get("status"), "resolved");
  });

  await step("T20 automation manual review is visible to moderators with limited actions", async () => {
    const page = await mod.get("/Automation");
    assert.match(page.html, /deletion_verify_qa_ts_deleted/);
    assert.match(page.html, /Escalate/);
    assert.doesNotMatch(page.html, /<option value="resolve">/);
  });

  await step("T9 senior moderator bans; sign-in is disabled", async () => {
    assert.equal((await senior.login("senior@mevora.test")).status, 302);
    const page = await senior.act("/Users/qa_ts_active", "/Users/qa_ts_active?handler=Ban", {
      reasonCode: "SCAM_FRAUD", internalNote: "Confirmed scam pattern", confirmWord: "BAN", caseId: "", idempotencyKey: key("ban"),
    });
    assert.match(flash(page.html), /permanently banned/);
    const user = await admin.auth().getUser("qa_ts_active");
    assert.equal(user.disabled, true);
  });

  await step("T10 senior moderator restores the banned member", async () => {
    const page = await senior.act("/Users/qa_ts_active", "/Users/qa_ts_active?handler=Restore", {
      reasonCode: "ERROR_CORRECTION", internalNote: "Wrong account", idempotencyKey: key("restore"),
    });
    assert.match(flash(page.html), /restored/);
    assert.equal((await admin.auth().getUser("qa_ts_active")).disabled, false);
    const actions = await db.collection("moderationActions").where("targetUserId", "==", "qa_ts_active").get();
    assert.ok(actions.docs.some((d) => d.get("type") === "PERMANENT_BAN" && d.get("overturnedByActionId")));
  });

  await step("T19 require re-verification clears the badge (no mark-verified control exists)", async () => {
    const page = await senior.get("/Users/qa_ts_verified");
    assert.doesNotMatch(page.html, /mark verified|force verif/i);
    const after = await senior.act("/Users/qa_ts_verified", "/Users/qa_ts_verified?handler=Reverify", {
      reasonCode: "IMPERSONATION", internalNote: "Photos do not match", idempotencyKey: key("reverify"),
    });
    assert.match(flash(after.html), /Re-verification required/);
    assert.equal((await db.doc("users/qa_ts_verified").get()).get("isVerified"), false);
    assert.equal((await db.doc("users/qa_ts_verified/verification/identity").get()).get("status"), "expired");
  });

  await step("T21 senior accepts the appeal; the suspension is lifted by a new action", async () => {
    const list = await senior.get("/Appeals");
    const appealId = (list.html.match(/href="\/Appeals\/(appeal_[a-z0-9_]+)"/) ?? [])[1];
    assert.ok(appealId);
    const page = await senior.act(`/Appeals/${appealId}`, `/Appeals/${appealId}?handler=Resolve`, {
      decision: "accept", userMessage: "We reviewed your messages and lifted the suspension.", internalNote: "", idempotencyKey: key("appeal"),
    });
    assert.match(flash(page.html), /accepted/);
    assert.equal((await db.doc("users/qa_ts_appeal").get()).get("accountStatus"), "active");
    assert.equal((await db.doc("moderationActions/act_seed_appealed").get()).get("type"), "TEMPORARY_SUSPENSION");
  });

  await step("T22 safety timeline shows the new decisions", async () => {
    const page = await senior.get("/Users/qa_ts_reported");
    assert.match(page.html, /Account suspended/);
    assert.match(page.html, /Report received/);
  });

  await step("T16 support agent replies on a ticket; notes stay internal; no access to cases", async () => {
    assert.equal((await support.login("support@mevora.test")).status, 302);
    const reply = await support.act("/Support/qa_ts_ticket_app", "/Support/qa_ts_ticket_app?handler=Reply", {
      text: "Thanks for telling us. We have blocked the new account.", idempotencyKey: key("reply"),
    });
    assert.match(flash(reply.html), /Reply sent/);
    await support.act("/Support/qa_ts_ticket_app", "/Support/qa_ts_ticket_app?handler=Note", {text: "Matches case on the same member."});
    const thread = await db.collection("supportTickets/qa_ts_ticket_app/messages").get();
    const notes = await db.collection("supportTickets/qa_ts_ticket_app/internalNotes").get();
    assert.equal(thread.size, 1);
    assert.equal(notes.size, 1);
    assert.equal(thread.docs[0].get("visibility"), "user");
    assert.equal((await support.get("/Cases")).status, 403);
  });

  await step("T17 verification queue shows provider status only", async () => {
    assert.equal((await tsa.login("tsa@mevora.test")).status, 302);
    const page = await tsa.get("/Verification?filter=in_review");
    assert.match(page.html, /Vera Verifying/);
    assert.doesNotMatch(page.html, /seed-session-review-0002/);
  });

  await step("T15 photo decisions are final: a second decision is refused", async () => {
    const page = await tsa.act("/Photos", "/Photos?handler=Decide", {
      uid: "qa_ts_photo", imageId: "qa_ts_photo_img1", decision: "approve", reasonCode: "", internalNote: "", filter: "manual_review", idempotencyKey: key("photo-again"),
    });
    assert.match(flash(page.html), /already has a final decision/);
  });

  await step("Sensitive reveal is audited", async () => {
    const before = (await db.collection("adminAuditLog").where("action", "==", "SENSITIVE_PROFILE_VIEWED").get()).size;
    const r = await tsa.post("/Users/qa_ts_support", "/Users/qa_ts_support?handler=Reveal", {justification: "Identity check for ticket qa_ts_ticket_app"});
    assert.equal(r.status, 200);
    assert.match(r.html, /qa_ts_support@mevora\.test/);
    const after = (await db.collection("adminAuditLog").where("action", "==", "SENSITIVE_PROFILE_VIEWED").get()).size;
    assert.equal(after, before + 1);
  });

  await step("T23 audit log records the session's decisions", async () => {
    const page = await tsa.get("/Audit");
    for (const action of ["USER_SUSPENDED", "USER_BANNED", "USER_RESTORED", "PHOTO_APPROVED", "APPEAL_ACCEPTED", "ADMIN_LOGIN", "SUPPORT_REPLIED"]) {
      assert.match(page.html, new RegExp(action));
    }
  });

  await step("Staff management: super admin disables and re-enables a staff member", async () => {
    assert.equal((await superAdmin.login("super@mevora.test")).status, 302);
    const off = await superAdmin.act("/Admin/Staff", "/Admin/Staff?handler=Disable", {targetUid: "qa_staff_support", reason: "Leaving the team"});
    assert.match(flash(off.html), /disabled/);
    // The disabled agent's live session is refused on the next request.
    const next = await support.get("/Support");
    assert.equal(next.status, 302);
    await superAdmin.act("/Admin/Staff", "/Admin/Staff?handler=Enable", {targetUid: "qa_staff_support", reason: "Back"});
    assert.equal((await db.doc("adminStaff/qa_staff_support").get()).get("status"), "active");
  });

  await step("T25 no console route exposes private conversations", async () => {
    for (const p of ["/Chats", "/Messages", "/Users/qa_ts_reported/Messages", "/Conversations"]) {
      assert.equal((await superAdmin.get(p)).status, 404, p);
    }
  });

  const failed = results.filter(([s]) => s === "FAIL").length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  process.exit(failed ? 1 : 0);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
