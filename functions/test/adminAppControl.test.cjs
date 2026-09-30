const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {createAdminWorld, rejectsWith, key} = require("./helpers/adminHarness.cjs");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const specs = require("../lib/admin/commands.js");
const {assertAppFeatureAvailable, resetAppOperationsCache} = require("../lib/appOperations/appOperationsGate.js");
const {parseAppOperationsState} = require("../lib/appOperations/appOperationsConfig.js");

/**
 * App Control (the A-matrix): who may read and change the app's operating
 * state, that every change is revision-checked, idempotent and audited, and
 * that the switches are enforced by the backend, not only hidden in the app.
 */

async function world() {
  const w = createAdminWorld();
  await w.addStaff("owner-1", "super_admin", {isOwner: true});
  await w.addStaff("tsa-1", "trust_safety_admin");
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("support-1", "support_agent");
  await w.addMember("member-1");
  return w;
}

const pub = (w) => w.db.read("appOperationsConfig/public");
const current = (w) => w.db.read("appOperationsConfig/current");
const auditOf = (w, action) => w.db.paths().filter((p) => p.startsWith("adminAuditLog/")).map((p) => w.db.read(p)).filter((e) => e.action === action);

async function rev(w) {
  return (await w.run(specs.adminGetAppControlSpec, "owner-1")).config.revision;
}

const DAY = 24 * 60 * 60 * 1000;

describe("App Control permissions", () => {
  it("A1 a non-staff caller is refused", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminGetAppControlSpec, "member-1", {}, {admin: false}), "permission_denied");
  });

  it("A2 moderators and support agents can neither read nor write", async () => {
    const w = await world();
    for (const uid of ["mod-1", "support-1"]) {
      await rejectsWith(w.run(specs.adminGetAppControlSpec, uid), "permission_denied");
      await rejectsWith(w.run(specs.adminUpdateMaintenanceModeSpec, uid, {enabled: true, expectedRevision: 0, idempotencyKey: key()}), "permission_denied");
    }
  });

  it("A3 a Trust & Safety admin reads but cannot change anything", async () => {
    const w = await world();
    const view = await w.run(specs.adminGetAppControlSpec, "tsa-1");
    assert.equal(view.config.maintenance.enabled, false);
    const env = {expectedRevision: 0, idempotencyKey: key()};
    await rejectsWith(w.run(specs.adminUpdateMaintenanceModeSpec, "tsa-1", {enabled: true, ...env}), "permission_denied");
    await rejectsWith(w.run(specs.adminUpdateFeatureSwitchSpec, "tsa-1", {feature: "boost", enabled: false, reason: "x", ...env}), "permission_denied");
    await rejectsWith(w.run(specs.adminUpdateMinimumVersionSpec, "tsa-1", {platform: "android", minimumVersion: "9.9.9", ...env}), "permission_denied");
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "tsa-1", {enabled: false, ...env}), "permission_denied");
    assert.equal(pub(w), undefined);
  });

  it("app_control.write is super_admin only; T&S admin holds read", () => {
    const {ROLE_PERMISSIONS} = require("../lib/admin/auth/roles.js");
    for (const [role, perms] of Object.entries(ROLE_PERMISSIONS)) {
      assert.equal(perms.has("app_control.write"), role === "super_admin", role);
      assert.equal(perms.has("app_control.read"), role === "super_admin" || role === "trust_safety_admin", role);
    }
  });
});

