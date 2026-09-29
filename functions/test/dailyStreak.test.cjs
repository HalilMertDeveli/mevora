const {beforeEach, describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs, callAs} = require("./helpers/adminStubs.cjs");

const db = createFakeFirestore();
const {auth} = installFirebaseAdminStubs({db});

const {
  dayKeyFor,
  daysBetween,
  isDayKey,
  normalizeOffsetMinutes,
  MAX_OFFSET_MINUTES,
  MIN_OFFSET_MINUTES,
} = require("../lib/streak/day.js");
const {applyCheckIn, parseCounters, STREAK_MILESTONES} = require("../lib/streak/rules.js");
const {dailyStreakDocPath, recordCheckIn, streakExportView} = require("../lib/streak/service.js");
const {recordDailyCheckIn} = require("../lib/streak/index.js");
const {deleteUserAccount} = require("../lib/deleteAccount.js");
const {verifyAccountDeletion} = require("../lib/automation/deletionVerify.js");

const UID = "member-a";
const OTHER = "member-b";
const TRT = 180; // Europe/Istanbul, UTC+3
const PATH = dailyStreakDocPath(UID);

/** 2026-09-29 12:00 UTC — 15:00 in Istanbul. */
const NOON = Date.UTC(2026, 8, 29, 12, 0, 0);
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

function member(extra = {}) {
  return {uid: UID, onboardingCompleted: true, profileCompleted: true, ...extra};
}

function seed(extra = {}) {
  db.reset({
    [`users/${UID}`]: member(),
    [`profiles/${UID}`]: {uid: UID, onboardingCompleted: true},
    [`users/${OTHER}`]: {uid: OTHER, onboardingCompleted: true},
    ...extra,
  });
}

function streakDoc(fields) {
  return {[PATH]: {schemaVersion: 1, lastTimezoneOffsetMinutes: TRT, ...fields}};
}

const checkIn = (nowMs, offset = TRT, uid = UID) =>
  recordCheckIn(db, {uid, timezoneOffsetMinutes: offset, nowMs});

beforeEach(() => seed());

// ---------------------------------------------------------------------------
// Pure day arithmetic
// ---------------------------------------------------------------------------

describe("calendar day arithmetic", () => {
  it("puts the day boundary at local midnight for each offset", () => {
    // 2026-09-29 21:30 UTC
    const t = Date.UTC(2026, 8, 29, 21, 30);
    assert.equal(dayKeyFor(t, 0), "2026-09-29");
    assert.equal(dayKeyFor(t, TRT), "2026-09-30"); // 00:30 in Istanbul
    assert.equal(dayKeyFor(t, -300), "2026-09-29"); // 16:30 in New York (UTC-5)
    assert.equal(dayKeyFor(Date.UTC(2026, 8, 29, 3, 0), -300), "2026-09-28"); // 22:00 the day before
  });

  it("counts whole days across month and year boundaries", () => {
    assert.equal(daysBetween("2026-09-30", "2026-10-01"), 1);
    assert.equal(daysBetween("2026-12-31", "2027-01-01"), 1);
    assert.equal(daysBetween("2028-02-28", "2028-03-01"), 2); // leap year
    assert.equal(daysBetween("2026-09-29", "2026-09-29"), 0);
    assert.equal(daysBetween("2026-09-29", "2026-09-28"), -1);
  });

  it("accepts only real calendar dates as day keys", () => {
    assert.equal(isDayKey("2026-09-29"), true);
    for (const bad of ["2026-9-29", "2026-02-30", "2037-13-01", "", null, 20260929, "2026-09-29T00:00"]) {
      assert.equal(isDayKey(bad), false, `accepted ${String(bad)}`);
    }
  });

  it("clamps offsets to real time zones and rejects non-numbers", () => {
    assert.equal(normalizeOffsetMinutes(180), 180);
    assert.equal(normalizeOffsetMinutes(-330.4), -330);
    assert.equal(normalizeOffsetMinutes(99999), MAX_OFFSET_MINUTES);
    assert.equal(normalizeOffsetMinutes(-99999), MIN_OFFSET_MINUTES);
    for (const bad of [undefined, null, "180", NaN, Infinity, {}]) {
      assert.equal(normalizeOffsetMinutes(bad), null);
    }
  });
});

