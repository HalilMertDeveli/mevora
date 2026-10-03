import {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} from "./calibration.js";
import type {HumorCategory, HumorVector} from "./categories.js";
import type {UpsertHumorContentInput} from "./contentRepository.js";
import type {HumorAttribution} from "./types.js";

/**
 * The curated calibration catalogue: hand-picked GIPHY clips.
 *
 * Owner decision: every Humor card, calibration included, is a GIF. Each item
 * below is ONE exact GIPHY clip a Mevora curator watched, annotated with a
 * vector authored for that clip, and credited to its GIPHY uploader on the
 * card (K1). The joke is in the clip, so there is no caption: GIPHY titles are
 * search tags, not captions, and Mevora never writes text over a clip.
 *
 * Shape: 6 anchor slots x {@link ANCHOR_POOL_TARGET} interchangeable
 * candidates, plus an open pool (no slot) that the adaptive and exploration
 * stages draw from — including teasing, romantic and dark, which the anchor
 * stage deliberately does not measure.
 *
 * The Mevora-authored text-joke cards this replaced are gone from the source;
 * only their ids remain ({@link RETIRED_TEXT_JOKE_CONTENT_IDS}) so the seeders
 * can retire documents an earlier seed wrote (see `calibrationCatalog.ts`).
 */

/** How many interchangeable candidates each anchor slot should have. */
export const ANCHOR_POOL_TARGET = 4;

/**
 * Document ids of the retired text-joke calibration cards. Seeding the
 * curated GIPHY catalogue deactivates and un-curates any of these it finds
 * (never deletes them: ratings keep pointing at something real).
 */
export const RETIRED_TEXT_JOKE_CONTENT_IDS: readonly string[] = [
  // former anchors
  "hc_tr_img_001", "hc_tr_img_006", "hc_tr_img_012", "hc_tr_vid_007",
  "hc_tr_vid_001", "hc_tr_vid_006", "hc_tr_img_013", "hc_tr_img_014",
  "hc_tr_vid_002", "hc_tr_img_007", "hc_tr_img_015", "hc_tr_vid_008",
  "hc_tr_vid_004", "hc_tr_img_008", "hc_tr_img_016", "hc_tr_img_017",
  "hc_tr_img_002", "hc_tr_img_009", "hc_tr_img_018", "hc_tr_img_019",
  "hc_tr_img_004", "hc_tr_img_010", "hc_tr_img_020", "hc_tr_img_021",
  // former open pool
  "hc_tr_vid_003", "hc_tr_img_003", "hc_tr_img_022", "hc_tr_img_005",
  "hc_tr_img_023", "hc_tr_vid_005", "hc_tr_img_024", "hc_tr_img_011",
  "hc_tr_img_025", "hc_tr_img_026", "hc_en_vid_001", "hc_en_img_001",
];

// --------------------------------------------------------------------------
// Curated GIPHY catalogue
// --------------------------------------------------------------------------

/** Content-id namespace of curated GIPHY items. Provider sync uses `ext_giphy_`. */
export const CURATED_GIPHY_ID_PREFIX = "hc_gif_";

/** GIPHY ids are short alphanumeric strings. */
export const GIPHY_ID_PATTERN = /^[A-Za-z0-9]{4,64}$/;

export function curatedGiphyContentId(giphyId: string): string {
  return `${CURATED_GIPHY_ID_PREFIX}${giphyId}`;
}

/** Content-id namespace of curated KLIPY clips (short videos). */
export const CURATED_KLIPY_ID_PREFIX = "hc_klipy_";

/** KLIPY ids are long decimal numbers; kept as strings (they exceed 2^53). */
export const KLIPY_ID_PATTERN = /^[0-9]{6,24}$/;

export function curatedKlipyContentId(klipyId: string): string {
  return `${CURATED_KLIPY_ID_PREFIX}${klipyId}`;
}

/** Stable, shard-independent animated WebP of a GIPHY item. */
export function giphyStableWebpUrl(giphyId: string): string {
  return `https://media.giphy.com/media/${giphyId}/giphy.webp`;
}

/** Stable, shard-independent still (first frame) of a GIPHY item. */
export function giphyStableStillUrl(giphyId: string): string {
  return `https://media.giphy.com/media/${giphyId}/giphy_s.gif`;
}

/**
 * One exact GIPHY item that a Mevora curator watched and annotated.
 *
 * Everything here describes THAT clip: the vector is authored for it, the
 * media and poster are its own renditions, the caption is GIPHY's own title
 * for it (cleaned by `cleanProviderTitle`) or null — never text we wrote —
 * and the attribution is GIPHY's credit for it, shown on the card (K1).
 *
 * Curated GIPHY entries are the only provider items that may be
 * calibration-eligible: Mevora explicitly chose this exact media. Items the
 * provider sync pulls in (`ext_giphy_*`) never are.
 */
