import {createHash} from "node:crypto";

export type RelationshipAnswers = Record<string, string>;

export type RelationshipCompatibility = {
  score: number;
  sharedQuestionCount: number;
  alignedCount: number;
  topTopics: string[];
};

const QUESTION_TOPICS: Record<string, string> = {
  rq_001: "friendship",
  rq_002: "exes",
  rq_003: "boundaries",
  rq_004: "socialLife",
  rq_005: "jealousy",
  rq_006: "friendship",
  rq_007: "personalSpace",
  rq_008: "communication",
  rq_009: "money",
  rq_010: "exes",
  rq_011: "socialLife",
  rq_012: "communication",
  rq_013: "expectations",
  rq_014: "communication",
  rq_015: "flirting",
  rq_016: "trust",
  rq_017: "loyalty",
  rq_018: "boundaries",
  rq_019: "futurePlans",
  rq_020: "money",
  rq_021: "socialLife",
  rq_022: "jealousy",
  rq_023: "trust",
  rq_024: "exes",
  rq_025: "communication",
  rq_026: "friendship",
  rq_027: "personalSpace",
  rq_028: "loyalty",
  rq_029: "money",
  rq_030: "expectations",
  rq_031: "flirting",
  rq_032: "boundaries",
  rq_033: "trust",
  rq_034: "socialLife",
  rq_035: "futurePlans",
  rq_036: "jealousy",
  rq_037: "communication",
  rq_038: "personalSpace",
  rq_039: "exes",
  rq_040: "money",
  rq_041: "loyalty",
  rq_042: "friendship",
  rq_043: "expectations",
  rq_044: "communication",
  rq_045: "boundaries",
  rq_046: "trust",
  rq_047: "socialLife",
  rq_048: "futurePlans",
  rq_049: "flirting",
  rq_050: "jealousy",
  rq_051: "exes",
  rq_052: "money",
  rq_053: "personalSpace",
  rq_054: "communication",
  rq_055: "friendship",
  rq_056: "loyalty",
  rq_057: "boundaries",
  rq_058: "socialLife",
  rq_059: "trust",
  rq_060: "expectations",
  rq_061: "futurePlans",
  rq_062: "flirting",
  rq_063: "jealousy",
  rq_064: "communication",
  rq_065: "money",
  rq_066: "exes",
  rq_067: "personalSpace",
  rq_068: "friendship",
  rq_069: "loyalty",
  rq_070: "boundaries",
  rq_071: "socialLife",
  rq_072: "trust",
  rq_073: "futurePlans",
  rq_074: "expectations",
  rq_075: "flirting",
  rq_076: "communication",
  rq_077: "money",
  rq_078: "jealousy",
  rq_079: "exes",
  rq_080: "personalSpace",
  rq_081: "loyalty",
  rq_082: "friendship",
  rq_083: "boundaries",
  rq_084: "socialLife",
  rq_085: "communication",
  rq_086: "trust",
  rq_087: "futurePlans",
  rq_088: "money",
  rq_089: "expectations",
  rq_090: "flirting",
  rq_091: "jealousy",
  rq_092: "exes",
  rq_093: "personalSpace",
  rq_094: "loyalty",
  rq_095: "friendship",
  rq_096: "boundaries",
  rq_097: "socialLife",
  rq_098: "communication",
  rq_099: "trust",
  rq_100: "futurePlans",
  rq_101: "money",
  rq_102: "expectations",
  rq_103: "flirting",
  rq_104: "jealousy",
  rq_105: "exes",
  rq_106: "personalSpace",
  rq_107: "loyalty",
  rq_108: "communication",
  rq_109: "friendship",
  rq_110: "boundaries",
  rq_111: "expectations",
};

/** Keep in sync with Flutter RelationshipQuestionCatalog size. */
export const RELATIONSHIP_QUESTION_MAX_ID = 111;

export function isValidRelationshipAnswer(
  questionId: string,
  answerId: string,
): boolean {
  if (!/^rq_\d{3}$/.test(questionId)) return false;
  const n = Number(questionId.slice(3));
  if (!Number.isInteger(n) || n < 1 || n > RELATIONSHIP_QUESTION_MAX_ID) {
    return false;
  }
  return answerId === "a" || answerId === "b" || answerId === "c";
}