// ---------------------------------------------------------------------------
// Pure transition rules
// ---------------------------------------------------------------------------

describe("streak transition rules", () => {
  const none = parseCounters(undefined);

  it("starts at one from nothing", () => {
    const t = applyCheckIn(none, "2026-09-29");
    assert.equal(t.status, "started");
    assert.equal(t.credited, true);
    assert.deepEqual(t.next, {currentStreak: 1, longestStreak: 1, totalCheckInDays: 1, lastCheckInDay: "2026-09-29"});
    assert.equal(t.newPersonalBest, false);
  });

  it("keeps the longest streak when a lapsed member starts again", () => {
    const t = applyCheckIn(
      {currentStreak: 0, longestStreak: 12, totalCheckInDays: 40, lastCheckInDay: null},
      "2026-09-29",
    );
    assert.equal(t.next.longestStreak, 12);
    assert.equal(t.next.totalCheckInDays, 41);
  });

  it("does nothing on the same day", () => {
    const prev = {currentStreak: 1, longestStreak: 1, totalCheckInDays: 1, lastCheckInDay: "2026-09-29"};
    const t = applyCheckIn(prev, "2026-09-29");
    assert.equal(t.status, "alreadyCounted");
    assert.equal(t.credited, false);
    assert.deepEqual(t.next, prev);
  });

  it("never moves the stored day backwards", () => {
    const prev = {currentStreak: 4, longestStreak: 4, totalCheckInDays: 4, lastCheckInDay: "2026-09-30"};
    const t = applyCheckIn(prev, "2026-09-29");
    assert.equal(t.status, "alreadyCounted");
    assert.deepEqual(t.next, prev);
  });

  it("continues on the next day", () => {
    const t = applyCheckIn({currentStreak: 5, longestStreak: 5, totalCheckInDays: 9, lastCheckInDay: "2026-09-28"}, "2026-09-29");
    assert.equal(t.status, "continued");
    assert.equal(t.next.currentStreak, 6);
    assert.equal(t.next.totalCheckInDays, 10);
  });

  it("resets to one after a missed day", () => {
    const t = applyCheckIn({currentStreak: 5, longestStreak: 5, totalCheckInDays: 9, lastCheckInDay: "2026-09-27"}, "2026-09-29");
    assert.equal(t.status, "reset");
    assert.equal(t.next.currentStreak, 1);
    assert.equal(t.next.longestStreak, 5);
    assert.equal(t.next.totalCheckInDays, 10);
    assert.equal(t.newPersonalBest, false);
  });

  it("leaves a longer record alone and raises a matched one", () => {
    const below = applyCheckIn({currentStreak: 9, longestStreak: 12, totalCheckInDays: 30, lastCheckInDay: "2026-09-28"}, "2026-09-29");
    assert.equal(below.next.currentStreak, 10);
    assert.equal(below.next.longestStreak, 12);
    assert.equal(below.newPersonalBest, false);

    const at = applyCheckIn({currentStreak: 12, longestStreak: 12, totalCheckInDays: 30, lastCheckInDay: "2026-09-28"}, "2026-09-29");
    assert.equal(at.next.currentStreak, 13);
    assert.equal(at.next.longestStreak, 13);
    assert.equal(at.newPersonalBest, true);
  });

  it("flags milestone lengths only", () => {
    for (const n of STREAK_MILESTONES) {
      const t = applyCheckIn({currentStreak: n - 1, longestStreak: 100, totalCheckInDays: 200, lastCheckInDay: "2026-09-28"}, "2026-09-29");
      assert.equal(t.milestone, true, `day ${n}`);
    }
    const t = applyCheckIn({currentStreak: 4, longestStreak: 4, totalCheckInDays: 4, lastCheckInDay: "2026-09-28"}, "2026-09-29");
    assert.equal(t.milestone, false);
  });

  it("reads corrupt stored fields as zero instead of propagating them", () => {
    const c = parseCounters({currentStreak: "lots", longestStreak: -3, totalCheckInDays: NaN, lastCheckInDay: "yesterday"});
    assert.deepEqual(c, {currentStreak: 0, longestStreak: 0, totalCheckInDays: 0, lastCheckInDay: null});
  });
});