export type CuratedGiphyEntry = {
  /** Always `curatedGiphyContentId(giphyId)`. */
  contentId: string;
  giphyId: string;
  /** Anchor slot this clip can fill; omitted means adaptive/exploration only. */
  slot?: string;
  /** False keeps a curated clip out of calibration (ordinary feed only). */
  calibrationEligible: boolean;
  category: HumorCategory;
  humorTags?: string[];
  humorVector: Partial<HumorVector>;
  language: "tr" | "en";
  caption: string | null;
  media: {
    /** Animated rendition: `giphyStableWebpUrl(id)` or the harvested rendition. */
    downloadUrl: string;
    /** A still of the same item. */
    thumbUrl: string;
    aspectRatio: number | null;
  };
  attribution: HumorAttribution;
  sourceTrust: "curated";
};

/** A reviewed clip as the curator recorded it. */
type CuratedClip = {
  giphyId: string;
  slot?: string;
  category: HumorCategory;
  humorVector: Partial<HumorVector>;
  language: "tr" | "en";
  /** The harvested rendition (WebP/GIF of at most 1.5 MB), else `giphyStableWebpUrl`. */
  downloadUrl: string;
  /** `giphyStableStillUrl`, else the harvested still. */
  thumbUrl: string;
  /** Width / height of `downloadUrl`. */
  aspectRatio: number;
  credit: {displayName: string | null; username: string | null; verified: boolean};
  sourceUrl: string;
};

/**
 * Every curated clip is calibration content (anchor or open pool) and has no
 * caption: the joke is in the clip.
 */
function gif(clip: CuratedClip): CuratedGiphyEntry {
  return {
    contentId: curatedGiphyContentId(clip.giphyId),
    giphyId: clip.giphyId,
    ...(clip.slot ? {slot: clip.slot} : {}),
    calibrationEligible: true,
    category: clip.category,
    humorVector: clip.humorVector,
    language: clip.language,
    caption: null,
    media: {
      downloadUrl: clip.downloadUrl,
      thumbUrl: clip.thumbUrl,
      aspectRatio: clip.aspectRatio,
    },
    attribution: {
      provider: "giphy",
      displayName: clip.credit.displayName,
      username: clip.credit.username,
      sourceUrl: clip.sourceUrl,
      verified: clip.credit.verified,
    },
    sourceTrust: "curated",
  };
}

/**
 * The curated GIPHY catalogue: 24 anchors (4 per slot) and 12 open-pool clips.
 *
 * Vectors: the clip's own category is its primary dimension (0.78–0.92, which
 * is what an anchor slot measures); a slot's contrast dimension stays low
 * unless the clip clearly carries it; secondaries are flavours genuinely
 * present in the clip and stay below the 0.5 coverage threshold, so an anchor
 * measures exactly its slot and nothing else.
 */