describe("App Control changes", () => {
  it("A4/A5/A8 maintenance on and off: both documents, revision and audit", async () => {
    const w = await world();
    const on = await w.run(specs.adminUpdateMaintenanceModeSpec, "owner-1", {enabled: true, message: "Back at 03:00", expectedRevision: 0, idempotencyKey: key()});
    assert.equal(on.revision, 1);
    assert.deepEqual(pub(w).maintenance, {enabled: true, message: "Back at 03:00"});
    assert.equal(pub(w).revision, 1);
    assert.equal(pub(w).updatedBy, undefined, "the public projection carries no actor");
    assert.equal(current(w).updatedBy, "owner-1");
    const [event] = auditOf(w, "APP_MAINTENANCE_ENABLED");
    assert.equal(event.actorAdminId, "owner-1");
    assert.equal(event.targetType, "app_config");
    assert.deepEqual(event.metadata.previousValue, {enabled: false, customMessage: false});
    assert.deepEqual(event.metadata.newValue, {enabled: true, customMessage: true});

    await w.run(specs.adminUpdateMaintenanceModeSpec, "owner-1", {enabled: false, expectedRevision: 1, idempotencyKey: key()});
    assert.deepEqual(pub(w).maintenance, {enabled: false, message: null});
    assert.equal(auditOf(w, "APP_MAINTENANCE_DISABLED").length, 1);
  });

  it("A7 a change made against an old revision is refused, not merged", async () => {
    const w = await world();
    await w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "boost", enabled: false, reason: "payments incident", expectedRevision: 0, idempotencyKey: key()});
    await rejectsWith(
      w.run(specs.adminUpdateMaintenanceModeSpec, "owner-1", {enabled: true, expectedRevision: 0, idempotencyKey: key()}),
      "conflict",
    );
    assert.equal(pub(w).maintenance.enabled, false);
    assert.equal(pub(w).features.boost, false);
  });

  it("A7 a replayed request returns the first result and writes nothing twice", async () => {
    const w = await world();
    const idem = key("replay");
    const first = await w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "calls", enabled: false, reason: "provider outage", expectedRevision: 0, idempotencyKey: idem});
    const again = await w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "calls", enabled: false, reason: "provider outage", expectedRevision: 0, idempotencyKey: idem});
    assert.equal(again.replay, true);
    assert.equal(again.revision, first.revision);
    assert.equal(auditOf(w, "APP_FEATURE_SWITCH_CHANGED").length, 1);
    assert.equal(pub(w).revision, 1);
  });

  it("a change to the current value writes nothing and bumps nothing", async () => {
    const w = await world();
    const result = await w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "picks", enabled: true, reason: "noop", expectedRevision: 0, idempotencyKey: key()});
    assert.equal(result.changed, false);
    assert.equal(pub(w), undefined);
    assert.equal(auditOf(w, "APP_FEATURE_SWITCH_CHANGED").length, 0);
  });

  it("A9 minimum and recommended versions per platform, with store-only links", async () => {
    const w = await world();
    await w.run(specs.adminUpdateMinimumVersionSpec, "owner-1", {
      platform: "android", minimumVersion: "1.2.0", recommendedVersion: "1.3.0",
      updateUrl: "https://play.google.com/store/apps/details?id=com.mevora.app", expectedRevision: 0, idempotencyKey: key(),
    });
    assert.deepEqual(pub(w).minimumVersion, {android: "1.2.0", ios: null});
    assert.deepEqual(pub(w).recommendedVersion, {android: "1.3.0", ios: null});
    const [event] = auditOf(w, "APP_MIN_VERSION_CHANGED");
    assert.equal(event.metadata.platform, "android");
    assert.equal(event.metadata.previousValue.minimumVersion, null);
    assert.equal(event.metadata.newValue.minimumVersion, "1.2.0");

    const r = await rev(w);
    await rejectsWith(w.run(specs.adminUpdateMinimumVersionSpec, "owner-1", {platform: "ios", minimumVersion: "1.2", updateUrl: "https://evil.example.com/app", expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateMinimumVersionSpec, "owner-1", {platform: "ios", minimumVersion: "latest", expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateMinimumVersionSpec, "owner-1", {platform: "ios", minimumVersion: "2.0.0", recommendedVersion: "1.9.9", expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateMinimumVersionSpec, "owner-1", {platform: "windows", minimumVersion: "1.0.0", expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
  });

  it("A10 feature switches exist only for real features and default to enabled", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "everything", enabled: false, reason: "x", expectedRevision: 0, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateFeatureSwitchSpec, "owner-1", {feature: "boost", enabled: false, reason: "", expectedRevision: 0, idempotencyKey: key()}), "invalid_argument");
    const view = await w.run(specs.adminGetAppControlSpec, "owner-1");
    assert.deepEqual(view.config.features, {boost: true, calls: true, spotify: true, humorLab: true, picks: true});
  });

  it("A11 announcements are plain text, short-lived and versioned for dismissal", async () => {
    const w = await world();
    const now = w.now;
    const base = {enabled: true, title: "Bakım", message: "Bu gece 02:00'de kısa bir bakım var.", severity: "warning", expiresAt: new Date(now + DAY).toISOString(), idempotencyKey: key()};
    await w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, expectedRevision: 0});
    const a = pub(w).announcement;
    assert.equal(a.enabled, true);
    assert.equal(a.title, "Bakım");
    assert.equal(a.severity, "warning");
    assert.equal(a.expiresAt.toMillis(), now + DAY);
    assert.ok(/^[0-9a-f]{16}$/.test(a.id));
    const [event] = auditOf(w, "APP_ANNOUNCEMENT_CHANGED");
    assert.equal(event.metadata.newValue.titleChars, 5);
    assert.equal(JSON.stringify(event.metadata).includes("02:00"), false, "the text itself is not copied into the audit log");

    const r = await rev(w);
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, message: "<script>alert(1)</script>", expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, expiresAt: null, expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, expiresAt: new Date(now - 1000).toISOString(), expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, expiresAt: new Date(now + 60 * DAY).toISOString(), expectedRevision: r, idempotencyKey: key()}), "invalid_argument");
    await rejectsWith(w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, title: "x".repeat(81), expectedRevision: r, idempotencyKey: key()}), "invalid_argument");

    const changed = await w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {...base, message: "Yeni metin", expectedRevision: r, idempotencyKey: key()});
    assert.notEqual(pub(w).announcement.id, a.id, "new text, new id: a dismissed banner shows again");
    await w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {enabled: false, expectedRevision: changed.revision, idempotencyKey: key()});
    assert.equal(pub(w).announcement.enabled, false);
  });

  it("control characters are stripped from announcement text", async () => {
    const w = await world();
    await w.run(specs.adminUpdateAnnouncementSpec, "owner-1", {
      enabled: true, title: "Hi\u0000‮ there", message: "line one\r\nline two", expiresAt: new Date(w.now + DAY).toISOString(), expectedRevision: 0, idempotencyKey: key(),
    });
    assert.equal(pub(w).announcement.title, "Hi there");
    assert.equal(pub(w).announcement.message, "line one\nline two");
  });

  it("health reports real probes and the current revision", async () => {
    const w = await world();
    await w.run(specs.adminUpdateMaintenanceModeSpec, "owner-1", {enabled: true, expectedRevision: 0, idempotencyKey: key()});
    const view = await w.run(specs.adminGetAppControlSpec, "owner-1");
    assert.equal(view.health.firestore.ok, true);
    assert.equal(view.health.auth.ok, true);
    assert.equal(typeof view.health.storage.ok, "boolean");
    assert.ok(["emulator", "production"].includes(view.health.environment));
    assert.equal(view.config.revision, 1);
    assert.equal(view.config.updatedBy, "owner-1");
  });
});