// ---------------------------------------------------------------------------
// The transactional service against the in-memory Firestore
// ---------------------------------------------------------------------------

describe("recording a check-in", () => {
  it("creates the first streak day", async () => {
    const r = await checkIn(NOON);
    assert.equal(r.status, "started");
    assert.equal(r.credited, true);
    assert.equal(r.currentStreak, 1);
    assert.equal(r.longestStreak, 1);
    assert.equal(r.totalCheckInDays, 1);
    assert.equal(r.dayKey, "2026-09-29");
    assert.equal(r.schemaVersion, 1);
    const doc = db.read(PATH);
    assert.equal(doc.currentStreak, 1);
    assert.equal(doc.lastCheckInDay, "2026-09-29");
    assert.equal(doc.lastTimezoneOffsetMinutes, TRT);
    assert.ok(doc.lastCheckInAt && doc.createdAt && doc.updatedAt);
  });

  it("stores nothing personal beyond counters, the day and the offset", async () => {
    await checkIn(NOON);
    assert.deepEqual(Object.keys(db.read(PATH)).sort(), [
      "createdAt", "currentStreak", "lastCheckInAt", "lastCheckInDay",
      "lastTimezoneOffsetMinutes", "longestStreak", "schemaVersion", "totalCheckInDays", "updatedAt",
    ]);
  });

  it("is idempotent within a day and writes nothing on repeat", async () => {
    await checkIn(NOON);
    const first = db.read(PATH);
    for (const later of [NOON + 1000, NOON + 2 * HOUR, NOON + 8 * HOUR]) {
      const r = await checkIn(later);
      assert.equal(r.status, "alreadyCounted");
      assert.equal(r.credited, false);
      assert.equal(r.currentStreak, 1);
      assert.equal(r.totalCheckInDays, 1);
    }
    // Not even updatedAt moved: a same-day open costs reads only.
    assert.deepEqual(db.read(PATH), first);
  });

  it("continues on the next local day", async () => {
    seed(streakDoc({currentStreak: 5, longestStreak: 7, totalCheckInDays: 20, lastCheckInDay: "2026-09-28"}));
    const r = await checkIn(NOON);
    assert.equal(r.status, "continued");
    assert.equal(r.currentStreak, 6);
    assert.equal(r.longestStreak, 7);
    assert.equal(r.totalCheckInDays, 21);
  });

  it("resets after a gap and keeps the historical longest", async () => {
    seed(streakDoc({currentStreak: 5, longestStreak: 5, totalCheckInDays: 20, lastCheckInDay: "2026-09-26"}));
    const r = await checkIn(NOON);
    assert.equal(r.status, "reset");
    assert.equal(r.currentStreak, 1);
    assert.equal(r.longestStreak, 5);
    assert.equal(r.totalCheckInDays, 21);
    assert.equal(db.read(PATH).longestStreak, 5);
  });

  it("reports a new personal best only when the record is beaten", async () => {
    seed(streakDoc({currentStreak: 6, longestStreak: 6, totalCheckInDays: 6, lastCheckInDay: "2026-09-28"}));
    const r = await checkIn(NOON);
    assert.equal(r.currentStreak, 7);
    assert.equal(r.longestStreak, 7);
    assert.equal(r.newPersonalBest, true);
    assert.equal(r.milestone, true);
  });

  it("counts every credited day exactly once across a week of visits", async () => {
    let total = 0;
    for (let d = 0; d < 7; d++) {
      // 15:00, 18:00 and 23:00 in Istanbul — three opens, one local day.
      for (const h of [0, 3, 8]) {
        const r = await checkIn(NOON + d * DAY + h * HOUR);
        if (r.credited) total += 1;
      }
    }
    assert.equal(total, 7);
    assert.equal(db.read(PATH).totalCheckInDays, 7);
    assert.equal(db.read(PATH).currentStreak, 7);
  });

  it("keeps the created-at timestamp across days", async () => {
    await checkIn(NOON);
    const createdAt = db.read(PATH).createdAt;
    await checkIn(NOON + DAY);
    assert.deepEqual(db.read(PATH).createdAt, createdAt);
  });

  it("ignores any day, streak or uid the client tries to send", async () => {
    seed(streakDoc({currentStreak: 2, longestStreak: 2, totalCheckInDays: 2, lastCheckInDay: "2026-09-28"}));
    const r = await callAs(recordDailyCheckIn, UID, {
      timezoneOffsetMinutes: TRT,
      dayKey: "2037-05-18",
      currentStreak: 999,
      longestStreak: 999,
      uid: OTHER,
      nowMs: Date.UTC(2037, 4, 18),
    });
    assert.ok(r.currentStreak <= 3, `client-supplied counters leaked: ${r.currentStreak}`);
    assert.notEqual(r.dayKey, "2037-05-18");
    assert.equal(db.has(dailyStreakDocPath(OTHER)), false);
  });
});

