const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {bornYearsAgo} = require("./helpers/birthDates.cjs");
const {ageFromBirthDate} = require("../lib/profileSafety.js");
const {
  accountBirthFields,
  memberBirthDate,
  moveProfileBirthDates,
  nextAgeChangeAt,
  rollOverProfileAges,
} = require("../lib/profileAge.js");

// Local-time constructors throughout: the age rule reads calendar fields in
// the process time zone, so the suite is the same in any zone.
const day = (y, m, d, h = 0) => new Date(y, m - 1, d, h);
const ts = (date) => Timestamp.fromDate(date);

describe("age at a given moment", () => {
  it("counts a birthday from the start of the day it falls on", () => {
    const born = day(1996, 4, 11);
    assert.equal(ageFromBirthDate(born, day(2026, 4, 10, 23)), 29);
    assert.equal(ageFromBirthDate(born, day(2026, 4, 11)), 30);
    assert.equal(ageFromBirthDate(born, day(2026, 12, 31)), 30);
  });

  it("still defaults to now", () => {
    assert.equal(ageFromBirthDate(bornYearsAgo(25)), 25);
  });
});

describe("nextAgeChangeAt", () => {
  it("is this year's birthday when it is still ahead", () => {
    assert.deepEqual(nextAgeChangeAt(day(1996, 4, 11), day(2026, 1, 20)), day(2026, 4, 11));
  });

  it("is next year's once this year's has passed, including on the day itself", () => {
    assert.deepEqual(nextAgeChangeAt(day(1996, 4, 11), day(2026, 4, 11)), day(2027, 4, 11));
    assert.deepEqual(nextAgeChangeAt(day(1996, 4, 11), day(2026, 10, 1)), day(2027, 4, 11));
  });

  it("is exactly the moment the age changes", () => {
    for (const born of [day(1996, 4, 11), day(2000, 2, 29), day(1990, 12, 31), day(1988, 1, 1)]) {
      for (const now of [day(2026, 10, 1), day(2027, 2, 28, 12), day(2028, 2, 29), day(2028, 3, 1)]) {
        const next = nextAgeChangeAt(born, now);
        assert.ok(next > now);
        const justBefore = new Date(next.getTime() - 1);
        assert.equal(ageFromBirthDate(born, next), ageFromBirthDate(born, justBefore) + 1);
        assert.equal(ageFromBirthDate(born, justBefore), ageFromBirthDate(born, now));
      }
    }
  });

  it("a 29 February birthday turns on 1 March in a common year", () => {
    assert.deepEqual(nextAgeChangeAt(day(2000, 2, 29), day(2026, 10, 1)), day(2027, 3, 1));
    assert.deepEqual(nextAgeChangeAt(day(2000, 2, 29), day(2027, 10, 1)), day(2028, 2, 29));
  });
});

