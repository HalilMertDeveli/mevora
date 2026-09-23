import {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} from "./calibration.js";
import type {HumorCategory, HumorVector} from "./categories.js";
import type {HumorContentType} from "./types.js";

/**
 * Curated calibration catalog — QA / development tier.
 *
 * This is deliberately *not* a production meme library. It exists so the
 * calibration engine can be exercised end to end with real playable media and
 * honest vector annotations, and so anchor pools are deep enough to rotate.
 * Production curation is content-ops work; the architecture here is what makes
 * that work possible without touching code.
 *
 * Provenance is explicit: every item below is written with
 * {@link QA_SEED_PROVIDER}, so a production catalog audit can tell curated
 * dev content apart from anything else at a glance.
 *
 * Licensing: Mevora-authored Turkish captions over public sample media
 * (Google's public video bucket, picsum). No scraping of TikTok, Instagram,
 * YouTube or any copyrighted source.
 */

export const QA_SEED_PROVIDER = "mevora-qa-seed";

/** How many interchangeable candidates each anchor slot should have. */
export const ANCHOR_POOL_TARGET = 4;

type SeedMedia = {
  downloadUrl: string;
  thumbUrl: string;
  durationMs?: number;
  aspectRatio: number;
  textBody: string;
};

type SeedItem = {
  contentId: string;
  type: HumorContentType;
  language: string;
  category: HumorCategory;
  humorTags: string[];
  humorVector: Partial<HumorVector>;
  media: SeedMedia;
  /** Anchor slot this item can fill; omitted means adaptive/exploration only. */
  slot?: string;
};

const VIDEO_BUCKET =
  "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample";

function clip(name: string, textBody: string, durationMs = 15000): SeedMedia {
  return {
    downloadUrl: `${VIDEO_BUCKET}/${name}.mp4`,
    thumbUrl: `${VIDEO_BUCKET}/images/${name}.jpg`,
    durationMs,
    aspectRatio: 16 / 9,
    textBody,
  };
}

function still(seed: string, textBody: string): SeedMedia {
  return {
    downloadUrl: `https://picsum.photos/seed/${seed}/1080/1920`,
    thumbUrl: `https://picsum.photos/seed/${seed}/540/960`,
    aspectRatio: 9 / 16,
    textBody,
  };
}

/**
 * Anchor candidates, grouped by the slot they fill.
 *
 * Every candidate carries decisive mass on its slot's `primary` dimension —
 * that is the measurement the slot exists to make, and a test enforces it.
 * Candidates deliberately differ in format and secondary flavour so rotation
 * gives genuinely different content while measuring the same thing.
 *
 * A slot's `contrast` dimension is *not* required here, and should not be:
 * an item that scores high on both sarcasm and dry cannot separate them. The
 * contrast is what the adaptive stage probes afterwards.
 */