/** Normalize legacy / UI variants to canonical a|b|c. */
export function normalizeAnswerId(raw: unknown): string | null {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const n = Math.trunc(raw);
    if (n === 1 || n === 0) return "a";
    if (n === 2) return "b";
    if (n === 3) return "c";
    return null;
  }
  if (typeof raw !== "string") {
    return null;
  }
  const v = raw.trim().toLowerCase();
  if (v === "a" || v === "b" || v === "c") {
    return v;
  }
  if (
    v === "option_a" ||
    v === "option_1" ||
    v === "answer_a" ||
    v === "1" ||
    v === "a1"
  ) {
    return "a";
  }
  if (
    v === "option_b" ||
    v === "option_2" ||
    v === "answer_b" ||
    v === "2" ||
    v === "b1"
  ) {
    return "b";
  }
  if (
    v === "option_c" ||
    v === "option_3" ||
    v === "answer_c" ||
    v === "3" ||
    v === "c1"
  ) {
    return "c";
  }
  return null;
}

export function scoreRelationshipCompatibility(
  viewer: RelationshipAnswers,
  candidate: RelationshipAnswers,
): RelationshipCompatibility {
  const viewerKeys = Object.keys(viewer);
  const candidateKeys = Object.keys(candidate);
  if (viewerKeys.length === 0 || candidateKeys.length === 0) {
    return {score: 0, sharedQuestionCount: 0, alignedCount: 0, topTopics: []};
  }
  let shared = 0;
  let aligned = 0;
  const topicHits = new Map<string, number>();
  for (const questionId of viewerKeys) {
    const viewerAnswer = normalizeAnswerId(viewer[questionId]) ?? viewer[questionId];
    const otherRaw = candidate[questionId];
    if (otherRaw == null) continue;
    const otherAnswer = normalizeAnswerId(otherRaw) ?? String(otherRaw);
    shared += 1;
    if (otherAnswer === viewerAnswer) {
      aligned += 1;
      const topic = QUESTION_TOPICS[questionId];
      if (topic) {
        topicHits.set(topic, (topicHits.get(topic) ?? 0) + 1);
      }
    }
  }
  if (shared === 0) {
    return {score: 0, sharedQuestionCount: 0, alignedCount: 0, topTopics: []};
  }
  const topTopics = [...topicHits.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([topic]) => topic);
  return {
    score: Math.max(0, Math.min(100, Math.round((aligned / shared) * 100))),
    sharedQuestionCount: shared,
    alignedCount: aligned,
    topTopics,
  };
}

export function answersFromSummary(data: {answers?: unknown} | undefined): RelationshipAnswers {
  const raw = data?.answers;
  if (!raw || typeof raw !== "object") return {};
  const out: RelationshipAnswers = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const normalized = normalizeAnswerId(value);
    if (normalized && isValidRelationshipAnswer(key, normalized)) {
      out[key] = normalized;
    }
  }
  return out;
}

export const RELATIONSHIP_SET_SIZE = 3;
export const MAX_RELATIONSHIP_MATCH_KM = 100;

export function isWithinRelationshipRadius(km: number | null | undefined): boolean {
  return typeof km === "number" && Number.isFinite(km) && km <= MAX_RELATIONSHIP_MATCH_KM;
}

export function relationshipQuestionSets(): string[][] {
  const sets: string[][] = [];
  for (let n = 1; n + RELATIONSHIP_SET_SIZE - 1 <= 110; n += RELATIONSHIP_SET_SIZE) {
    sets.push([padQuestionId(n), padQuestionId(n + 1), padQuestionId(n + 2)]);
  }
  return sets;
}

export function setIdFor(questionIds: string[]): string | null {
  const wanted = [...questionIds].sort().join("|");
  const sets = relationshipQuestionSets();
  for (let i = 0; i < sets.length; i++) {
    if ([...sets[i]].sort().join("|") === wanted) {
      return `set_${String(i).padStart(2, "0")}`;
    }
  }
  return null;
}

export function canonicalCompatibilityKey(answers: RelationshipAnswers, questionIds: string[]): string {
  const ids = [...questionIds].sort();
  return ids.map((id) => `${id}:${answers[id]}`).join("|");
}

export function hashCompatibilityKey(canonical: string): string {
  return createHash("sha256").update(canonical).digest("hex");
}

export function isExactTriple(
  viewer: RelationshipAnswers,
  candidate: RelationshipAnswers,
  questionIds: string[],
): boolean {
  if (questionIds.length !== RELATIONSHIP_SET_SIZE) return false;
  for (const id of questionIds) {
    if (!viewer[id] || !candidate[id] || viewer[id] !== candidate[id]) {
      return false;
    }
  }
  return true;
}

function padQuestionId(n: number): string {
  return `rq_${String(n).padStart(3, "0")}`;
}