describe("memberBirthDate", () => {
  const onAccount = ts(day(1996, 4, 11));
  const onProfile = ts(day(1990, 1, 1));

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
  const now = day(2026, 10, 1, 0);

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
      today: member(day(1996, 10, 1), {age: 29, rolloverAt: day(2026, 10, 1)}),
    });
    const result = await rollOverProfileAges(db, {now});
    assert.equal(db.read("profiles/today").age, 30);
    assert.deepEqual(db.read("users/today").ageRolloverAt.toDate(), day(2027, 10, 1));
    assert.equal(result.updated, 1);
    // The date itself never reaches the member-readable document.
    assert.equal("birthDate" in db.read("profiles/today"), false);
  });

  it("catches up on birthdays missed while it was not running", async () => {
    const db = seed({
      missed: member(day(1990, 9, 20), {age: 35, rolloverAt: day(2026, 9, 20)}),
      longAgo: member(day(1990, 3, 2), {age: 33, rolloverAt: day(2024, 3, 2)}),
    });
    await rollOverProfileAges(db, {now});
    assert.equal(db.read("profiles/missed").age, 36);
    assert.equal(db.read("profiles/longAgo").age, 36);
    assert.deepEqual(db.read("users/longAgo").ageRolloverAt.toDate(), day(2027, 3, 2));
  });

  it("leaves a member whose birthday is still ahead alone", async () => {
    const db = seed({
      later: member(day(1996, 10, 2), {age: 29, rolloverAt: day(2026, 10, 2)}),
    });
    const before = db.read("profiles/later");
    const result = await rollOverProfileAges(db, {now});
    assert.deepEqual(db.read("profiles/later"), before);
    assert.deepEqual(result, {due: 0, updated: 0, unchanged: 0, cleared: 0, failed: 0});
  });

  it("does not rewrite a profile whose age is already right", async () => {
    const db = seed({
      right: member(day(1996, 10, 1), {age: 30, rolloverAt: day(2026, 10, 1), profile: {updatedAt: ts(day(2026, 1, 1))}}),
    });
    const result = await rollOverProfileAges(db, {now});
    assert.deepEqual(db.read("profiles/right").updatedAt.toDate(), day(2026, 1, 1));
    assert.deepEqual(db.read("users/right").ageRolloverAt.toDate(), day(2027, 10, 1));
    assert.equal(result.unchanged, 1);
  });

  it("never creates a profile for an account that has none", async () => {
    const db = seed({
      bare: {...member(day(1996, 10, 1), {rolloverAt: day(2026, 10, 1)}), profile: null},
    });
    await rollOverProfileAges(db, {now});
    assert.equal(db.has("profiles/bare"), false);
    assert.deepEqual(db.read("users/bare").ageRolloverAt.toDate(), day(2027, 10, 1));
  });

  it("drops the marker from an account with no readable date of birth", async () => {
    const db = createFakeFirestore();
    db.reset({
      "users/odd": {uid: "odd", ageRolloverAt: ts(day(2026, 9, 1))},
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
      members[`m${i}`] = member(day(1990 + i, 9, 1 + i), {age: 1, rolloverAt: day(2026, 9, 1 + i)});
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
      members[`m${i}`] = member(day(1990, 9, 1 + i), {age: 35, rolloverAt: day(2026, 9, 1 + i)});
    }
    const db = seed(members);
    assert.equal((await rollOverProfileAges(db, {now, pageSize: 2, maxMembers: 4})).due, 4);
    assert.equal((await rollOverProfileAges(db, {now, pageSize: 2, maxMembers: 4})).due, 1);
  });
});

describe("moveProfileBirthDates — the backfill", () => {
  const now = day(2026, 10, 1);
  const born = day(1996, 4, 11);

  function legacy(extra = {}) {
    const db = createFakeFirestore();
    db.reset({
      "users/a": {uid: "a", accountStatus: "active"},
      "profiles/a": {uid: "a", displayName: "Ada", birthDate: ts(born), age: 27, updatedAt: ts(day(2026, 1, 1))},
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
    assert.deepEqual(profile.updatedAt.toDate(), day(2026, 1, 1));
    const account = db.read("users/a");
    assert.deepEqual(account.birthDate.toDate(), born);
    assert.deepEqual(account.ageRolloverAt.toDate(), day(2027, 4, 11));
    assert.equal(account.accountStatus, "active");
  });

  it("keeps a date the account already holds", async () => {
    const onAccount = day(1994, 2, 3);
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
      "profiles/b": {uid: "b", birthDate: ts(day(1999, 12, 31))},
    });
    assert.equal((await moveProfileBirthDates(db, {now, confirm: true, pageSize: 1})).written, 2);
    const again = await moveProfileBirthDates(db, {now, confirm: true});
    assert.equal(again.examined, 0);
    assert.equal(db.read("profiles/b").age, 26);
  });

  it("honours a limit", async () => {
    const db = legacy({
      "users/b": {uid: "b"},
      "profiles/b": {uid: "b", birthDate: ts(day(1999, 12, 31))},
    });
    const result = await moveProfileBirthDates(db, {now, confirm: true, limit: 1});
    assert.equal(result.written, 1);
  });
});

describe("accountBirthFields", () => {
  it("is the date plus the moment its age next changes", () => {
    const birthDate = ts(day(1996, 4, 11));
    const fields = accountBirthFields(birthDate, day(2026, 10, 1));
    assert.equal(fields.birthDate, birthDate);
    assert.deepEqual(fields.ageRolloverAt.toDate(), day(2027, 4, 11));
  });
});