const ANCHOR_SEED: readonly SeedItem[] = [
  // anchor_wit — sarcasm
  {
    contentId: "hc_tr_img_001",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "meme"],
    humorVector: {sarcasm: 0.88, dry: 0.55, teasing: 0.4},
    media: still("mevora-tr-1", "Tabii, trafik yine benim yüzümden oluştu."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_img_006",
    type: "meme",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "gunluk"],
    humorVector: {sarcasm: 0.86, dry: 0.5, situational: 0.35},
    media: still("mevora-tr-6", "Harika, tam da bugün bitmesi gereken şey bitmedi."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_img_012",
    type: "image",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "toplanti"],
    humorVector: {sarcasm: 0.9, situational: 0.4},
    media: still("mevora-tr-12", "Bu toplantı bir e-posta olabilirdi. Yine oldu."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_vid_007",
    type: "video",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "video"],
    humorVector: {sarcasm: 0.85, dry: 0.45},
    media: clip("TearsOfSteel", "Tabii ki ilk denemede oldu. Sadece on yedinciydi."),
    slot: "anchor_wit",
  },

  // anchor_absurd — absurd
  {
    contentId: "hc_tr_vid_001",
    type: "video",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "video"],
    humorVector: {absurd: 0.85, silly: 0.6, meme: 0.4},
    media: clip("ForBiggerBlazes", "Alarm değil, sabah sabotajı."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_vid_006",
    type: "video",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "video"],
    humorVector: {absurd: 0.87, silly: 0.55},
    media: clip("ElephantsDream", "Rüyamda da sıra bekliyordum. Uyanınca da."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_img_013",
    type: "meme",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt"],
    humorVector: {absurd: 0.88, silly: 0.5},
    media: still("mevora-tr-13", "Buzdolabına neden geldiğimi hatırlamak için bir kurul topladım."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_img_014",
    type: "image",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "saçma"],
    humorVector: {absurd: 0.84, wordplay: 0.35},
    media: still("mevora-tr-14", "Takvimime 'düşünmek' yazdım. Düşünemedim, takvim doluydu."),
    slot: "anchor_absurd",
  },

  // anchor_everyday — situational
  {
    contentId: "hc_tr_vid_002",
    type: "video",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "video"],
    humorVector: {situational: 0.88, dry: 0.45, silly: 0.5},
    media: clip("ForBiggerEscapes", "Buzdolabı yine boş fikirler sunuyor."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_img_007",
    type: "image",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "sosyal"],
    humorVector: {situational: 0.85, cringe: 0.4, dry: 0.35},
    media: still("mevora-tr-7", "Asansörde sohbet başlatan insan türü üzerine bir inceleme."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_img_015",
    type: "meme",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "market"],
    humorVector: {situational: 0.86, meme: 0.35},
    media: still("mevora-tr-15", "Markete süt için girdim, üç poşetle çıktım. Süt yok."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_vid_008",
    type: "video",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "video"],
    humorVector: {situational: 0.83, silly: 0.4},
    media: clip("Sintel", "Beş dakika daha dedim. Öğlen oldu."),
    slot: "anchor_everyday",
  },

  // anchor_meme — meme
  {
    contentId: "hc_tr_vid_004",
    type: "video",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "video"],
    humorVector: {meme: 0.9, situational: 0.6, cringe: 0.25},
    media: clip("ForBiggerJoyrides", "Wi‑Fi şifresi kadar karmaşık bir ruh hali."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_008",
    type: "meme",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "klasik"],
    humorVector: {meme: 0.88, silly: 0.45},
    media: still("mevora-tr-8", "Bildirimi kapattım, huzur geldi sandım. Gelmedi."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_016",
    type: "meme",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "internet"],
    humorVector: {meme: 0.91, absurd: 0.4},
    media: still("mevora-tr-16", "Şarjım %1. Ben de öyle."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_017",
    type: "image",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "pazartesi"],
    humorVector: {meme: 0.85, situational: 0.45},
    media: still("mevora-tr-17", "Pazartesi: bir gün değil, bir ruh hali."),
    slot: "anchor_meme",
  },

  // anchor_wordplay — wordplay
  {
    contentId: "hc_tr_img_002",
    type: "image",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.85, silly: 0.55},
    media: still("mevora-tr-2", "Kahve olmadan ben 'ben' değilim; 'be n'."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_009",
    type: "image",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.87, sarcasm: 0.4},
    media: still("mevora-tr-9", "Planım yoktu ama planım olmadığına dair bir planım vardı."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_018",
    type: "meme",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime"],
    humorVector: {wordplay: 0.89, absurd: 0.35},
    media: still("mevora-tr-18", "Uykusuzum ama uyanık da sayılmam. Arada bir yerdeyim: uyanıksız."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_019",
    type: "image",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.83, silly: 0.4},
    media: still("mevora-tr-19", "Bugün üretken oldum: iki fikir ürettim, ikisi de kötüydü."),
    slot: "anchor_wordplay",
  },

  // anchor_social — cringe
  {
    contentId: "hc_tr_img_004",
    type: "image",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.82, situational: 0.65, silly: 0.4},
    media: still("mevora-tr-4", "Arkandaki kişiye el sallayanı sandım. Klasik."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_010",
    type: "meme",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.85, teasing: 0.45, situational: 0.5},
    media: still("mevora-tr-10", "Sesli mesajı yanlış gruba attım. İyi geceler herkese."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_020",
    type: "meme",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe"],
    humorVector: {cringe: 0.87, situational: 0.45},
    media: still("mevora-tr-20", "Görüntülü aramada mikrofonum kapalıydı. İki dakika anlattım."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_021",
    type: "image",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.84, teasing: 0.4},
    media: still("mevora-tr-21", "Tanımadığım birine 'kanka' dedim. Geri alamadım."),
    slot: "anchor_social",
  },
];

/**
 * Adaptive / exploration pool.
 *
 * No slot, so these can never fill an anchor position. They exist to give the
 * later stages focused candidates for every dimension — especially `teasing`,
 * `romantic` and `dark`, which the anchor stage deliberately does not measure.
 */