describe("time zones", () => {
  it("counts two visits either side of Istanbul midnight as two days", async () => {
    // 20:50 UTC = 23:50 TRT, then 21:10 UTC = 00:10 TRT next day.
    const before = Date.UTC(2026, 8, 29, 20, 50);
    const after = Date.UTC(2026, 8, 29, 21, 10);
    assert.equal((await checkIn(before)).status, "started");
    const r = await checkIn(after);
    assert.equal(r.status, "continued");
    assert.equal(r.dayKey, "2026-09-30");
  });

  it("treats the same two instants as one day in UTC", async () => {
    await checkIn(Date.UTC(2026, 8, 29, 20, 50), 0);
    const r = await checkIn(Date.UTC(2026, 8, 29, 21, 10), 0);
    assert.equal(r.status, "alreadyCounted");
  });

  it("uses local days for a negative offset", async () => {
    const NY = -240; // New York in summer, UTC-4
    // 02:00 UTC on the 30th is 22:00 on the 29th in New York.
    assert.equal((await checkIn(Date.UTC(2026, 8, 30, 2, 0), NY)).dayKey, "2026-09-29");
    // 05:00 UTC on the 30th is 01:00 on the 30th.
    const r = await checkIn(Date.UTC(2026, 8, 30, 5, 0), NY);
    assert.equal(r.status, "continued");
    assert.equal(r.dayKey, "2026-09-30");
  });

  it("does not double count when the offset changes within a day", async () => {
    await checkIn(NOON, TRT);
    const r = await checkIn(NOON + HOUR, 0);
    assert.equal(r.status, "alreadyCounted");
    assert.equal(db.read(PATH).totalCheckInDays, 1);
  });

  it("does not move the streak back when travelling west across midnight", async () => {
    // 22:30 UTC: already the 30th in Istanbul, still the 29th in UTC.
    const t = Date.UTC(2026, 8, 29, 22, 30);
    await checkIn(t, TRT);
    const r = await checkIn(t + 10 * 60 * 1000, 0);
    assert.equal(r.status, "alreadyCounted");
    assert.equal(r.dayKey, "2026-09-30");
    assert.equal(db.read(PATH).lastCheckInDay, "2026-09-30");
  });

  it("falls back to the last known offset when the client sends none", async () => {
    await checkIn(Date.UTC(2026, 8, 29, 20, 50), TRT);
    const r = await recordCheckIn(db, {uid: UID, timezoneOffsetMinutes: "garbage", nowMs: Date.UTC(2026, 8, 29, 21, 10)});
    assert.equal(r.status, "continued"); // still reckoned in TRT
  });

  it("clamps an absurd offset rather than trusting it", async () => {
    const r = await checkIn(NOON, 100000);
    assert.equal(r.dayKey, dayKeyFor(NOON, MAX_OFFSET_MINUTES));
    assert.equal(db.read(PATH).lastTimezoneOffsetMinutes, MAX_OFFSET_MINUTES);
  });
});

