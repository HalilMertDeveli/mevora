import type {HumorSourceItem} from "./sourceAdapter.js";
import type {HumorAttribution, HumorSourceTrust} from "./types.js";

/**
 * Deterministic relevance filter for licensed provider content.
 *
 * No LLM and no new dependency: a small TR + EN lexicon decides whether an
 * item is *about* humour, and a stop-list throws out what a humour search
 * drags in anyway — wallpapers, landscapes, abstract loops, greeting cards,
 * logos, transparent stickers. When in doubt an item is rejected: a thinner
 * feed is better than one padded with a sunset under a joke.
 *
 * All matching runs on "folded" text: lower-case, Turkish letters mapped to
 * ASCII (ç→c, ğ→g, ı/İ→i, ö→o, ş→s, ü→u) and other diacritics stripped, then
 * split into words on anything that is not a letter or digit. Slugs such as
 * `the-office-funny-reaction-12XMGIWtrHBl5e` therefore split cleanly.
 */

const TURKISH_FOLD: Record<string, string> = {
  "ç": "c",
  "ğ": "g",
  "ı": "i",
  "İ": "i",
  "ö": "o",
  "ş": "s",
  "ü": "u",
  "Ç": "c",
  "Ğ": "g",
  "Ö": "o",
  "Ş": "s",
  "Ü": "u",
};

/** Lower-case, Turkish-aware ASCII fold. */
export function foldText(value: string | null | undefined): string {
  if (!value) return "";
  return value
    .replace(/[çğıİöşüÇĞÖŞÜ]/g, (ch) => TURKISH_FOLD[ch] ?? ch)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "");
}

export function foldedWords(value: string | null | undefined): string[] {
  return foldText(value).split(/[^a-z0-9]+/).filter(Boolean);
}

/** Whole words that mark an item as humour / reaction / comedy. */
const HUMOR_WORDS = new Set([
  // English
  "funny", "funnier", "funniest", "lol", "lmao", "lmfao", "rofl", "lolz",
  "comedy", "comedic", "comedian", "comedians", "hilarious", "humor",
  "humour", "humorous", "joke", "jokes", "joking", "prank", "pranks",
  "sitcom", "sitcoms", "reaction", "reactions", "react", "reacting", "meme",
  "memes", "sarcasm", "sarcastic", "irony", "ironic", "awkward", "cringe",
  "cringey", "cringy", "facepalm", "eyeroll", "shocked", "shook", "surprised",
  "confused", "wtf", "omg", "deadpan", "absurd", "silly", "goofy", "parody",
  "spoof", "snl", "standup", "bruh", "smh", "laugh", "laughs", "laughing",
  "laughter", "giggle", "giggling", "chuckle", "smirk", "sassy", "sass",
  "roast", "roasted", "fail",
  // Turkish (folded)
  "komik", "komiklik", "komedi", "komedyen", "kahkaha", "kahkahalar",
  "gulmek", "gulme", "gulmekten", "guluyor", "guluyorum", "gulus", "gulerken",
  "espri", "espriler", "esprili", "mizah", "mizahi", "saka", "sakasi",
  "ironi", "ironik", "sarkazm", "sarkastik", "tepki", "tepkisi", "tepkiler",
  "saskin", "saskinlik", "sasirdim", "sasirmak", "absurt", "sitkom", "skec",
  "parodi", "rezil", "rezillik", "yuh",
]);

/** Word prefixes (stems) that mark humour: "hahaha", "komedisi", "laughed"... */
const HUMOR_STEMS = [
  "haha", "ahaha", "hehe", "funn", "comed", "laugh", "giggl", "chuckl",
  "cring", "awkward", "hilari", "sarcas", "prank", "sitcom", "joke",
  "komik", "komed", "kahkaha", "gulmek", "espri", "mizah", "sarkas", "tepki",
  "sasir", "saskin",
];

/** Multi-word humour markers, matched on the folded word sequence. */
const HUMOR_PHRASES = [
  "eye roll", "side eye", "slow clap", "mic drop", "dry humor", "dry humour",
  "plot twist", "stand up", "dalga gec", "tiye al",
];

/** Whole words that mark an item as off-topic backdrop material. */
const STOP_WORDS = new Set([
  "wallpaper", "wallpapers", "landscape", "landscapes", "nature", "background",
  "backgrounds", "scenery", "abstract", "aesthetic", "aesthetics", "pattern",
  "patterns", "logo", "logos", "sunset", "sunrise", "seascape", "waterfall",
  "screensaver", "congratulations", "manzara", "doga", "gunaydin",
  "tesekkurler",
]);

/** Multi-word stop markers: loops, and text-only greeting cards. */
const STOP_PHRASES = [
  "loop pattern", "seamless loop", "happy birthday", "good morning",
  "good night", "happy new year", "merry christmas", "happy holidays",
  "thank you", "duvar kagidi", "arka plan", "gun batimi", "iyi geceler",
  "iyi aksamlar", "dogum gunu", "dogum gunun", "iyi bayramlar",
  "hayirli cumalar", "yeni yiliniz", "tesekkur ederim",
];