const POOL_SEED: readonly SeedItem[] = [
  {
    contentId: "hc_tr_vid_003",
    type: "video",
    language: "tr",
    category: "silly",
    humorTags: ["saçma", "video"],
    humorVector: {silly: 0.9, absurd: 0.55, meme: 0.35},
    media: clip("ForBiggerFun", "Planım vardı… sonra pazartesi oldu.", 60000),
  },
  {
    contentId: "hc_tr_img_003",
    type: "meme",
    language: "tr",
    category: "teasing",
    humorTags: ["takılma"],
    humorVector: {teasing: 0.86, romantic: 0.35, silly: 0.45},
    media: still("mevora-tr-3", "Poker suratın tatilde galiba."),
  },
  {
    contentId: "hc_tr_img_022",
    type: "image",
    language: "tr",
    category: "teasing",
    humorTags: ["takılma"],
    humorVector: {teasing: 0.88, cringe: 0.3},
    media: still("mevora-tr-22", "Yol tarifi vermeyi seviyorsun. Doğru olmasını değil."),
  },
  {
    contentId: "hc_tr_img_005",
    type: "meme",
    language: "tr",
    category: "dark",
    humorTags: ["kuru", "bitki"],
    humorVector: {dark: 0.68, dry: 0.6, situational: 0.4},
    media: still("mevora-tr-5", "Bitkilerimle karşılıklı ihmal anlaşmamız var."),
  },
  {
    contentId: "hc_tr_img_023",
    type: "image",
    language: "tr",
    category: "dark",
    humorTags: ["kara mizah"],
    humorVector: {dark: 0.82, dry: 0.5},
    media: still("mevora-tr-23", "Emeklilik planım: umut."),
  },
  {
    contentId: "hc_tr_vid_005",
    type: "video",
    language: "tr",
    category: "romantic",
    humorTags: ["romantik", "espri"],
    humorVector: {romantic: 0.75, teasing: 0.5, silly: 0.4},
    media: clip("ForBiggerMeltdowns", "Sen Wi‑Fi misin? Bağlantı hissediyorum."),
  },
  {
    contentId: "hc_tr_img_024",
    type: "meme",
    language: "tr",
    category: "romantic",
    humorTags: ["romantik"],
    humorVector: {romantic: 0.84, wordplay: 0.4},
    media: still("mevora-tr-24", "Kahveni nasıl içersin? Yanımda."),
  },
  {
    contentId: "hc_tr_img_011",
    type: "image",
    language: "tr",
    category: "dry",
    humorTags: ["kuru", "sakin"],
    humorVector: {dry: 0.86, situational: 0.4},
    media: still("mevora-tr-11", "Evet. Güzel. Devam edelim."),
  },
  {
    contentId: "hc_tr_img_025",
    type: "image",
    language: "tr",
    category: "dry",
    humorTags: ["kuru"],
    humorVector: {dry: 0.88},
    media: still("mevora-tr-25", "Heyecanlıyım. Öyle görünmüyor olabilirim."),
  },
  {
    contentId: "hc_tr_img_026",
    type: "meme",
    language: "tr",
    category: "silly",
    humorTags: ["saçma"],
    humorVector: {silly: 0.87, absurd: 0.45},
    media: still("mevora-tr-26", "Ördek sesi çıkarabiliyorum. Kimse istemedi."),
  },
  {
    contentId: "hc_en_vid_001",
    type: "video",
    language: "en",
    category: "silly",
    humorTags: ["silly", "fallback"],
    humorVector: {silly: 0.8, meme: 0.5},
    media: clip("BigBuckBunny", "English fallback clip for bilingual users.", 60000),
  },
  {
    contentId: "hc_en_img_001",
    type: "image",
    language: "en",
    category: "meme",
    humorTags: ["meme", "fallback"],
    humorVector: {meme: 0.85, situational: 0.5},
    media: still("mevora-en-1", "English fallback still — TR feed stays primary."),
  },
];

export type CalibrationSeedEntry = SeedItem & {
  calibration: {eligible: true; slot: string | null; version: number};
  provider: string;
  sourceType: "internal";
  active: true;
};

function withCuration(item: SeedItem): CalibrationSeedEntry {
  return {
    ...item,
    calibration: {
      eligible: true,
      slot: item.slot ?? null,
      version: HUMOR_CALIBRATION_VERSION,
    },
    provider: QA_SEED_PROVIDER,
    sourceType: "internal",
    active: true,
  };
}

/** Every curated QA item, anchors first. */
export const CALIBRATION_SEED: readonly CalibrationSeedEntry[] = [
  ...ANCHOR_SEED.map(withCuration),
  ...POOL_SEED.map(withCuration),
];

export const ANCHOR_SEED_IDS: readonly string[] = ANCHOR_SEED.map((i) => i.contentId);

/** Candidates per anchor slot, for pool-health reporting and tests. */
export function seedAnchorPools(): Map<string, CalibrationSeedEntry[]> {
  const pools = new Map<string, CalibrationSeedEntry[]>();
  for (const slot of ANCHOR_SLOTS) {
    pools.set(slot.id, []);
  }
  for (const item of CALIBRATION_SEED) {
    const slot = item.calibration.slot;
    if (slot && pools.has(slot)) {
      pools.get(slot)!.push(item);
    }
  }
  return pools;
}
