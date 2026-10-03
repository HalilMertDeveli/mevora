/**
 * The Humor Core sequence — the one canonical order every member rates humor
 * content in.
 *
 * V1 is the first entry, V2 the second, and so on. The first
 * `HUMOR_CORE.onboardingCount` entries are the initial calibration; afterwards
 * a member gets the next `HUMOR_CORE.dailyCount` open entries per logical day
 * (see `coreSchedule.ts`). Two members who have each rated thirty Core items
 * have therefore rated the same thirty, which is what makes their answers
 * directly comparable.
 *
 * The order is explicit — an array in this file, never a Firestore query —
 * and it is frozen by `functions/test/fixtures/humorCoreSequence.lock.json`:
 *
 * - **Append only.** A released position never moves, is never inserted
 *   before and is never removed.
 * - **The id is the joke.** An entry's id is its `humorContent` document id
 *   and names one measurement: this clip, this joke. Swapping the file, the
 *   CDN URL or the poster of the *same* clip is a rendition change — edit the
 *   content document's `media`, keep the id. A different clip, or a cut that
 *   changes what is funny about it, is a different measurement: append a new
 *   entry with `supersedes`, and retire the old one in place.
 * - **Retiring keeps the place.** A retired entry stays where it is with
 *   `active: false`, so old ratings still mean what they meant. It is skipped
 *   for everyone who has not rated it and is never backfilled, so a retired
 *   V9 makes the initial calibration fourteen items, not a different fifteen.
 * - **Curated only.** Every entry must be a curated catalogue item — a GIPHY
 *   GIF (`hc_gif_*`) or a KLIPY clip (`hc_klipy_*`, a short video). Provider
 *   sync writes `ext_giphy_*` documents that can never be listed here, so
 *   nothing a provider returns reaches a member without a person choosing it.
 *
 * To add entries: add the clip to the curated catalogue, append its id here,
 * build, run `node tool/lockHumorCoreSequence.cjs`, commit the lock.
 */
import {
  CURATED_CATALOG,
  type CuratedCatalogEntry,
} from "./calibrationSeed.js";

/** Product rules, not tuning: the first run and the daily ration. */
export const HUMOR_CORE = {
  /** Entries in the initial calibration (V1 … V15). */
  onboardingCount: 15,
  /** Most new Core entries a member gets per logical day afterwards. */
  dailyCount: 5,
} as const;

/**
 * Whether the owner has released this order to members.
 *
 * While `false` the sequence is a draft: the lock tool may rewrite the lock
 * wholesale (`--redraft`) so the order can still be reviewed and changed,
 * and only the emulator hands it out — a deployed backend serves no Core
 * content (`isHumorCoreServed` in `coreService.ts`).
 * Once `true` the lock is append-only and `--redraft` refuses to run.
 */
export const HUMOR_CORE_RELEASE = {released: false} as const;

export type HumorCoreEntry = {
  /** `humorContent` document id — the measurement identity. */
  readonly id: string;
  /** `false` once retired; the entry keeps its position. */
  readonly active: boolean;
  /** Why it was retired. Required on a retired entry. */
  readonly retiredReason?: string;
  /** The earlier, retired entry this one replaces as a measurement. */
  readonly supersedes?: string;
};

const live = (id: string): HumorCoreEntry => ({id, active: true});