describe("App Control enforcement in the backend", () => {
  function fakeDb(data) {
    const db = createFakeFirestore(data ? {"appOperationsConfig/public": data} : {});
    resetAppOperationsCache(db);
    return db;
  }

  it("no config at all means everything is available", async () => {
    const db = fakeDb(null);
    await assertAppFeatureAvailable(db, "boost");
    await assertAppFeatureAvailable(db, null);
  });

  it("A10 a switched-off feature is refused with feature_disabled", async () => {
    const db = fakeDb({features: {boost: false}});
    await assert.rejects(assertAppFeatureAvailable(db, "boost"), (e) => e.code === "unavailable" && e.message === "feature_disabled");
    await assertAppFeatureAvailable(db, "calls");
  });

  it("A8 maintenance refuses every guarded operation", async () => {
    const db = fakeDb({maintenance: {enabled: true}});
    await assert.rejects(assertAppFeatureAvailable(db, null), (e) => e.code === "unavailable" && e.message === "maintenance");
    await assert.rejects(assertAppFeatureAvailable(db, "picks"), (e) => e.message === "maintenance");
  });

  it("malformed config falls back to enabled", () => {
    const state = parseAppOperationsState({features: {boost: "no", calls: 0}, maintenance: "yes"});
    assert.equal(state.features.boost, true);
    assert.equal(state.features.calls, true);
    assert.equal(state.maintenance.enabled, false);
  });

  const src = (file) => fs.readFileSync(path.join(__dirname, "..", "src", file), "utf8");
  function body(file, name) {
    const text = src(file);
    const start = text.indexOf(`export const ${name} = `);
    assert.ok(start >= 0, `${name} not found in ${file}`);
    const next = text.indexOf("\nexport const ", start + 10);
    return text.slice(start, next < 0 ? undefined : next);
  }

  const GUARDED = [
    ["boost/verifyBoostPurchase.ts", "activateBoost", "\"boost\""],
    ["social.ts", "createVideoCall", "\"calls\""],
    ["social.ts", "recordSwipe", "null"],
    ["spotifyMusic.ts", "spotifyLinkMusic", "\"spotify\""],
    ["spotifyMusic.ts", "syncSpotifyTaste", "\"spotify\""],
    ["humor/index.ts", "getHumorFeed", "\"humorLab\""],
    ["humor/index.ts", "submitHumorFeedback", "\"humorLab\""],
    ["humor/index.ts", "getDailyHumorSet", "\"humorLab\""],
    ["humor/index.ts", "submitDailyHumorResponse", "\"humorLab\""],
    ["picks/index.ts", "getMevoraPicks", "\"picks\""],
    ["backend.ts", "getDiscoveryCandidates", "null"],
    ["backend.ts", "recordDiscoveryDecision", "null"],
  ];
  for (const [file, name, feature] of GUARDED) {
    it(`${name} is guarded server-side (${feature})`, () => {
      assert.ok(body(file, name).includes(`assertAppFeatureAvailable(db, ${feature})`), `${name} must call the gate`);
    });
  }

  const NEVER_GUARDED = [
    ["boost/verifyBoostPurchase.ts", "verifyBoostPurchase"],
    ["spotifyAuth.ts", "spotifyCompleteAuth"],
    ["backend.ts", "exportMyData"],
  ];
  for (const [file, name] of NEVER_GUARDED) {
    it(`${name} stays available during maintenance and kill switches`, () => {
      assert.equal(body(file, name).includes("assertAppFeatureAvailable"), false);
    });
  }

  it("safety and compliance modules never import the gate", () => {
    for (const file of ["deleteAccount.ts", "accountGuard.ts", "admin/appeals/consumerAppeals.ts"]) {
      assert.equal(src(file).includes("appOperationsGate"), false, file);
    }
  });
});