export const CURATED_GIPHY_CATALOG: readonly CuratedGiphyEntry[] = [
  // anchor_wit — sarcasm
  gif({
    giphyId: "MvdaYPuKPMNZRJCl8Z",
    // sarcastic "yeah right" smile
    slot: "anchor_wit",
    category: "sarcasm",
    humorVector: {sarcasm: 0.88, teasing: 0.35, meme: 0.3},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZja2dsMTZvb3A1eWFsYXdwa3IyeGozd2E1YXdzMHV4cnJqZGs3czk4eCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/MvdaYPuKPMNZRJCl8Z/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/MvdaYPuKPMNZRJCl8Z/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Apple TV", username: "AppleTV", verified: true},
    sourceUrl: "https://giphy.com/gifs/AppleTV-MvdaYPuKPMNZRJCl8Z",
  }),
  gif({
    giphyId: "srqiG5lSxGZTaxdld1",
    // deadpan "Fantastic."
    slot: "anchor_wit",
    category: "sarcasm",
    humorVector: {sarcasm: 0.84, dry: 0.4, situational: 0.3},
    language: "en",
    downloadUrl:
      "https://media0.giphy.com/media/v1.Y2lkPTNjNWVkMzZja2dsMTZvb3A1eWFsYXdwa3IyeGozd2E1YXdzMHV4cnJqZGs3czk4eCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/srqiG5lSxGZTaxdld1/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/srqiG5lSxGZTaxdld1/giphy_s.gif",
    aspectRatio: 480 / 270,
    credit: {displayName: "Married At First Sight", username: "mafs", verified: true},
    sourceUrl: "https://giphy.com/gifs/mafs-mafsau-mafsaus-mafsaustralia-srqiG5lSxGZTaxdld1",
  }),
  gif({
    giphyId: "kgm8xJCg9lQV6oKkU5",
    // "Uh... Ya think??"
    slot: "anchor_wit",
    category: "sarcasm",
    humorVector: {sarcasm: 0.9, teasing: 0.4},
    language: "en",
    downloadUrl:
      "https://media3.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNjhiYmlqM2FlbnU1ZXRiaWZpcmlpMDlxaDd3MXlveGdlZWFxZnk5bCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/kgm8xJCg9lQV6oKkU5/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/kgm8xJCg9lQV6oKkU5/giphy_s.gif",
    aspectRatio: 400 / 400,
    credit: {displayName: "Bounce", username: "Bounce_TV", verified: true},
    sourceUrl: "https://giphy.com/gifs/Bounce-TV-duh-obviously-ya-think-kgm8xJCg9lQV6oKkU5",
  }),
  gif({
    giphyId: "WcOykop23zlK2dAycY",
    // Turkish "YOK ARTIK!"
    slot: "anchor_wit",
    category: "sarcasm",
    humorVector: {sarcasm: 0.8, situational: 0.35},
    language: "tr",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjcDV0emw0bzkwM2ptb2Z1ZW45anh6OHlzY2ZzOWlvdm1tZm4zc2s1byZlcD12MV9naWZzX3NlYXJjaCZjdD1n/WcOykop23zlK2dAycY/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/WcOykop23zlK2dAycY/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "TRT", username: "trt_network", verified: true},
    sourceUrl: "https://giphy.com/gifs/trt-network-kalk-gidelim-mustafa-ali-dizisi-WcOykop23zlK2dAycY",
  }),
  // anchor_absurd — absurd
  gif({
    giphyId: "37QADdG7V5bo9ToyCX",
    // over-the-top "MAAAGIC!"
    slot: "anchor_absurd",
    category: "absurd",
    humorVector: {absurd: 0.86, silly: 0.35, meme: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjbnF1ZDBkNHd1cTU3cHdicm5lbTFtcmp2dGpqM2s2cWNuaXdnODV5YiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/37QADdG7V5bo9ToyCX/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/37QADdG7V5bo9ToyCX/giphy_s.gif",
    aspectRatio: 500 / 500,
    credit: {displayName: "CBC", username: "cbc", verified: true},
    sourceUrl: "https://giphy.com/gifs/cbc-comedy-cavendish-cbccavendish-37QADdG7V5bo9ToyCX",
  }),
  gif({
    giphyId: "BRBXMLg2n9wzZF5J63",
    // bewildered Turkish drama moment
    slot: "anchor_absurd",
    category: "absurd",
    humorVector: {absurd: 0.8, situational: 0.4},
    language: "tr",
    downloadUrl:
      "https://media3.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNW9kOW43Nzdpend5OHg0MnNmenY3a29qems4NDN1c2czeXZkaWk5byZlcD12MV9naWZzX3NlYXJjaCZjdD1n/BRBXMLg2n9wzZF5J63/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/BRBXMLg2n9wzZF5J63/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "TRT", username: "trt_network", verified: true},
    sourceUrl: "https://giphy.com/gifs/trt-network-trt1-trt-bir-zamanlar-istanbul-BRBXMLg2n9wzZF5J63",
  }),
  gif({
    giphyId: "xT9IgFdfhi8lPMzlbW",
    // surreal melting SpongeBob
    slot: "anchor_absurd",
    category: "absurd",
    humorVector: {absurd: 0.9, meme: 0.4},
    language: "en",
    downloadUrl:
      "https://media0.giphy.com/media/v1.Y2lkPTNjNWVkMzZjejViNjY4enR3NDdkbGVlNjFoeXExOG41dWNkNmJ3d3ZxZXJoM3d5ZyZlcD12MV9naWZzX3NlYXJjaCZjdD1n/xT9IgFdfhi8lPMzlbW/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/xT9IgFdfhi8lPMzlbW/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: null, username: "wolfmask", verified: true},
    sourceUrl: "https://giphy.com/gifs/funny-art-lol-xT9IgFdfhi8lPMzlbW",
  }),
  gif({
    giphyId: "0J2IMMncQPVzY4TOLZ",
    // "WHAT DID I MISS?"
    slot: "anchor_absurd",
    category: "absurd",
    humorVector: {absurd: 0.82, situational: 0.35, meme: 0.3},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjcGE3c2QwcnZhb2ptZ2Fham1obmwwcjQ2cWU5NDY1ZGF5eGl3bmI0OSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/0J2IMMncQPVzY4TOLZ/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/0J2IMMncQPVzY4TOLZ/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Late Night with Seth Meyers", username: "latenightseth", verified: true},
    sourceUrl: "https://giphy.com/gifs/latenightseth-seth-meyers-lnsm-late-night-with-0J2IMMncQPVzY4TOLZ",
  }),
  // anchor_everyday — situational
  gif({
    giphyId: "U5PhYH10hwyvlt3Db3",
    // "My events don't always go as planned..."
    slot: "anchor_everyday",
    category: "situational",
    humorVector: {situational: 0.86, cringe: 0.4, silly: 0.3},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjM28xcjR2ZjY0b2dvM2x3eHJnaG91aHpyajRld21wMzJuZnJzOHd4YiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/U5PhYH10hwyvlt3Db3/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/U5PhYH10hwyvlt3Db3/giphy_s.gif",
    aspectRatio: 480 / 274,
    credit: {displayName: "I'm So Jonathan", username: "imsojonathan", verified: true},
    sourceUrl: "https://giphy.com/gifs/imsojonathan-fail-epic-jonathan-fernandez-U5PhYH10hwyvlt3Db3",
  }),
  gif({
    giphyId: "Beng9YrOPhGaB3m5zO",
    // "What Day?" weekday confusion
    slot: "anchor_everyday",
    category: "situational",
    humorVector: {situational: 0.85, absurd: 0.3},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjM28xcjR2ZjY0b2dvM2x3eHJnaG91aHpyajRld21wMzJuZnJzOHd4YiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/Beng9YrOPhGaB3m5zO/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/Beng9YrOPhGaB3m5zO/giphy_s.gif",
    aspectRatio: 480 / 320,
    credit: {displayName: "Mike Hitt", username: "metahitt", verified: true},
    sourceUrl: "https://giphy.com/gifs/metahitt-mike-hitt-pittsburgh-pa-lets-make-plans-Beng9YrOPhGaB3m5zO",
  }),
  gif({
    giphyId: "YqnXaLTb68GAJ8ZHFR",
    // office desk frustration
    slot: "anchor_everyday",
    category: "situational",
    humorVector: {situational: 0.88, meme: 0.35},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNng2YXhhNnI2cnNteDMwbW1xcXRzbmR1cG56cHhiOTY1dDNsN2Y3dCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/YqnXaLTb68GAJ8ZHFR/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/YqnXaLTb68GAJ8ZHFR/giphy_s.gif",
    aspectRatio: 480 / 270,
    credit: {displayName: "Robert E Blackmon", username: "RobertEBlackmon", verified: true},
    sourceUrl: "https://giphy.com/gifs/RobertEBlackmon-reactions-calculator-expense-report-YqnXaLTb68GAJ8ZHFR",
  }),
  gif({
    giphyId: "oStoEt37xFJvlSV2fK",
    // "Super casual, right?!"
    slot: "anchor_everyday",
    category: "situational",
    humorVector: {situational: 0.83, cringe: 0.4, sarcasm: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjZmhqaGcxOGtsc2N5MmJiZWwyYWp0eTV3aW13aHBuMGVtYWdveWJpMyZlcD12MV9naWZzX3NlYXJjaCZjdD1n/oStoEt37xFJvlSV2fK/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/oStoEt37xFJvlSV2fK/giphy_s.gif",
    aspectRatio: 480 / 271,
    credit: {displayName: "Big Brother", username: "bigbrother", verified: true},
    sourceUrl: "https://giphy.com/gifs/bigbrother-big-brother-bb23-season-23-oStoEt37xFJvlSV2fK",
  }),
  // anchor_meme — meme
  gif({
    giphyId: "d3mlE7uhX8KFgEmY",
    // Roll Safe classic meme
    slot: "anchor_meme",
    category: "meme",
    humorVector: {meme: 0.92, absurd: 0.35},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjaDg4aDZua3ozOXVuNjI5aGpuMnVvcWdxOHRnNG9vczExbjBtdDExZiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/d3mlE7uhX8KFgEmY/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/d3mlE7uhX8KFgEmY/giphy_s.gif",
    aspectRatio: 480 / 264,
    credit: {displayName: "Identity", username: "Identity", verified: true},
    sourceUrl: "https://giphy.com/gifs/culture--think-hmm-d3mlE7uhX8KFgEmY",
  }),
  gif({
    giphyId: "l3q2K5jinAlChoCLS",
    // blinking guy classic meme
    slot: "anchor_meme",
    category: "meme",
    humorVector: {meme: 0.9, sarcasm: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjaDg4aDZua3ozOXVuNjI5aGpuMnVvcWdxOHRnNG9vczExbjBtdDExZiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/l3q2K5jinAlChoCLS/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/l3q2K5jinAlChoCLS/giphy_s.gif",
    aspectRatio: 195 / 229,
    credit: {displayName: "Mashable", username: "mashable", verified: true},
    sourceUrl: "https://giphy.com/gifs/mashable-l3q2K5jinAlChoCLS",
  }),
  gif({
    giphyId: "pUeXcg80cO8I8",
    // popcorn classic meme
    slot: "anchor_meme",
    category: "meme",
    humorVector: {meme: 0.88, teasing: 0.35},
    language: "en",
    downloadUrl:
      "https://media3.giphy.com/media/v1.Y2lkPTNjNWVkMzZjaDg4aDZua3ozOXVuNjI5aGpuMnVvcWdxOHRnNG9vczExbjBtdDExZiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/pUeXcg80cO8I8/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/pUeXcg80cO8I8/giphy_s.gif",
    aspectRatio: 267 / 200,
    credit: {displayName: null, username: null, verified: false},
    sourceUrl: "https://giphy.com/gifs/michael-jackson-comments-popcorn-pUeXcg80cO8I8",
  }),
  gif({
    giphyId: "ReyD2H8zfGPswW3fdA",
    // "YOU ARE NOT THE FATHER" meme
    slot: "anchor_meme",
    category: "meme",
    humorVector: {meme: 0.86, cringe: 0.4},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNHdsOTNhcGlxeTZuNnU2dGxrNGxtNjhjaHE2dTk5dzVucjZyZDNncSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/ReyD2H8zfGPswW3fdA/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/ReyD2H8zfGPswW3fdA/giphy_s.gif",
    aspectRatio: 480 / 270,
    credit: {displayName: "Robert E Blackmon", username: "RobertEBlackmon", verified: true},
    sourceUrl: "https://giphy.com/gifs/RobertEBlackmon-maury-the-show-not-father-ReyD2H8zfGPswW3fdA",
  }),
  // anchor_wordplay — wordplay
  gif({
    giphyId: "U8GLl0bUYFLZVquOfY",
    // "see what i did there?"
    slot: "anchor_wordplay",
    category: "wordplay",
    humorVector: {wordplay: 0.82, teasing: 0.35},
    language: "en",
    downloadUrl:
      "https://media0.giphy.com/media/v1.Y2lkPTNjNWVkMzZjeXJ6cnV0ZWwwMDIybW0wbWJydWR0YjdtMjFsYmJiNGVwbWl3MGIwayZlcD12MV9naWZzX3NlYXJjaCZjdD1n/U8GLl0bUYFLZVquOfY/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/U8GLl0bUYFLZVquOfY/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "CBC", username: "cbc", verified: true},
    sourceUrl: "https://giphy.com/gifs/cbc-U8GLl0bUYFLZVquOfY",
  }),
  gif({
    giphyId: "aHmquP8GsDCHS",
    // "What do you call a pile of cats? A meowtain"
    slot: "anchor_wordplay",
    category: "wordplay",
    humorVector: {wordplay: 0.9, silly: 0.4},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjcXI1b2Z6ZzE5NDg3aG9hd2IyYXFmc2ZycGgzcGthZThkdHExcjE0NyZlcD12MV9naWZzX3NlYXJjaCZjdD1n/aHmquP8GsDCHS/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/aHmquP8GsDCHS/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Michelle Porucznik", username: "porucz", verified: true},
    sourceUrl: "https://giphy.com/gifs/porucz-art-michelle-porucznik-dad-jokes-aHmquP8GsDCHS",
  }),
  gif({
    giphyId: "bwgdr1Xi3AKX86O5Oq",
    // "Such a free spirit. No pun intended."
    slot: "anchor_wordplay",
    category: "wordplay",
    humorVector: {wordplay: 0.86, dark: 0.3},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjcGFxcDcyeWVkbTlmdjF2cXhvM2Rhd3J6dTZhNnl3ZGo2NnRuYXkxbyZlcD12MV9naWZzX3NlYXJjaCZjdD1n/bwgdr1Xi3AKX86O5Oq/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/bwgdr1Xi3AKX86O5Oq/giphy_s.gif",
    aspectRatio: 480 / 269,
    credit: {displayName: "CBS", username: "cbs", verified: true},
    sourceUrl: "https://giphy.com/gifs/cbs-ghosts-ghostscbs-cbs-bwgdr1Xi3AKX86O5Oq",
  }),
  gif({
    giphyId: "VNeFpBkw9W3w8ulfJ9",
    // "Nothing, it just waved!" dad joke
    slot: "anchor_wordplay",
    category: "wordplay",
    humorVector: {wordplay: 0.88, silly: 0.45},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjeXJ6cnV0ZWwwMDIybW0wbWJydWR0YjdtMjFsYmJiNGVwbWl3MGIwayZlcD12MV9naWZzX3NlYXJjaCZjdD1n/VNeFpBkw9W3w8ulfJ9/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/VNeFpBkw9W3w8ulfJ9/giphy_s.gif",
    aspectRatio: 320 / 320,
    credit: {displayName: "Timmy. ID", username: "timpoulton", verified: true},
    sourceUrl: "https://giphy.com/gifs/dad-joke-timpoulton-tim-poulton-VNeFpBkw9W3w8ulfJ9",
  }),
  // anchor_social — cringe
  gif({
    giphyId: "fXjdpSAXKfyw3yvVQh",
    // "SECOND-HAND EMBARRASSMENT"
    slot: "anchor_social",
    category: "cringe",
    humorVector: {cringe: 0.9, situational: 0.35},
    language: "en",
    downloadUrl:
      "https://media0.giphy.com/media/v1.Y2lkPTNjNWVkMzZjYjF3eXcxODUzc2s3dDUyNzJmNTF6eXprMG03dHd4YzJ1d2pmbHcxcCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/fXjdpSAXKfyw3yvVQh/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/fXjdpSAXKfyw3yvVQh/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Ryn Dean", username: "ryndean", verified: true},
    sourceUrl: "https://giphy.com/gifs/ryndean-why-did-you-do-that-are-the-way-fXjdpSAXKfyw3yvVQh",
  }),
  gif({
    giphyId: "1DGh2Kduf58TzskEh8",
    // "What an embarrassment."
    slot: "anchor_social",
    category: "cringe",
    humorVector: {cringe: 0.82, dry: 0.35},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjYjF3eXcxODUzc2s3dDUyNzJmNTF6eXprMG03dHd4YzJ1d2pmbHcxcCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/1DGh2Kduf58TzskEh8/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/1DGh2Kduf58TzskEh8/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Shogun FX", username: "ShogunFX", verified: true},
    sourceUrl: "https://giphy.com/gifs/ShogunFX-1DGh2Kduf58TzskEh8",
  }),
  gif({
    giphyId: "2kL6Xn1yfwFg62ApII",
    // "OH MY GOD I'M SWEATING JUST THINKING ABOUT IT"
    slot: "anchor_social",
    category: "cringe",
    humorVector: {cringe: 0.86, situational: 0.4},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjYjF3eXcxODUzc2s3dDUyNzJmNTF6eXprMG03dHd4YzJ1d2pmbHcxcCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/2kL6Xn1yfwFg62ApII/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/2kL6Xn1yfwFg62ApII/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "PBS SoCal", username: "PBSSoCal", verified: true},
    sourceUrl: "https://giphy.com/gifs/PBSSoCal-pbssocal-varietystudio-actorsonactors-2kL6Xn1yfwFg62ApII",
  }),
  gif({
    giphyId: "LM2AKwFXf4SPHOUPCn",
    // "...I had second-hand embarrassment"
    slot: "anchor_social",
    category: "cringe",
    humorVector: {cringe: 0.84, situational: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjYjF3eXcxODUzc2s3dDUyNzJmNTF6eXprMG03dHd4YzJ1d2pmbHcxcCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/LM2AKwFXf4SPHOUPCn/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/LM2AKwFXf4SPHOUPCn/giphy_s.gif",
    aspectRatio: 480 / 268,
    credit: {displayName: "NHL", username: "nhl", verified: true},
    sourceUrl: "https://giphy.com/gifs/nhl-paul-bissonnette-first-timers-biz-nasty-LM2AKwFXf4SPHOUPCn",
  }),
  // open pool — silly
  gif({
    giphyId: "3o6ZsTBERbqBTPkRKo",
    // goofy drooling SpongeBob
    category: "silly",
    humorVector: {silly: 0.9, absurd: 0.4},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjaDN0dDNnaGhkbmFpeDhxam9zMXVwbnVmMmdpdW5yMmlqbmNta3Z6byZlcD12MV9naWZzX3NlYXJjaCZjdD1n/3o6ZsTBERbqBTPkRKo/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/3o6ZsTBERbqBTPkRKo/giphy_s.gif",
    aspectRatio: 500 / 281,
    credit: {displayName: "Nickelodeon", username: "nickelodeon", verified: true},
    sourceUrl: "https://giphy.com/gifs/nickelodeon-spongebob-squarepants-goofy-3o6ZsTBERbqBTPkRKo",
  }),
  gif({
    giphyId: "JFtdcCgVSkzEa1lAgR",
    // Friends turkey-head dance
    category: "silly",
    humorVector: {silly: 0.88, absurd: 0.45, meme: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjc3lrdGNnc2wwd3Z2dWxpdXg0ZDV3MXEzbncwcTRnbHRjYzFva3FkbiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/JFtdcCgVSkzEa1lAgR/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/JFtdcCgVSkzEa1lAgR/giphy_s.gif",
    aspectRatio: 480 / 270,
    credit: {displayName: "HBO Max", username: "hbomax", verified: true},
    sourceUrl: "https://giphy.com/gifs/HBOMax-lol-friends-ill-be-there-for-you-JFtdcCgVSkzEa1lAgR",
  }),
  gif({
    giphyId: "lF35CodYKcV4BhpBkD",
    // Turkish sitcom goofy moment
    category: "silly",
    humorVector: {silly: 0.85, situational: 0.35},
    language: "tr",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjc3lrdGNnc2wwd3Z2dWxpdXg0ZDV3MXEzbncwcTRnbHRjYzFva3FkbiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/lF35CodYKcV4BhpBkD/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/lF35CodYKcV4BhpBkD/giphy_s.gif",
    aspectRatio: 480 / 270,
    credit: {displayName: "Show TV", username: "showtv", verified: true},
    sourceUrl: "https://giphy.com/gifs/showtv-kuzey-yildizi-lF35CodYKcV4BhpBkD",
  }),
  // open pool — dry
  gif({
    giphyId: "2cYwWmw2yXdf4MDPHs",
    // "I want to cry but my eyeball is too dry."
    category: "dry",
    humorVector: {dry: 0.85, wordplay: 0.35},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjemxsZjFrbWE2OGU3ZmdoZnMwZWxyZjJ4bTIybmM1bzJ1a3k5djE5NSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/2cYwWmw2yXdf4MDPHs/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/2cYwWmw2yXdf4MDPHs/giphy_s.gif",
    aspectRatio: 480 / 274,
    credit: {displayName: "Apple TV", username: "AppleTV", verified: true},
    sourceUrl: "https://giphy.com/gifs/AppleTV-apple-tv-app-2cYwWmw2yXdf4MDPHs",
  }),
  gif({
    giphyId: "kt3PrO9QV6xMsF67oD",
    // Oscar deadpan (The Office)
    category: "dry",
    humorVector: {dry: 0.9, sarcasm: 0.35},
    language: "en",
    downloadUrl:
      "https://media1.giphy.com/media/v1.Y2lkPTNjNWVkMzZjY2VrZzllY2J1a2ZscXAxYXFuZGw5aGRkam9qZW8ybmNmYXN2bXk5ayZlcD12MV9naWZzX3NlYXJjaCZjdD1n/kt3PrO9QV6xMsF67oD/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/kt3PrO9QV6xMsF67oD/giphy_s.gif",
    aspectRatio: 480 / 400,
    credit: {displayName: "The Office", username: "theoffice", verified: true},
    sourceUrl: "https://giphy.com/gifs/theoffice-episode-1-the-office-tv-kt3PrO9QV6xMsF67oD",
  }),
  // open pool — teasing
  gif({
    giphyId: "Xoz7C9PpMmp701d28v",
    // "I'M SORRY, DID SOMEONE LOSE THEIR CHILD?" (Kevin Hart)
    category: "teasing",
    humorVector: {teasing: 0.88, silly: 0.35},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjOG5rb25kZGFzcmNuaWxrNnJtZmw1bjJxc2dnOWc0czd4YW1haGZ2byZlcD12MV9naWZzX3NlYXJjaCZjdD1n/Xoz7C9PpMmp701d28v/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/Xoz7C9PpMmp701d28v/giphy_s.gif",
    aspectRatio: 500 / 268,
    credit: {displayName: "The Tonight Show Starring Jimmy Fallon", username: "fallontonight", verified: true},
    sourceUrl: "https://giphy.com/gifs/fallontonight-jimmy-fallon-tonight-show-kevin-hart-Xoz7C9PpMmp701d28v",
  }),
  gif({
    giphyId: "Ke2KBmPiwWmH0ZKgHl",
    // "ROASTED"
    category: "teasing",
    humorVector: {teasing: 0.9, meme: 0.4},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNHBvZmM5OGwxN2ZtaGlwbjdjZGt0bGxrbGVyYXJ1ZGIzeWRsendtcCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/Ke2KBmPiwWmH0ZKgHl/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/Ke2KBmPiwWmH0ZKgHl/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Death Wish Coffee", username: "deathwishcoffee", verified: true},
    sourceUrl: "https://giphy.com/gifs/deathwishcoffee-roasted-deathwish-death-wish-coffee-Ke2KBmPiwWmH0ZKgHl",
  }),
  gif({
    giphyId: "3ohs7V0MMoyuPsWUkU",
    // "Straight gangsta!"
    category: "teasing",
    humorVector: {teasing: 0.8, silly: 0.35, meme: 0.3},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNnhkNm9jM2M1bHQ5NWVvdTlrYXp2NmRncXJ5Yzl3bHRkbWRjemc1bCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/3ohs7V0MMoyuPsWUkU/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/3ohs7V0MMoyuPsWUkU/giphy_s.gif",
    aspectRatio: 500 / 280,
    credit: {displayName: "VH1", username: "vh1", verified: true},
    sourceUrl: "https://giphy.com/gifs/vh1-martha-snoop-3ohs7V0MMoyuPsWUkU",
  }),
  // open pool — romantic
  gif({
    giphyId: "RG4Zzpk8aqkQdDEiPd",
    // Barney flirting (HIMYM)
    category: "romantic",
    humorVector: {romantic: 0.84, teasing: 0.4},
    language: "en",
    downloadUrl:
      "https://media4.giphy.com/media/v1.Y2lkPTNjNWVkMzZjMG1vdXN5ZDVvY2wwNjhleWd5c3d0a3J1bmcwZjB2bHFjNzdtbHF1NSZlcD12MV9naWZzX3NlYXJjaCZjdD1n/RG4Zzpk8aqkQdDEiPd/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/RG4Zzpk8aqkQdDEiPd/giphy_s.gif",
    aspectRatio: 400 / 400,
    credit: {displayName: "Laff", username: "laff_tv", verified: true},
    sourceUrl: "https://giphy.com/gifs/laff-tv-himym-how-i-met-your-mother-sitcom-RG4Zzpk8aqkQdDEiPd",
  }),
  gif({
    giphyId: "5tmS2ZkdusAYme2hd1",
    // Alexis wink (Schitt's Creek)
    category: "romantic",
    humorVector: {romantic: 0.8, teasing: 0.35, silly: 0.3},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNHkzYTNweWR1N2hscWI5OGQyMDAxaGM2aXVlZTRyZ29kdTNtZnVlNiZlcD12MV9naWZzX3NlYXJjaCZjdD1n/5tmS2ZkdusAYme2hd1/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/5tmS2ZkdusAYme2hd1/giphy_s.gif",
    aspectRatio: 480 / 480,
    credit: {displayName: "Schitt's Creek", username: "schittscreek", verified: true},
    sourceUrl: "https://giphy.com/gifs/schittscreek-schitts-creek-poptv-5tmS2ZkdusAYme2hd1",
  }),
  // open pool — dark
  gif({
    giphyId: "BRErszG4ZIZPn0CYmG",
    // "That took a dark turn."
    category: "dark",
    humorVector: {dark: 0.82, dry: 0.35},
    language: "en",
    downloadUrl:
      "https://media3.giphy.com/media/v1.Y2lkPTNjNWVkMzZjd3VtOG0zdjRpbzByNG1ndWw0cWJqZ2U1eXF3aXVrMW9rdjdldjFqZCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/BRErszG4ZIZPn0CYmG/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/BRErszG4ZIZPn0CYmG/giphy_s.gif",
    aspectRatio: 480 / 268,
    credit: {displayName: "CBS", username: "cbs", verified: true},
    sourceUrl: "https://giphy.com/gifs/cbs-ghostscbs-ghosts-cbs-cbsghosts-BRErszG4ZIZPn0CYmG",
  }),
  gif({
    giphyId: "XOrDspslyBAT7bH60s",
    // "I never said everything goes your way."
    category: "dark",
    humorVector: {dark: 0.78, dry: 0.4, sarcasm: 0.3},
    language: "en",
    downloadUrl:
      "https://media2.giphy.com/media/v1.Y2lkPTNjNWVkMzZjNmZzMGVvajU4eGhkaTZtMWtueGVkdHp1ZzRhYW1ncmh2NGNsbnhvdCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/XOrDspslyBAT7bH60s/giphy.webp",
    thumbUrl: "https://media.giphy.com/media/XOrDspslyBAT7bH60s/giphy_s.gif",
    aspectRatio: 500 / 281,
    credit: {displayName: "Apple TV", username: "AppleTV", verified: true},
    sourceUrl: "https://giphy.com/gifs/AppleTVPlus-apple-tv-shrinking-XOrDspslyBAT7bH60s",
  }),
];

/**
 * Which catalogue calibration runs on. The text-joke catalogue is retired:
 * the seeders write the curated GIPHY items and retire the text documents.
 */
export type CalibrationCatalogKind = "curated_giphy";

export const ACTIVE_CALIBRATION_CATALOG: CalibrationCatalogKind = "curated_giphy";

/** The upsert a curated GIPHY entry is written with. */
export function curatedGiphyUpsertInput(entry: CuratedGiphyEntry): UpsertHumorContentInput {
  return {
    contentId: entry.contentId,
    // A GIF is an animated image, shown like any provider GIF.
    type: "meme",
    language: entry.language,
    category: entry.category,
    humorTags: entry.humorTags ?? [],
    humorVector: entry.humorVector,
    media: {
      downloadUrl: entry.media.downloadUrl,
      thumbUrl: entry.media.thumbUrl,
      durationMs: null,
      aspectRatio: entry.media.aspectRatio,
      // GIPHY's own cleaned title, or nothing.
      textBody: entry.caption,
    },
    safetyStatus: "approved",
    active: true,
    sourceType: "licensed_api",
    provider: "giphy",
    licenseRef: entry.attribution.sourceUrl,
    calibration: entry.calibrationEligible
      ? {eligible: true, slot: entry.slot ?? null, version: HUMOR_CALIBRATION_VERSION}
      : {eligible: false},
    sourceTrust: "curated",
    curatedCatalogEntry: true,
    attribution: entry.attribution,
    sourceId: entry.giphyId,
    sourceUrl: entry.attribution.sourceUrl,
  };
}

/** A catalogue item exactly as the seeders write it, with explicit curation. */
export type CalibrationSeedEntry = Omit<UpsertHumorContentInput, "calibration"> & {
  calibration: {eligible: boolean; slot: string | null; version: number};
};

/** The active calibration catalogue as upserts, anchors first. */
export const CALIBRATION_SEED: readonly CalibrationSeedEntry[] = CURATED_GIPHY_CATALOG.map(
  (entry) => ({
    ...curatedGiphyUpsertInput(entry),
    calibration: {
      eligible: entry.calibrationEligible,
      slot: entry.calibrationEligible ? entry.slot ?? null : null,
      version: HUMOR_CALIBRATION_VERSION,
    },
  }),
);

export const ANCHOR_SEED_IDS: readonly string[] = CALIBRATION_SEED.filter(
  (item) => item.calibration.slot !== null,
).map((item) => item.contentId);

/** Candidates per anchor slot, for pool-health reporting and tests. */
export function seedAnchorPools(): Map<string, CalibrationSeedEntry[]> {
  const pools = new Map<string, CalibrationSeedEntry[]>();
  for (const slot of ANCHOR_SLOTS) {
    pools.set(slot.id, []);
  }
  for (const item of CALIBRATION_SEED) {
    const slot = item.calibration.slot;
    if (item.calibration.eligible && slot && pools.has(slot)) {
      pools.get(slot)!.push(item);
    }
  }
  return pools;
}
