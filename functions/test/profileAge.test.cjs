const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {bornYearsAgo, picked, utc} = require("./helpers/birthDates.cjs");
const {ageFromBirthDate, birthCalendarDate} = require("../lib/profileSafety.js");
const {
  accountBirthFields,
  memberBirthDate,
  moveProfileBirthDates,
  nextAgeChangeAt,
  rollOverProfileAges,
} = require("../lib/profileAge.js");

// No local-time constructors: `picked` is the instant the app stores (midnight
// of the chosen day on the member's own clock — Istanbul, UTC+3, unless an
// offset is given) and `utc` is a moment on the server's clock. The suite
// reads the same in any process time zone.
const ts = (date) => Timestamp.fromDate(date);

// Hours east of UTC: clocks from UTC-11 to UTC+12, half and quarter hours
// included.
const OFFSETS = [-11, -10, -9.5, -8, -5, -3.5, -3, -1, 0, 1, 2, 3, 3.5, 4.5, 5.5, 5.75, 8, 9.5, 10, 11, 12];
const zone = (offset) => `UTC${offset >= 0 ? "+" : ""}${offset}`;

describe("birthCalendarDate — the day the member picked", () => {
  it("an Istanbul member's 11 April is 11 April, though it is stored as 10 April 21:00 UTC", () => {
    const stored = picked(1996, 4, 11);
    assert.equal(stored.toISOString(), "1996-04-10T21:00:00.000Z");
    assert.deepEqual(birthCalendarDate(stored), utc(1996, 4, 11));
  });

  it("is the picked day on every clock from UTC-11 to UTC+12", () => {
    for (const offset of OFFSETS) {
      assert.deepEqual(birthCalendarDate(picked(1996, 4, 11, offset)), utc(1996, 4, 11), zone(offset));
    }
  });

  it("leaves a date already stored as UTC midnight where it is", () => {
    assert.deepEqual(birthCalendarDate(utc(1996, 4, 11)), utc(1996, 4, 11));
    assert.deepEqual(birthCalendarDate(birthCalendarDate(picked(1996, 4, 11))), utc(1996, 4, 11));
  });

  it("works before 1970 and across a month and a year", () => {
    assert.deepEqual(birthCalendarDate(picked(1960, 5, 20)), utc(1960, 5, 20));
    assert.deepEqual(birthCalendarDate(picked(1969, 12, 31, -8)), utc(1969, 12, 31));
    assert.deepEqual(birthCalendarDate(picked(1990, 1, 1)), utc(1990, 1, 1));
    assert.deepEqual(birthCalendarDate(picked(2000, 3, 1)), utc(2000, 3, 1));
  });

  it("midnight skipped by a clock change still lands on the picked day", () => {
    // Where the day starts at 01:00, the app stores that instead.
    assert.deepEqual(birthCalendarDate(utc(1996, 4, 10, 22)), utc(1996, 4, 11));
  });

  it("at exactly twelve hours the day goes to UTC+12, where people live", () => {
    assert.deepEqual(birthCalendarDate(picked(1996, 4, 11, 12)), utc(1996, 4, 11));
    // UTC-12 stores the same instant for the day before. Nobody lives there.
    assert.deepEqual(picked(1996, 4, 10, -12), picked(1996, 4, 11, 12));
  });

  it("known limit: beyond UTC+12 the day before is the nearer one", () => {
    for (const offset of [12.75, 13, 13.75, 14]) {
      assert.deepEqual(birthCalendarDate(picked(1996, 4, 11, offset)), utc(1996, 4, 10), zone(offset));
    }
  });
});

