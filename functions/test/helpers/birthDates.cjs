/**
 * Birth dates measured back from today, for the age rules that read the real
 * clock (completeOnboarding, isAdultProfile, ageFromBirthDate's default).
 *
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */

/**
 * The birth date of a member who turns `years` today: the latest one that
 * already makes them that age. `daysAfter` moves the birthday — 1 is the
 * member still one day short, a negative number one whose birthday has passed.
 *
 * Local-time calendar fields, like the age rule itself.
 */
function bornYearsAgo(years, daysAfter = 0) {
  const today = new Date();
  const born = new Date(today.getFullYear() - years, today.getMonth(), today.getDate() + daysAfter);
  // 29 February has no anniversary in a common year: the constructor rolls it
  // to 1 March, a birthday still to come, and the age came out one year short
  // on every leap day. The last day of February is the latest one reached.
  if (daysAfter === 0 && born.getMonth() !== today.getMonth()) born.setDate(0);
  return born;
}

module.exports = {bornYearsAgo};