describe("eligibility", () => {
  it("rejects an unauthenticated caller", async () => {
    await assert.rejects(() => callAs(recordDailyCheckIn, null, {timezoneOffsetMinutes: TRT}), (e) => e.code === "unauthenticated");
    assert.equal(db.has(PATH), false);
  });

  for (const [label, account] of [
    ["suspended", member({isSuspended: true})],
    ["banned", member({isBanned: true})],
    ["status suspended", member({accountStatus: "suspended"})],
    ["status deleted", member({accountStatus: "deleted"})],
  ]) {
    it(`gives a ${label} account no credit`, async () => {
      seed({[`users/${UID}`]: account});
      const r = await checkIn(NOON);
      assert.equal(r.status, "ineligible");
      assert.equal(r.credited, false);
      assert.equal(r.currentStreak, 0);
      assert.equal(db.has(PATH), false);
    });
  }

  it("does not return a suspended member's existing streak", async () => {
    seed({
      [`users/${UID}`]: member({isSuspended: true}),
      ...streakDoc({currentStreak: 5, longestStreak: 5, totalCheckInDays: 5, lastCheckInDay: "2026-09-28"}),
    });
    const r = await checkIn(NOON);
    assert.equal(r.status, "ineligible");
    assert.equal(r.currentStreak, 0);
    assert.equal(db.read(PATH).currentStreak, 5); // untouched, not reset
  });

  it("gives a deleted account (no account document) no credit", async () => {
    db.reset({[`profiles/${UID}`]: {onboardingCompleted: true}});
    const r = await checkIn(NOON);
    assert.equal(r.status, "ineligible");
    assert.equal(db.has(PATH), false);
  });

  it("gives an account mid-onboarding no credit", async () => {
    seed({
      [`users/${UID}`]: {uid: UID, onboardingCompleted: false, profileCompleted: false},
      [`profiles/${UID}`]: {uid: UID, onboardingStep: "photos"},
    });
    const r = await checkIn(NOON);
    assert.equal(r.status, "ineligible");
    assert.equal(db.has(PATH), false);
  });

  it("accepts onboarding recorded on the profile only, as the app's router does", async () => {
    seed({
      [`users/${UID}`]: {uid: UID},
      [`profiles/${UID}`]: {uid: UID, profileCompleted: true},
    });
    const r = await checkIn(NOON);
    assert.equal(r.status, "started");
  });

  it("keeps each member's streak to themselves", async () => {
    await checkIn(NOON, TRT, UID);
    await checkIn(NOON + DAY, TRT, UID);
    const b = await checkIn(NOON + DAY, TRT, OTHER);
    assert.equal(b.status, "started");
    assert.equal(b.currentStreak, 1);
    assert.equal(db.read(PATH).currentStreak, 2);
    assert.equal(db.read(dailyStreakDocPath(OTHER)).currentStreak, 1);
  });
});

// ---------------------------------------------------------------------------
// Concurrency: the fake's transactions do not conflict on their own, so this
// wraps them with Firestore's optimistic rule — a transaction whose reads
// changed before commit is retried.
// ---------------------------------------------------------------------------

function withOptimisticTransactions(base) {
  const stats = {retries: 0};
  const read = (path) => JSON.stringify(base.read(path) ?? null);
  const wrapped = Object.create(base);
  wrapped.runTransaction = async (fn) => {
    for (let attempt = 0; attempt < 10; attempt++) {
      const seen = new Map();
      const writes = [];
      const tx = {
        async get(ref) {
          const snap = await ref.get();
          seen.set(ref.path, read(ref.path));
          return snap;
        },
        async getAll(...refs) {
          return Promise.all(refs.map((ref) => tx.get(ref)));
        },
        set(ref, data, options) {
          writes.push(() => ref.set(data, options));
          return tx;
        },
      };
      const result = await fn(tx);
      // Validate-and-commit in one synchronous step, as the backend would.
      const stale = [...seen].some(([path, value]) => read(path) !== value);
      if (stale) {
        stats.retries += 1;
        continue;
      }
      for (const write of writes) write();
      return result;
    }
    throw new Error("transaction retries exhausted");
  };
  return {db: wrapped, stats};
}

