/**
 * Dates of birth as the app stores them, and moments on the server's clock.
 *
 * The app stores midnight of the day the member picked, on the member's own
 * clock. The server's day is UTC. Everything here is built from Date.UTC so a
 * suite reads the same whatever time zone the process runs in.
 *
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */

const HOUR_MS = 3_600_000;

/**
 * What the app stores for a member who picks y-m-d on a clock `offsetHours`
 * east of UTC (negative: west): midnight of that day there. Istanbul, UTC+3,
 * unless told otherwise — 11 April is stored as 10 April 21:00 UTC.
 */
function picked(y, m, d, offsetHours = 3) {
  return new Date(Date.UTC(y, m - 1, d) - offsetHours * HOUR_MS);
}

/** A moment on the server's clock. */
function utc(y, m, d, h = 0, min = 0) {
  return new Date(Date.UTC(y, m - 1, d, h, min));
}

/**
 * The stored date of birth of a member who turns `years` today, for the age
 * rules that read the real clock (completeOnboarding, isAdultProfile,
 * ageFromBirthDate's default): the latest one that already makes them that
 * age. `daysAfter` moves the birthday — 1 is the member still one day short,
 * a negative number one whose birthday has passed. `offsetHours` is the
 * member's clock, as in `picked`.
 *
 * "Today" is the server's day, UTC, like the age rule itself.
 */
function bornYearsAgo(years, daysAfter = 0, offsetHours = 0) {
  const today = new Date();
  const born = new Date(Date.UTC(today.getUTCFullYear() - years, today.getUTCMonth(), today.getUTCDate() + daysAfter));
  // 29 February has no anniversary in a common year: the constructor rolls it
  // to 1 March, a birthday still to come, and the age would come out one year
  // short on every leap day. The last day of February is the latest one reached.
  if (daysAfter === 0 && born.getUTCMonth() !== today.getUTCMonth()) born.setUTCDate(0);
  return new Date(born.getTime() - offsetHours * HOUR_MS);
}

module.exports = {bornYearsAgo, picked, utc};