export const HUMOR_CORE_SEQUENCE: readonly HumorCoreEntry[] = [
  // V1–V6 — one clip per baseline dimension.
  live("hc_gif_MvdaYPuKPMNZRJCl8Z"), // sarcasm
  live("hc_gif_37QADdG7V5bo9ToyCX"), // absurd
  live("hc_gif_U5PhYH10hwyvlt3Db3"), // situational
  live("hc_gif_d3mlE7uhX8KFgEmY"), // meme
  live("hc_gif_U8GLl0bUYFLZVquOfY"), // wordplay
  live("hc_gif_fXjdpSAXKfyw3yvVQh"), // cringe
  // V7–V11 — the five remaining dimensions, so the first fifteen cover all eleven.
  live("hc_gif_3o6ZsTBERbqBTPkRKo"), // silly
  live("hc_gif_2cYwWmw2yXdf4MDPHs"), // dry
  live("hc_gif_Xoz7C9PpMmp701d28v"), // teasing
  live("hc_gif_RG4Zzpk8aqkQdDEiPd"), // romantic
  live("hc_gif_BRErszG4ZIZPn0CYmG"), // dark
  // V12–V15 — a second reading of four baseline dimensions.
  live("hc_gif_srqiG5lSxGZTaxdld1"), // sarcasm
  live("hc_gif_BRBXMLg2n9wzZF5J63"), // absurd
  live("hc_gif_Beng9YrOPhGaB3m5zO"), // situational
  live("hc_gif_l3q2K5jinAlChoCLS"), // meme
  // V16–V20
  live("hc_gif_aHmquP8GsDCHS"), // wordplay
  live("hc_gif_1DGh2Kduf58TzskEh8"), // cringe
  live("hc_gif_JFtdcCgVSkzEa1lAgR"), // silly
  live("hc_gif_kt3PrO9QV6xMsF67oD"), // dry
  live("hc_gif_Ke2KBmPiwWmH0ZKgHl"), // teasing
  // V21–V25
  live("hc_gif_kgm8xJCg9lQV6oKkU5"), // sarcasm
  live("hc_gif_xT9IgFdfhi8lPMzlbW"), // absurd
  live("hc_gif_YqnXaLTb68GAJ8ZHFR"), // situational
  live("hc_gif_5tmS2ZkdusAYme2hd1"), // romantic
  live("hc_gif_XOrDspslyBAT7bH60s"), // dark
  // V26–V30
  live("hc_gif_pUeXcg80cO8I8"), // meme
  live("hc_gif_bwgdr1Xi3AKX86O5Oq"), // wordplay
  live("hc_gif_2kL6Xn1yfwFg62ApII"), // cringe
  live("hc_gif_lF35CodYKcV4BhpBkD"), // silly
  live("hc_gif_3ohs7V0MMoyuPsWUkU"), // teasing
  // V31–V35
  live("hc_gif_WcOykop23zlK2dAycY"), // sarcasm
  live("hc_gif_0J2IMMncQPVzY4TOLZ"), // absurd
  live("hc_gif_oStoEt37xFJvlSV2fK"), // situational
  live("hc_gif_ReyD2H8zfGPswW3fdA"), // meme
  live("hc_gif_VNeFpBkw9W3w8ulfJ9"), // wordplay
  // V36
  live("hc_gif_LM2AKwFXf4SPHOUPCn"), // cringe
];

/** 1-based place of [id] in [sequence] (V-number), or null when it is not a Core entry. */
export function humorCorePosition(
  id: string,
  sequence: readonly HumorCoreEntry[] = HUMOR_CORE_SEQUENCE,
): number | null {
  const index = sequence.findIndex((entry) => entry.id === id);
  return index < 0 ? null : index + 1;
}

/** What a sequence entry must resolve to: a curated catalogue item. */
export type HumorCoreCatalogItem = Pick<
  CuratedCatalogEntry,
  "contentId" | "category" | "humorVector" | "sourceTrust" | "calibrationEligible"
>;

const CORE_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * Why [sequence] may not ship; empty when it is well-formed.
 *
 * Checked by the freeze test and by the lock tool, so a malformed sequence
 * never reaches a build that is deployed.
 */
export function humorCoreSequenceProblems(
  sequence: readonly HumorCoreEntry[] = HUMOR_CORE_SEQUENCE,
  catalog: readonly HumorCoreCatalogItem[] = CURATED_CATALOG,
): string[] {
  const problems: string[] = [];
  const known = new Map(catalog.map((item) => [item.contentId, item]));
  const firstIndex = new Map<string, number>();
  sequence.forEach((entry, index) => {
    const at = `V${index + 1} ${entry.id}`;
    if (!CORE_ID_PATTERN.test(entry.id)) {
      problems.push(`${at}: malformed id`);
      return;
    }
    if (firstIndex.has(entry.id)) {
      problems.push(`${at}: duplicate of V${(firstIndex.get(entry.id) ?? 0) + 1}`);
      return;
    }
    firstIndex.set(entry.id, index);
    const item = known.get(entry.id);
    if (!item) {
      problems.push(`${at}: not in the curated catalogue`);
    } else if (item.sourceTrust !== "curated" || item.calibrationEligible !== true) {
      problems.push(`${at}: not curated`);
    }
    if (!entry.active && !entry.retiredReason?.trim()) {
      problems.push(`${at}: retired without a reason`);
    }
    if (entry.active && entry.retiredReason !== undefined) {
      problems.push(`${at}: active entry carries a retiredReason`);
    }
    if (entry.supersedes !== undefined) {
      const earlier = firstIndex.get(entry.supersedes);
      if (earlier === undefined || earlier >= index) {
        problems.push(`${at}: supersedes an entry that is not earlier in the sequence`);
      } else if (sequence[earlier].active) {
        problems.push(`${at}: supersedes V${earlier + 1}, which is still active`);
      }
    }
  });
  return problems;
}