export const ALLOWED_PROVIDER_RATINGS: readonly string[] = ["g", "pg", "pg-13"];

/**
 * Entertainment studios / networks whose official accounts get the verified
 * trust tier even when the provider does not flag them `is_verified`.
 * Matched case-insensitively on the exact username or display name.
 */
export const KNOWN_ENTERTAINMENT_ACCOUNTS: readonly string[] = [
  "nbc", "theoffice", "brooklyn99", "brooklynninenine", "snl",
  "saturdaynightlive", "netflix", "netflixturkiye", "primevideo",
  "primevideotr", "disneyplus", "hbo", "hbomax", "max", "hulu", "peacock",
  "paramountplus", "comedycentral", "adultswim", "foxtv", "fox", "abcnetwork",
  "cbs", "tbs", "bbc", "bbcone", "appletv", "trt", "trt1", "blutv", "exxen",
  "tabii", "gainmedya", "showtv", "kanald", "atv", "startv",
];

type TextBag = {words: Set<string>; sequence: string};

function bagOf(texts: Array<string | null | undefined>): TextBag {
  const all: string[] = [];
  for (const text of texts) {
    all.push(...foldedWords(text));
  }
  return {words: new Set(all), sequence: ` ${all.join(" ")} `};
}

function hasPhrase(bag: TextBag, phrases: readonly string[]): boolean {
  // A phrase starts on a word boundary and may end mid-word, so "dalga gec"
  // also matches "dalga gecmek".
  return phrases.some((phrase) => bag.sequence.includes(` ${phrase}`));
}

function textsOf(item: HumorSourceItem): Array<string | null | undefined> {
  return [
    item.rawTitle,
    item.title,
    item.slug,
    item.altText,
    ...(item.tags ?? []),
  ];
}

/** True when the provider text carries a humour / reaction / comedy marker. */
export function hasHumorSignal(item: HumorSourceItem): boolean {
  const bag = bagOf(textsOf(item));
  for (const word of bag.words) {
    if (HUMOR_WORDS.has(word)) return true;
    if (HUMOR_STEMS.some((stem) => word.startsWith(stem))) return true;
  }
  return hasPhrase(bag, HUMOR_PHRASES);
}

/** True when the provider text marks the item as backdrop / greeting / logo. */
export function hasStopSignal(item: HumorSourceItem): boolean {
  const bag = bagOf(textsOf(item));
  for (const word of bag.words) {
    if (STOP_WORDS.has(word)) return true;
  }
  return hasPhrase(bag, STOP_PHRASES);
}

export function isKnownEntertainmentAccount(
  attribution: Pick<HumorAttribution, "username" | "displayName"> | null | undefined,
): boolean {
  if (!attribution) return false;
  const names = [attribution.username, attribution.displayName]
    .map((name) => foldText(name).replace(/[^a-z0-9]/g, ""))
    .filter(Boolean);
  return names.some((name) => KNOWN_ENTERTAINMENT_ACCOUNTS.includes(name));
}

/** Trust tier of a provider item. Never "curated": that is Mevora-authored only. */
export function providerSourceTrust(
  attribution: HumorAttribution | null | undefined,
): HumorSourceTrust {
  if (attribution && (attribution.verified || isKnownEntertainmentAccount(attribution))) {
    return "verified_provider";
  }
  return "provider";
}

export type RelevanceVerdict =
  | {ok: true; basis: "lexicon" | "verified-comedy-query"}
  | {ok: false; reason: string};

/**
 * Accept or reject one mapped provider item. Order matters: hard safety and
 * shape checks first, then the stop-list (it beats the lexicon: a "funny
 * wallpaper" is still a wallpaper), then the positive signal.
 */
export function assessProviderRelevance(item: HumorSourceItem): RelevanceVerdict {
  if (!item.media?.downloadUrl) {
    return {ok: false, reason: "missing-media"};
  }
  const rating = (item.rating ?? "").trim().toLowerCase();
  if (!ALLOWED_PROVIDER_RATINGS.includes(rating)) {
    return {ok: false, reason: "rating"};
  }
  if (item.isSticker === true) {
    return {ok: false, reason: "sticker"};
  }
  if (hasStopSignal(item)) {
    return {ok: false, reason: "off-topic"};
  }
  if (hasHumorSignal(item)) {
    return {ok: true, basis: "lexicon"};
  }
  // Every query family is a comedy query, so "matched a comedy query" is
  // "came from one of them". That alone is not enough — only a verified or
  // known entertainment account earns the benefit of the doubt.
  if (item.queryCategory && providerSourceTrust(item.attribution) === "verified_provider") {
    return {ok: true, basis: "verified-comedy-query"};
  }
  return {ok: false, reason: "not-humor"};
}