describe("age at a given moment", () => {
  it("counts a birthday from the start of the day it falls on", () => {
    const born = picked(1996, 4, 11);
    assert.equal(ageFromBirthDate(born, utc(2026, 4, 10, 23, 59)), 29);
    assert.equal(ageFromBirthDate(born, utc(2026, 4, 11)), 30);
    assert.equal(ageFromBirthDate(born, utc(2026, 12, 31)), 30);
  });

  it("an Istanbul member is not a year older the day before their birthday", () => {
    const born = picked(1996, 4, 11);
    assert.equal(ageFromBirthDate(born, utc(2026, 4, 10)), 29);
    assert.equal(ageFromBirthDate(born, utc(2026, 4, 10, 12)), 29);
    // Their own midnight: the server's day has not turned yet.
    assert.equal(ageFromBirthDate(born, utc(2026, 4, 10, 21)), 29);
  });

  it("is the same on every clock from UTC-11 to UTC+12", () => {
    for (const offset of OFFSETS) {
      const born = picked(1996, 4, 11, offset);
      assert.equal(ageFromBirthDate(born, utc(2026, 4, 10, 23, 59)), 29, zone(offset));
      assert.equal(ageFromBirthDate(born, utc(2026, 4, 11)), 30, zone(offset));
    }
  });

  it("reads the server's day in UTC, whatever zone the process is in", () => {
    const born = utc(2000, 6, 15);
    assert.equal(ageFromBirthDate(born, utc(2026, 6, 14, 23, 59)), 25);
    assert.equal(ageFromBirthDate(born, utc(2026, 6, 15)), 26);
  });

  it("still defaults to now", () => {
    assert.equal(ageFromBirthDate(bornYearsAgo(25)), 25);
    assert.equal(ageFromBirthDate(bornYearsAgo(25, 0, 3)), 25);
    assert.equal(ageFromBirthDate(bornYearsAgo(25, 1, 3)), 24);
  });
});

describe("nextAgeChangeAt", () => {
  it("is this year's birthday when it is still ahead", () => {
    assert.deepEqual(nextAgeChangeAt(picked(1996, 4, 11), utc(2026, 1, 20)), utc(2026, 4, 11));
  });

  it("is next year's once this year's has passed, including on the day itself", () => {
    assert.deepEqual(nextAgeChangeAt(picked(1996, 4, 11), utc(2026, 4, 11)), utc(2027, 4, 11));
    assert.deepEqual(nextAgeChangeAt(picked(1996, 4, 11), utc(2026, 10, 1)), utc(2027, 4, 11));
  });

  it("an Istanbul member born on 11 April rolls over on 11 April, not the 10th", () => {
    // Seen on the emulator on 2026-10-01: 2027-04-10T00:00:00Z.
    const next = nextAgeChangeAt(picked(1996, 4, 11), utc(2026, 10, 1, 20));
    assert.equal(next.toISOString(), "2027-04-11T00:00:00.000Z");
  });

  it("the day before the birthday, the birthday is still ahead", () => {
    assert.deepEqual(nextAgeChangeAt(picked(1996, 4, 11), utc(2026, 4, 10, 0, 10)), utc(2026, 4, 11));
  });

  it("is the same on every clock from UTC-11 to UTC+12", () => {
    for (const offset of OFFSETS) {
      assert.deepEqual(nextAgeChangeAt(picked(1996, 4, 11, offset), utc(2026, 10, 1)), utc(2027, 4, 11), zone(offset));
    }
  });

  it("is exactly the moment the age changes", () => {
    for (const day of [[1996, 4, 11], [2000, 2, 29], [1990, 12, 31], [1988, 1, 1]]) {
      for (const offset of [-8, 0, 3, 12]) {
        const born = picked(...day, offset);
        for (const now of [utc(2026, 10, 1), utc(2027, 2, 28, 12), utc(2028, 2, 29), utc(2028, 3, 1)]) {
          const next = nextAgeChangeAt(born, now);
          assert.ok(next > now);
          const justBefore = new Date(next.getTime() - 1);
          assert.equal(ageFromBirthDate(born, next), ageFromBirthDate(born, justBefore) + 1);
          assert.equal(ageFromBirthDate(born, justBefore), ageFromBirthDate(born, now));
        }
      }
    }
  });

  it("a 29 February birthday turns on 1 March in a common year", () => {
    // Stored as 28 February 21:00 UTC: the day is still the 29th.
    assert.deepEqual(nextAgeChangeAt(picked(2000, 2, 29), utc(2026, 10, 1)), utc(2027, 3, 1));
    assert.deepEqual(nextAgeChangeAt(picked(2000, 2, 29), utc(2027, 10, 1)), utc(2028, 2, 29));
  });

  it("a 1 March birthday stored on 29 February UTC stays on 1 March", () => {
    assert.equal(picked(1996, 3, 1).toISOString(), "1996-02-29T21:00:00.000Z");
    assert.deepEqual(nextAgeChangeAt(picked(1996, 3, 1), utc(2026, 10, 1)), utc(2027, 3, 1));
    assert.deepEqual(nextAgeChangeAt(picked(1996, 3, 1), utc(2027, 10, 1)), utc(2028, 3, 1));
  });
});

