/**
 * Pure hourly matching-game engine (no Firebase I/O).
 * Answer ids stay a/b/c — ordinal distance only; question text is never touched.
 */

export type AnswerMap = Record<string, string>;

export type PairScore = {
  userA: string;
  userB: string;
  score: number;
  exactAligned: number;
  shared: number;
  avgDistance: number;
};

const ORDINAL: Record<string, number> = {a: 0, b: 1, c: 2};
const MAX_DISTANCE = 2;

export function answerOrdinal(answerId: string): number | null {
  const key = String(answerId ?? "").trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(ORDINAL, key) ? ORDINAL[key] : null;
}

/** Per-question similarity in [0, 1]. Exact match = 1. */
export function questionSimilarity(answerA: string, answerB: string): number {
  const oa = answerOrdinal(answerA);
  const ob = answerOrdinal(answerB);
  if (oa == null || ob == null) {
    return answerA === answerB ? 1 : 0;
  }
  return 1 - Math.abs(oa - ob) / MAX_DISTANCE;
}

export function scoreAnswerSnapshots(
  a: AnswerMap,
  b: AnswerMap,
): {score: number; exactAligned: number; shared: number; avgDistance: number} {
  const ids = Object.keys(a).filter((id) => Object.prototype.hasOwnProperty.call(b, id));
  if (ids.length === 0) {
    return {score: 0, exactAligned: 0, shared: 0, avgDistance: MAX_DISTANCE};
  }
  let similaritySum = 0;
  let exact = 0;
  let distanceSum = 0;
  for (const id of ids) {
    const aa = a[id];
    const bb = b[id];
    similaritySum += questionSimilarity(aa, bb);
    if (aa === bb) exact += 1;
    const oa = answerOrdinal(aa);
    const ob = answerOrdinal(bb);
    distanceSum += oa == null || ob == null ? (aa === bb ? 0 : MAX_DISTANCE) : Math.abs(oa - ob);
  }
  const shared = ids.length;
  return {
    score: Math.max(0, Math.min(100, Math.round((similaritySum / shared) * 100))),
    exactAligned: exact,
    shared,
    avgDistance: distanceSum / shared,
  };
}

/**
 * Rank edges: exact aligned desc, avg distance asc, score desc, then uid tie-break.
 */
export function comparePairScores(left: PairScore, right: PairScore): number {
  if (right.exactAligned !== left.exactAligned) {
    return right.exactAligned - left.exactAligned;
  }
  if (left.avgDistance !== right.avgDistance) {
    return left.avgDistance - right.avgDistance;
  }
  if (right.score !== left.score) {
    return right.score - left.score;
  }
  const leftKey = [left.userA, left.userB].sort().join("|");
  const rightKey = [right.userA, right.userB].sort().join("|");
  return leftKey < rightKey ? -1 : leftKey > rightKey ? 1 : 0;
}

export function buildPairScores(
  participants: Array<{uid: string; answers: AnswerMap}>,
): PairScore[] {
  const pairs: PairScore[] = [];
  for (let i = 0; i < participants.length; i++) {
    for (let j = i + 1; j < participants.length; j++) {
      const left = participants[i];
      const right = participants[j];
      const scored = scoreAnswerSnapshots(left.answers, right.answers);
      if (scored.shared === 0) continue;
      const [userA, userB] = [left.uid, right.uid].sort();
      pairs.push({
        userA,
        userB,
        score: scored.score,
        exactAligned: scored.exactAligned,
        shared: scored.shared,
        avgDistance: scored.avgDistance,
      });
    }
  }
  pairs.sort(comparePairScores);
  return pairs;
}

/**
 * Top-K edges per user, then greedy 1:1 matching (deterministic).
 * Repeat pairs can be deprioritized via [repeatPenalty] (score subtracted).
 */
export function optimizeMatches(input: {
  participants: Array<{uid: string; answers: AnswerMap}>;
  topK?: number;
  repeatPairs?: Set<string>;
  repeatPenalty?: number;
}): PairScore[] {
  const topK = input.topK ?? 20;
  const penalty = input.repeatPenalty ?? 15;
  const repeat = input.repeatPairs ?? new Set<string>();
  const all = buildPairScores(input.participants).map((pair) => {
    const key = `${pair.userA}|${pair.userB}`;
    if (!repeat.has(key)) return pair;
    return {...pair, score: Math.max(0, pair.score - penalty)};
  });
  all.sort(comparePairScores);

  const perUser = new Map<string, PairScore[]>();
  for (const pair of all) {
    for (const uid of [pair.userA, pair.userB]) {
      const list = perUser.get(uid) ?? [];
      if (list.length < topK) {
        list.push(pair);
        perUser.set(uid, list);
      }
    }
  }

  const candidateKeys = new Set<string>();
  const candidates: PairScore[] = [];
  for (const list of perUser.values()) {
    for (const pair of list) {
      const key = `${pair.userA}|${pair.userB}`;
      if (candidateKeys.has(key)) continue;
      candidateKeys.add(key);
      candidates.push(pair);
    }
  }
  candidates.sort(comparePairScores);

  const matched = new Set<string>();
  const chosen: PairScore[] = [];
  for (const pair of candidates) {
    if (matched.has(pair.userA) || matched.has(pair.userB)) continue;
    matched.add(pair.userA);
    matched.add(pair.userB);
    chosen.push(pair);
  }
  return chosen;
}

/** Round id for Europe/Istanbul wall clock: YYYYMMDDHH (24h). */
export function istanbulRoundId(now: Date = new Date()): string {
  const parts = istanbulDateParts(now);
  return `${parts.year}${parts.month}${parts.day}${parts.hour}`;
}

export function istanbulDateParts(now: Date): {
  year: string;
  month: string;
  day: string;
  hour: string;
} {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: "Europe/Istanbul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23",
  });
  const bag: Record<string, string> = {};
  for (const part of dtf.formatToParts(now)) {
    if (part.type !== "literal") bag[part.type] = part.value;
  }
  let hour = bag.hour ?? "00";
  if (hour === "24") hour = "00";
  return {
    year: bag.year ?? "1970",
    month: bag.month ?? "01",
    day: bag.day ?? "01",
    hour: hour.padStart(2, "0"),
  };
}

/** Previous Istanbul hour round id (handles day/month/year wrap). */
export function previousIstanbulRoundId(now: Date = new Date()): string {
  return istanbulRoundId(new Date(now.getTime() - 60 * 60 * 1000));
}

export function parseRoundId(roundId: string): {
  year: number;
  month: number;
  day: number;
  hour: number;
} | null {
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})$/.exec(roundId);
  if (!m) return null;
  return {
    year: Number(m[1]),
    month: Number(m[2]),
    day: Number(m[3]),
    hour: Number(m[4]),
  };
}

/**
 * Civil Istanbul hour before [roundId] (handles 00 → previous day 23).
 * Turkey has no DST (permanent UTC+3), so calendar day math is stable.
 */
export function predecessorRoundId(roundId: string): string | null {
  const p = parseRoundId(roundId);
  if (!p) return null;
  let {year, month, day, hour} = p;
  hour -= 1;
  if (hour < 0) {
    hour = 23;
    const noon = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
    noon.setUTCDate(noon.getUTCDate() - 1);
    year = noon.getUTCFullYear();
    month = noon.getUTCMonth() + 1;
    day = noon.getUTCDate();
  }
  return (
    `${year}` +
    `${String(month).padStart(2, "0")}` +
    `${String(day).padStart(2, "0")}` +
    `${String(hour).padStart(2, "0")}`
  );
}
