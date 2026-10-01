const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createAdminWorld, rejectsWith} = require("./helpers/adminHarness.cjs");
const specs = require("../lib/admin/commands.js");
const {seedCalibrationCatalog} = require("../lib/humor/calibrationCatalog.js");
const {HUMOR_CORE_SEQUENCE} = require("../lib/humor/coreSequence.js");

async function world() {
  const w = createAdminWorld();
  await w.addStaff("mod-1", "moderator");
  await w.addStaff("support-1", "support_agent");
  await seedCalibrationCatalog(w.db);
  return w;
}

describe("admin Humor Core sequence — read-only", () => {
  it("lists every position with its status, measurement and source", async () => {
    const w = await world();
    const result = await w.run(specs.adminListHumorCoreSequenceSpec, "mod-1", {});

    assert.equal(result.total, HUMOR_CORE_SEQUENCE.length);
    assert.equal(result.items.length, HUMOR_CORE_SEQUENCE.length);
    assert.deepEqual([result.onboardingCount, result.dailyCount], [15, 5]);
    assert.equal(result.released, false);
    assert.equal(result.healthy, true);
    assert.deepEqual(
      result.items.map((item) => item.position),
      HUMOR_CORE_SEQUENCE.map((_, index) => index + 1),
    );
    assert.deepEqual(
      result.items.map((item) => item.contentId),
      HUMOR_CORE_SEQUENCE.map((entry) => entry.id),
    );

    const first = result.items[0];
    assert.deepEqual(
      {
        position: first.position,
        onboarding: first.onboarding,
        coreStatus: first.coreStatus,
        servable: first.servable,
        contentActive: first.contentActive,
        safetyStatus: first.safetyStatus,
        category: first.category,
        provider: first.provider,
        sourceTrust: first.sourceTrust,
      },
      {
        position: 1,
        onboarding: true,
        coreStatus: "active",
        servable: true,
        contentActive: true,
        safetyStatus: "approved",
        category: "sarcasm",
        provider: "giphy",
        sourceTrust: "curated",
      },
    );
    assert.ok(first.vectorSummary[0].startsWith("sarcasm "));
    assert.match(first.previewUrl, /^https:\/\//);
    assert.equal(result.items[15].onboarding, false);
  });

  it("shows an entry whose content was taken down as not servable", async () => {
    const w = await world();
    const id = HUMOR_CORE_SEQUENCE[4].id;
    await w.db.doc(`humorContent/${id}`).set({safetyStatus: "rejected"}, {merge: true});

    const result = await w.run(specs.adminListHumorCoreSequenceSpec, "mod-1", {});

    assert.equal(result.healthy, false);
    assert.equal(result.items[4].servable, false);
    assert.equal(result.items[4].coreStatus, "active");
    assert.deepEqual(result.warnings, [`V5 ${id}: content rejected`]);
  });

  it("changes nothing: reading the sequence writes no document", async () => {
    const w = await world();
    const before = JSON.stringify([...w.db._store.entries()]);
    await w.run(specs.adminListHumorCoreSequenceSpec, "mod-1", {});
    const after = [...w.db._store.entries()].filter(([key]) => key.startsWith("humor"));
    assert.equal(JSON.stringify(after), JSON.stringify(JSON.parse(before).filter(([key]) => key.startsWith("humor"))));
  });

  it("needs humor.read: support agents cannot see it", async () => {
    const w = await world();
    await rejectsWith(w.run(specs.adminListHumorCoreSequenceSpec, "support-1", {}), "permission_denied");
  });
});