describe("memberBirthDate", () => {
  const onAccount = ts(picked(1996, 4, 11));
  const onProfile = ts(picked(1990, 1, 1));

  it("reads the private account", () => {
    assert.equal(memberBirthDate({birthDate: onAccount}, {}), onAccount);
  });

  it("falls back to a profile from before the move", () => {
    assert.equal(memberBirthDate({}, {birthDate: onProfile}), onProfile);
    assert.equal(memberBirthDate(undefined, {birthDate: onProfile}), onProfile);
  });

  it("the account wins when both exist", () => {
    assert.equal(memberBirthDate({birthDate: onAccount}, {birthDate: onProfile}), onAccount);
  });

  it("is null for anything that is not a timestamp", () => {
    assert.equal(memberBirthDate({birthDate: "1996-04-11"}, {birthDate: null}), null);
    assert.equal(memberBirthDate(undefined, undefined), null);
  });
});

describe("rollOverProfileAges", () => {
  // When the scheduled run fires.
  const now = utc(2026, 10, 1, 0, 10);

  function member(born, {age, rolloverAt, profile = {}} = {}) {
    return {
      account: {uid: "x", birthDate: ts(born), ...(rolloverAt ? {ageRolloverAt: ts(rolloverAt)} : {})},
      profile: {displayName: "Deniz", ...(age === undefined ? {} : {age}), ...profile},
    };
  }

  function seed(members) {
    const docs = {};
    for (const [uid, value] of Object.entries(members)) {
      docs[`users/${uid}`] = {...value.account, uid};
      if (value.profile) docs[`profiles/${uid}`] = {uid, ...value.profile};
    }
    const db = createFakeFirestore();
    db.reset(docs);
    return db;
  }

  it("moves the age of a member whose birthday has arrived, and schedules the next one", async () => {
    const db = seed({
      today: member(picked(1996, 10, 1), {age: 29, rolloverAt: utc(2026, 10, 1)}),
    });
    const result = await rollOverProfileAges(db, {now});
    assert.equal(db.read("profiles/today").age, 30);
    assert.deepEqual(db.read("users/today").ageRolloverAt.toDate(), utc(2027, 10, 1));
    assert.equal(result.updated, 1);
    // The date itself never reaches the member-readable document.
    assert.equal("birthDate" in db.read("profiles/today"), false);
  });

  it("catches up on birthdays missed while it was not running", async () => {
    const db = seed({
      missed: member(picked(1990, 9, 20), {age: 35, rolloverAt: utc(2026, 9, 20)}),
      longAgo: member(picked(1990, 3, 2), {age: 33, rolloverAt: utc(2024, 3, 2)}),
    });
    await rollOverProfileAges(db, {now});
    assert.equal(db.read("profiles/missed").age, 36);
    assert.equal(db.read("profiles/longAgo").age, 36);
    assert.deepEqual(db.read("users/longAgo").ageRolloverAt.toDate(), utc(2027, 3, 2));
  });

  it("leaves a member whose birthday is still ahead alone", async () => {
    const db = seed({
      later: member(picked(1996, 10, 2), {age: 29, rolloverAt: utc(2026, 10, 2)}),
    });
    const before = db.read("profiles/later");
    const result = await rollOverProfileAges(db, {now});
    assert.deepEqual(db.read("profiles/later"), before);
    assert.deepEqual(result, {due: 0, updated: 0, unchanged: 0, cleared: 0, failed: 0});
  });

  it("an Istanbul member's age moves on their birthday, not the day before", async () => {
    // Born 2 October in Istanbul: stored as 1 October 21:00 UTC.
    const db = seed({
      tomorrow: member(picked(1996, 10, 2), {age: 29, rolloverAt: utc(2026, 10, 2)}),
    });
    assert.equal((await rollOverProfileAges(db, {now})).due, 0);
    assert.equal(db.read("profiles/tomorrow").age, 29);

    const result = await rollOverProfileAges(db, {now: utc(2026, 10, 2, 0, 10)});
    assert.equal(result.updated, 1);
    assert.equal(db.read("profiles/tomorrow").age, 30);
    assert.deepEqual(db.read("users/tomorrow").ageRolloverAt.toDate(), utc(2027, 10, 2));
  });

  it("a marker written a day early by the old rule corrects itself without moving the age", async () => {
    // The old rule read the stored instant's UTC day: 1 October for this member.
    const db = seed({
      early: member(picked(1996, 10, 2), {age: 29, rolloverAt: utc(2026, 10, 1), profile: {updatedAt: ts(utc(2026, 1, 1))}}),
    });
    const first = await rollOverProfileAges(db, {now});
    assert.deepEqual(first, {due: 1, updated: 0, unchanged: 1, cleared: 0, failed: 0});
    assert.equal(db.read("profiles/early").age, 29);
    assert.deepEqual(db.read("profiles/early").updatedAt.toDate(), utc(2026, 1, 1));
    assert.deepEqual(db.read("users/early").ageRolloverAt.toDate(), utc(2026, 10, 2));

    const second = await rollOverProfileAges(db, {now: utc(2026, 10, 2, 0, 10)});
    assert.equal(second.updated, 1);
    assert.equal(db.read("profiles/early").age, 30);
    assert.deepEqual(db.read("users/early").ageRolloverAt.toDate(), utc(2027, 10, 2));
  });

  it("does not rewrite a profile whose age is already right", async () => {
    const db = seed({
      right: member(picked(1996, 10, 1), {age: 30, rolloverAt: utc(2026, 10, 1), profile: {updatedAt: ts(utc(2026, 1, 1))}}),
    });
    const result = await rollOverProfileAges(db, {now});
    assert.deepEqual(db.read("profiles/right").updatedAt.toDate(), utc(2026, 1, 1));
    assert.deepEqual(db.read("users/right").ageRolloverAt.toDate(), utc(2027, 10, 1));
    assert.equal(result.unchanged, 1);
  });

  it("never creates a profile for an account that has none", async () => {
    const db = seed({
      bare: {...member(picked(1996, 10, 1), {rolloverAt: utc(2026, 10, 1)}), profile: null},
    });
    await rollOverProfileAges(db, {now});
    assert.equal(db.has("profiles/bare"), false);
    assert.deepEqual(db.read("users/bare").ageRolloverAt.toDate(), utc(2027, 10, 1));
  });

  it("drops the marker from an account with no readable date of birth", async () => {
    const db = createFakeFirestore();
    db.reset({
      "users/odd": {uid: "odd", ageRolloverAt: ts(utc(2026, 9, 1))},
      "profiles/odd": {uid: "odd", age: 40},
    });
    const result = await rollOverProfileAges(db, {now});
    assert.equal("ageRolloverAt" in db.read("users/odd"), false);
    assert.equal(db.read("profiles/odd").age, 40);
    assert.equal(result.cleared, 1);
    // And it is not picked up again.
    assert.equal((await rollOverProfileAges(db, {now})).due, 0);
  });

  it("works through more members than one page holds", async () => {
    const members = {};
    for (let i = 0; i < 7; i++) {
      members[`m${i}`] = member(picked(1990 + i, 9, 1 + i), {age: 1, rolloverAt: utc(2026, 9, 1 + i)});
    }
    const db = seed(members);
    const result = await rollOverProfileAges(db, {now, pageSize: 3});
    assert.equal(result.due, 7);
    assert.equal(result.updated, 7);
    for (let i = 0; i < 7; i++) {
      assert.equal(db.read(`profiles/m${i}`).age, 36 - i);
    }
  });

  it("stops at its per-run ceiling and picks the rest up next time", async () => {
    const members = {};
    for (let i = 0; i < 5; i++) {
      members[`m${i}`] = member(picked(1990, 9, 1 + i), {age: 35, rolloverAt: utc(2026, 9, 1 + i)});
    }
    const db = seed(members);
    assert.equal((await rollOverProfileAges(db, {now, pageSize: 2, maxMembers: 4})).due, 4);
    assert.equal((await rollOverProfileAges(db, {now, pageSize: 2, maxMembers: 4})).due, 1);
  });
});