describe("concurrency", () => {
  it("credits one day when two calls race on a new day", async () => {
    seed(streakDoc({currentStreak: 5, longestStreak: 5, totalCheckInDays: 5, lastCheckInDay: "2026-09-28"}));
    const {db: racing, stats} = withOptimisticTransactions(db);
    const results = await Promise.all(
      Array.from({length: 2}, () => recordCheckIn(racing, {uid: UID, timezoneOffsetMinutes: TRT, nowMs: NOON})),
    );
    assert.equal(db.read(PATH).currentStreak, 6);
    assert.equal(db.read(PATH).totalCheckInDays, 6);
    assert.equal(results.filter((r) => r.credited).length, 1);
    assert.deepEqual(results.map((r) => r.status).sort(), ["alreadyCounted", "continued"]);
    assert.ok(stats.retries >= 1, "the race was not exercised");
  });

  it("converges under a burst of parallel startup calls", async () => {
    const {db: racing} = withOptimisticTransactions(db);
    const results = await Promise.all(
      Array.from({length: 8}, (_, i) => recordCheckIn(racing, {uid: UID, timezoneOffsetMinutes: TRT, nowMs: NOON + i})),
    );
    assert.equal(results.filter((r) => r.credited).length, 1);
    assert.ok(results.every((r) => r.currentStreak === 1));
    assert.equal(db.read(PATH).totalCheckInDays, 1);
  });

  it("does not add a day when a completed call is replayed", async () => {
    // A retried delivery of the same request, after the first one committed.
    seed(streakDoc({currentStreak: 5, longestStreak: 5, totalCheckInDays: 5, lastCheckInDay: "2026-09-28"}));
    await checkIn(NOON);
    const replay = await checkIn(NOON);
    assert.equal(replay.status, "alreadyCounted");
    assert.equal(db.read(PATH).currentStreak, 6);
  });

  it("lands on the same state even if two stale transactions both commit", async () => {
    // Belt and braces: the write is absolute, never an increment, so even a
    // store without transaction conflicts cannot turn 5 into 7.
    seed(streakDoc({currentStreak: 5, longestStreak: 5, totalCheckInDays: 5, lastCheckInDay: "2026-09-28"}));
    await Promise.all([checkIn(NOON), checkIn(NOON)]);
    assert.equal(db.read(PATH).currentStreak, 6);
    assert.equal(db.read(PATH).totalCheckInDays, 6);
  });
});

// ---------------------------------------------------------------------------
// Privacy: deletion, verification, export
// ---------------------------------------------------------------------------

describe("account deletion and export", () => {
  beforeEach(() => {
    auth.users.clear();
    auth.addUser(UID);
    auth.addUser(OTHER);
  });

  it("deletes the streak with the account and verification confirms it", async () => {
    await checkIn(NOON);
    await checkIn(NOON, TRT, OTHER);
    assert.equal(db.has(PATH), true);

    const result = await callAs(deleteUserAccount, UID);
    assert.equal(result.ok, true);
    assert.equal(db.has(PATH), false);
    assert.equal(db.has(dailyStreakDocPath(OTHER)), true);

    const verified = await verifyAccountDeletion(UID, db);
    assert.equal(verified.issues.some((i) => i.includes("dailyStreak")), false, verified.issues.join(","));
  });

  it("cannot recreate a streak after the account is deleted", async () => {
    await callAs(deleteUserAccount, UID);
    const r = await checkIn(NOON + DAY);
    assert.equal(r.status, "ineligible");
    assert.equal(db.has(PATH), false);
  });

  it("verification reports a streak that survived deletion", async () => {
    db.reset(streakDoc({currentStreak: 3, longestStreak: 3, totalCheckInDays: 3, lastCheckInDay: "2026-09-29"}));
    auth.users.clear();
    const verified = await verifyAccountDeletion(UID, db);
    assert.equal(verified.complete, false);
    assert.ok(verified.issues.includes(`firestore_remnant:${PATH}`), verified.issues.join(","));
  });

  it("exports counters and the day only", () => {
    const view = streakExportView({
      currentStreak: 4, longestStreak: 9, totalCheckInDays: 30, lastCheckInDay: "2026-09-29",
      lastTimezoneOffsetMinutes: TRT, lastCheckInAt: {seconds: 1}, createdAt: {seconds: 0},
    });
    assert.deepEqual(view, {currentStreak: 4, longestStreak: 9, totalCheckInDays: 30, lastCheckInDay: "2026-09-29"});
    assert.equal(streakExportView(undefined), null);
  });
});
