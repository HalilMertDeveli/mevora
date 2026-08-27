const test = require("node:test");
const assert = require("node:assert/strict");
const {
  applyParticipation,
  dailyParticipation,
  effectiveStreak,
  emptyMatchingStreakState,
  istanbulDayKey,
  previousIstanbulDayKey,
} = require("../lib/matchingStreakEngine.js");

const REWARDS = [
  {id: "r7", minDays: 7, type: "profile_badge"},
  {id: "r14", minDays: 14, type: "compatibility_insight"},
  {id: "r30", minDays: 30, type: "boost_discount"},
];

test("first day starts streak at 1", () => {
  const r = applyParticipation({
    state: emptyMatchingStreakState(),
    dayKey: "2026-08-27",
    roundId: "2026082712",
    rewards: REWARDS,
  });
  assert.equal(r.alreadyParticipatedToday, false);
  assert.equal(r.state.currentStreak, 1);
  assert.equal(r.state.longestStreak, 1);
  assert.equal(r.state.lastParticipatedDay, "2026-08-27");
});

test("same day second game does not increment", () => {
  const first = applyParticipation({
    state: emptyMatchingStreakState(),
    dayKey: "2026-08-27",
    roundId: "2026082710",
    rewards: REWARDS,
  });
  const second = applyParticipation({
    state: first.state,
    dayKey: "2026-08-27",
    roundId: "2026082722",
    rewards: REWARDS,
  });
  assert.equal(second.alreadyParticipatedToday, true);
  assert.equal(second.state.currentStreak, 1);
  assert.equal(second.state.lastRoundId, "2026082722");
});

test("next Istanbul day increments by 1", () => {
  let state = emptyMatchingStreakState();
  state = applyParticipation({
    state,
    dayKey: "2026-08-27",
    roundId: "a",
    rewards: REWARDS,
  }).state;
  state = applyParticipation({
    state,
    dayKey: "2026-08-28",
    roundId: "b",
    rewards: REWARDS,
  }).state;
  assert.equal(state.currentStreak, 2);
});

test("missing a day resets to 1 on return", () => {
  let state = emptyMatchingStreakState();
  state = applyParticipation({
    state,
    dayKey: "2026-08-27",
    roundId: "a",
    rewards: REWARDS,
  }).state;
  state = applyParticipation({
    state,
    dayKey: "2026-08-28",
    roundId: "b",
    rewards: REWARDS,
  }).state;
  const r = applyParticipation({
    state,
    dayKey: "2026-08-30",
    roundId: "c",
    rewards: REWARDS,
  });
  assert.equal(r.state.currentStreak, 1);
  assert.equal(r.state.longestStreak, 2);
});

test("effectiveStreak is 0 after a missed day until participation", () => {
  const state = {
    currentStreak: 5,
    longestStreak: 5,
    lastParticipatedDay: "2026-08-25",
    lastRoundId: "x",
    unlockedRewardIds: [],
  };
  assert.equal(effectiveStreak(state, "2026-08-27"), 0);
  assert.equal(dailyParticipation(state, "2026-08-27"), false);
  assert.equal(effectiveStreak(state, "2026-08-26"), 5);
});

test("previousIstanbulDayKey crosses month boundary", () => {
  assert.equal(previousIstanbulDayKey("2026-09-01"), "2026-08-31");
  assert.equal(previousIstanbulDayKey("2026-01-01"), "2025-12-31");
});

test("istanbulDayKey uses Europe/Istanbul not UTC day", () => {
  // 2026-08-26 22:30 UTC = 2026-08-27 01:30 Istanbul
  const utcLate = new Date(Date.UTC(2026, 7, 26, 22, 30, 0));
  assert.equal(istanbulDayKey(utcLate), "2026-08-27");
  // 2026-08-26 20:30 UTC = 2026-08-26 23:30 Istanbul
  const utcEarly = new Date(Date.UTC(2026, 7, 26, 20, 30, 0));
  assert.equal(istanbulDayKey(utcEarly), "2026-08-26");
});

test("reward unlocks at configured thresholds only once", () => {
  let state = emptyMatchingStreakState();
  for (let d = 1; d <= 7; d++) {
    const day = `2026-08-${String(d).padStart(2, "0")}`;
    const r = applyParticipation({
      state,
      dayKey: day,
      roundId: `r${d}`,
      rewards: REWARDS,
    });
    state = r.state;
    if (d < 7) {
      assert.equal(r.newlyUnlocked.length, 0);
    } else {
      assert.equal(r.newlyUnlocked.map((x) => x.id).join(","), "r7");
    }
  }
  const again = applyParticipation({
    state,
    dayKey: "2026-08-08",
    roundId: "r8",
    rewards: REWARDS,
  });
  assert.equal(again.newlyUnlocked.length, 0);
  assert.ok(again.state.unlockedRewardIds.includes("r7"));
});

test("ten games same day still +1 total", () => {
  let state = emptyMatchingStreakState();
  for (let i = 0; i < 10; i++) {
    state = applyParticipation({
      state,
      dayKey: "2026-08-27",
      roundId: `g${i}`,
      rewards: REWARDS,
    }).state;
  }
  assert.equal(state.currentStreak, 1);
});