describe("moveProfileBirthDates — the backfill", () => {
  const now = utc(2026, 10, 1);
  const born = picked(1996, 4, 11);

  function legacy(extra = {}) {
    const db = createFakeFirestore();
    db.reset({
      "users/a": {uid: "a", accountStatus: "active"},
      "profiles/a": {uid: "a", displayName: "Ada", birthDate: ts(born), age: 27, updatedAt: ts(utc(2026, 1, 1))},
      ...extra,
    });
    return db;
  }

  it("a dry run reports and writes nothing", async () => {
    const db = legacy();
    const before = JSON.stringify([db.read("users/a"), db.read("profiles/a")]);
    const result = await moveProfileBirthDates(db, {now, confirm: false});
    assert.equal(result.examined, 1);
    assert.equal(result.moved, 1);
    assert.equal(result.written, 0);
    assert.equal(JSON.stringify([db.read("users/a"), db.read("profiles/a")]), before);
  });

  it("moves the date to the account and leaves a current age on the profile", async () => {
    const db = legacy();
    const result = await moveProfileBirthDates(db, {now, confirm: true});
    assert.equal(result.written, 1);
    const profile = db.read("profiles/a");
    assert.equal("birthDate" in profile, false);
    assert.equal(profile.age, 30);
    assert.equal(profile.displayName, "Ada");
    // Not an edit by the member: the profile's own timestamp is left alone.
    assert.deepEqual(profile.updatedAt.toDate(), utc(2026, 1, 1));
    const account = db.read("users/a");
    assert.deepEqual(account.birthDate.toDate(), born);
    assert.deepEqual(account.ageRolloverAt.toDate(), utc(2027, 4, 11));
    assert.equal(account.accountStatus, "active");
  });

  it("run the day before an Istanbul member's birthday, it does not age them early", async () => {
    const db = legacy();
    await moveProfileBirthDates(db, {now: utc(2026, 4, 10, 9), confirm: true});
    assert.equal(db.read("profiles/a").age, 29);
    assert.deepEqual(db.read("users/a").ageRolloverAt.toDate(), utc(2026, 4, 11));
    // The stored date is moved as it is, not rewritten.
    assert.equal(db.read("users/a").birthDate.toDate().toISOString(), "1996-04-10T21:00:00.000Z");
  });

  it("keeps a date the account already holds", async () => {
    const onAccount = picked(1994, 2, 3);
    const db = legacy({"users/a": {uid: "a", birthDate: ts(onAccount)}});
    const result = await moveProfileBirthDates(db, {now, confirm: true});
    assert.equal(result.alreadyOnAccount, 1);
    assert.deepEqual(db.read("users/a").birthDate.toDate(), onAccount);
    assert.equal(db.read("profiles/a").age, 32);
    assert.equal("birthDate" in db.read("profiles/a"), false);
  });

  it("leaves a profile without an account alone, unless told to strip it", async () => {
    const db = createFakeFirestore();
    db.reset({"profiles/ghost": {uid: "ghost", birthDate: ts(born), age: 27}});
    const kept = await moveProfileBirthDates(db, {now, confirm: true});
    assert.deepEqual(kept.orphans, ["ghost"]);
    assert.equal(kept.written, 0);
    assert.equal(db.has("users/ghost"), false);
    assert.deepEqual(db.read("profiles/ghost").birthDate.toDate(), born);

    const stripped = await moveProfileBirthDates(db, {now, confirm: true, stripOrphans: true});
    assert.equal(stripped.written, 1);
    assert.equal(db.has("users/ghost"), false);
    assert.equal("birthDate" in db.read("profiles/ghost"), false);
    assert.equal(db.read("profiles/ghost").age, 30);
  });

  it("ignores profiles that hold no date", async () => {
    const db = createFakeFirestore();
    db.reset({
      "users/n": {uid: "n"},
      "profiles/n": {uid: "n", birthDate: null, age: 31},
      "users/m": {uid: "m"},
      "profiles/m": {uid: "m", age: 22},
    });
    const result = await moveProfileBirthDates(db, {now, confirm: true});
    assert.equal(result.examined, 0);
    assert.equal(db.read("profiles/n").age, 31);
  });

  it("a second run finds nothing left to do", async () => {
    const db = legacy({
      "users/b": {uid: "b"},
      "profiles/b": {uid: "b", birthDate: ts(picked(1999, 12, 31))},
    });
    assert.equal((await moveProfileBirthDates(db, {now, confirm: true, pageSize: 1})).written, 2);
    const again = await moveProfileBirthDates(db, {now, confirm: true});
    assert.equal(again.examined, 0);
    assert.equal(db.read("profiles/b").age, 26);
  });

  it("honours a limit", async () => {
    const db = legacy({
      "users/b": {uid: "b"},
      "profiles/b": {uid: "b", birthDate: ts(picked(1999, 12, 31))},
    });
    const result = await moveProfileBirthDates(db, {now, confirm: true, limit: 1});
    assert.equal(result.written, 1);
  });
});

describe("accountBirthFields", () => {
  it("is the date plus the moment its age next changes", () => {
    const birthDate = ts(picked(1996, 4, 11));
    const fields = accountBirthFields(birthDate, utc(2026, 10, 1));
    assert.equal(fields.birthDate, birthDate);
    assert.deepEqual(fields.ageRolloverAt.toDate(), utc(2027, 4, 11));
  });
});
