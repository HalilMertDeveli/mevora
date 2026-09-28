import {ANCHOR_SLOTS, HUMOR_CALIBRATION_VERSION} from "./calibration.js";
import type {HumorCategory, HumorVector} from "./categories.js";

/**
 * Curated calibration catalog — QA / development tier.
 *
 * This is deliberately *not* a production meme library. It exists so the
 * calibration engine can be exercised end to end with honest vector
 * annotations, and so anchor pools are deep enough to rotate. Production
 * curation is content-ops work; the architecture here is what makes that work
 * possible without touching code.
 *
 * Provenance is explicit: every item below is written with
 * {@link QA_SEED_PROVIDER}, so a production catalog audit can tell curated
 * dev content apart from anything else at a glance.
 *
 * Content integrity: every curated item is ONE coherent, Mevora-authored text
 * joke card — `type: "text"`, no media at all. The catalogue used to attach
 * these captions to unrelated stock media (random picsum photos and four
 * sample clips such as Big Buck Bunny and Sintel), so users saw a grocery
 * joke over a seascape and a fridge joke under a sword fight. A joke and a
 * picture that were never made for each other are not a meme; they are noise
 * that corrupts the very ratings calibration measures. Media humour comes from
 * the licensed provider pipeline (`giphySource.ts`), where the caption is the
 * provider's own title for that exact item — never text we attach.
 *
 * Media fields are present and `null` rather than absent: the seed is written
 * with a merge, and only an explicit null clears the media an older seed left
 * on the same document.
 */

export const QA_SEED_PROVIDER = "mevora-qa-seed";

/** How many interchangeable candidates each anchor slot should have. */
export const ANCHOR_POOL_TARGET = 4;

type SeedMedia = {
  downloadUrl: null;
  thumbUrl: null;
  durationMs: null;
  aspectRatio: null;
  /** The joke itself. */
  textBody: string;
};

type SeedItem = {
  contentId: string;
  type: "text";
  language: string;
  category: HumorCategory;
  humorTags: string[];
  humorVector: Partial<HumorVector>;
  media: SeedMedia;
  /** Anchor slot this item can fill; omitted means adaptive/exploration only. */
  slot?: string;
};

/** A text-only joke card. The text is the whole item. */
function joke(textBody: string): SeedMedia {
  return {
    downloadUrl: null,
    thumbUrl: null,
    durationMs: null,
    aspectRatio: null,
    textBody,
  };
}

/**
 * Anchor candidates, grouped by the slot they fill.
 *
 * Every candidate carries decisive mass on its slot's `primary` dimension —
 * that is the measurement the slot exists to make, and a test enforces it.
 * Candidates deliberately differ in secondary flavour so rotation gives
 * genuinely different content while measuring the same thing.
 *
 * A slot's `contrast` dimension is *not* required here, and should not be:
 * an item that scores high on both sarcasm and dry cannot separate them. The
 * contrast is what the adaptive stage probes afterwards.
 */
const ANCHOR_SEED: readonly SeedItem[] = [
  // anchor_wit — sarcasm
  {
    contentId: "hc_tr_img_001",
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "meme"],
    humorVector: {sarcasm: 0.88, dry: 0.55, teasing: 0.4},
    media: joke("Tabii, trafik yine benim yüzümden oluştu."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_img_006",
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "gunluk"],
    humorVector: {sarcasm: 0.86, dry: 0.5, situational: 0.35},
    media: joke("Harika, tam da bugün bitmesi gereken şey bitmedi."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_img_012",
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi", "toplanti"],
    humorVector: {sarcasm: 0.9, situational: 0.4},
    media: joke("Bu toplantı bir e-posta olabilirdi. Yine oldu."),
    slot: "anchor_wit",
  },
  {
    contentId: "hc_tr_vid_007",
    type: "text",
    language: "tr",
    category: "sarcasm",
    humorTags: ["ironi"],
    humorVector: {sarcasm: 0.85, dry: 0.45},
    media: joke("Tabii ki ilk denemede oldu. Sadece on yedinciydi."),
    slot: "anchor_wit",
  },

  // anchor_absurd — absurd
  {
    contentId: "hc_tr_vid_001",
    type: "text",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt"],
    humorVector: {absurd: 0.85, silly: 0.6, meme: 0.4},
    media: joke("Alarm değil, sabah sabotajı."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_vid_006",
    type: "text",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt"],
    humorVector: {absurd: 0.87, silly: 0.55},
    media: joke("Rüyamda da sıra bekliyordum. Uyanınca da."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_img_013",
    type: "text",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt"],
    humorVector: {absurd: 0.88, silly: 0.5},
    media: joke("Buzdolabına neden geldiğimi hatırlamak için bir kurul topladım."),
    slot: "anchor_absurd",
  },
  {
    contentId: "hc_tr_img_014",
    type: "text",
    language: "tr",
    category: "absurd",
    humorTags: ["absürt", "saçma"],
    humorVector: {absurd: 0.84, wordplay: 0.35},
    media: joke("Takvimime 'düşünmek' yazdım. Düşünemedim, takvim doluydu."),
    slot: "anchor_absurd",
  },

  // anchor_everyday — situational
  {
    contentId: "hc_tr_vid_002",
    type: "text",
    language: "tr",
    category: "situational",
    humorTags: ["günlük"],
    humorVector: {situational: 0.88, dry: 0.45, silly: 0.5},
    media: joke("Buzdolabı yine boş fikirler sunuyor."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_img_007",
    type: "text",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "sosyal"],
    humorVector: {situational: 0.85, cringe: 0.4, dry: 0.35},
    media: joke("Asansörde sohbet başlatan insan türü üzerine bir inceleme."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_img_015",
    type: "text",
    language: "tr",
    category: "situational",
    humorTags: ["günlük", "market"],
    humorVector: {situational: 0.86, meme: 0.35},
    media: joke("Markete süt için girdim, üç poşetle çıktım. Süt yok."),
    slot: "anchor_everyday",
  },
  {
    contentId: "hc_tr_vid_008",
    type: "text",
    language: "tr",
    category: "situational",
    humorTags: ["günlük"],
    humorVector: {situational: 0.83, silly: 0.4},
    media: joke("Beş dakika daha dedim. Öğlen oldu."),
    slot: "anchor_everyday",
  },

  // anchor_meme — meme
  {
    contentId: "hc_tr_vid_004",
    type: "text",
    language: "tr",
    category: "meme",
    humorTags: ["meme"],
    humorVector: {meme: 0.9, situational: 0.6, cringe: 0.25},
    media: joke("Wi‑Fi şifresi kadar karmaşık bir ruh hali."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_008",
    type: "text",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "klasik"],
    humorVector: {meme: 0.88, silly: 0.45},
    media: joke("Bildirimi kapattım, huzur geldi sandım. Gelmedi."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_016",
    type: "text",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "internet"],
    humorVector: {meme: 0.91, absurd: 0.4},
    media: joke("Şarjım %1. Ben de öyle."),
    slot: "anchor_meme",
  },
  {
    contentId: "hc_tr_img_017",
    type: "text",
    language: "tr",
    category: "meme",
    humorTags: ["meme", "pazartesi"],
    humorVector: {meme: 0.85, situational: 0.45},
    media: joke("Pazartesi: bir gün değil, bir ruh hali."),
    slot: "anchor_meme",
  },

  // anchor_wordplay — wordplay
  {
    contentId: "hc_tr_img_002",
    type: "text",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.85, silly: 0.55},
    media: joke("Kahve olmadan ben 'ben' değilim; 'be n'."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_009",
    type: "text",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.87, sarcasm: 0.4},
    media: joke("Planım yoktu ama planım olmadığına dair bir planım vardı."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_018",
    type: "text",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime"],
    humorVector: {wordplay: 0.89, absurd: 0.35},
    media: joke("Uykusuzum ama uyanık da sayılmam. Arada bir yerdeyim: uyanıksız."),
    slot: "anchor_wordplay",
  },
  {
    contentId: "hc_tr_img_019",
    type: "text",
    language: "tr",
    category: "wordplay",
    humorTags: ["kelime", "espri"],
    humorVector: {wordplay: 0.83, silly: 0.4},
    media: joke("Bugün üretken oldum: iki fikir ürettim, ikisi de kötüydü."),
    slot: "anchor_wordplay",
  },

  // anchor_social — cringe
  {
    contentId: "hc_tr_img_004",
    type: "text",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.82, situational: 0.65, silly: 0.4},
    media: joke("Arkandaki kişiye el sallayanı sandım. Klasik."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_010",
    type: "text",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.85, teasing: 0.45, situational: 0.5},
    media: joke("Sesli mesajı yanlış gruba attım. İyi geceler herkese."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_020",
    type: "text",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe"],
    humorVector: {cringe: 0.87, situational: 0.45},
    media: joke("Görüntülü aramada mikrofonum kapalıydı. İki dakika anlattım."),
    slot: "anchor_social",
  },
  {
    contentId: "hc_tr_img_021",
    type: "text",
    language: "tr",
    category: "cringe",
    humorTags: ["cringe", "sosyal"],
    humorVector: {cringe: 0.84, teasing: 0.4},
    media: joke("Tanımadığım birine 'kanka' dedim. Geri alamadım."),
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
    type: "text",
    language: "tr",
    category: "silly",
    humorTags: ["saçma"],
    humorVector: {silly: 0.9, absurd: 0.55, meme: 0.35},
    media: joke("Planım vardı… sonra pazartesi oldu."),
  },
  {
    contentId: "hc_tr_img_003",
    type: "text",
    language: "tr",
    category: "teasing",
    humorTags: ["takılma"],
    humorVector: {teasing: 0.86, romantic: 0.35, silly: 0.45},
    media: joke("Poker suratın tatilde galiba."),
  },
  {
    contentId: "hc_tr_img_022",
    type: "text",
    language: "tr",
    category: "teasing",
    humorTags: ["takılma"],
    humorVector: {teasing: 0.88, cringe: 0.3},
    media: joke("Yol tarifi vermeyi seviyorsun. Doğru olmasını değil."),
  },
  {
    contentId: "hc_tr_img_005",
    type: "text",
    language: "tr",
    category: "dark",
    humorTags: ["kuru", "bitki"],
    humorVector: {dark: 0.68, dry: 0.6, situational: 0.4},
    media: joke("Bitkilerimle karşılıklı ihmal anlaşmamız var."),
  },
  {
    contentId: "hc_tr_img_023",
    type: "text",
    language: "tr",
    category: "dark",
    humorTags: ["kara mizah"],
    humorVector: {dark: 0.82, dry: 0.5},
    media: joke("Emeklilik planım: umut."),
  },
  {
    contentId: "hc_tr_vid_005",
    type: "text",
    language: "tr",
    category: "romantic",
    humorTags: ["romantik", "espri"],
    humorVector: {romantic: 0.75, teasing: 0.5, silly: 0.4},
    media: joke("Sen Wi‑Fi misin? Bağlantı hissediyorum."),
  },
  {
    contentId: "hc_tr_img_024",
    type: "text",
    language: "tr",
    category: "romantic",
    humorTags: ["romantik"],
    humorVector: {romantic: 0.84, wordplay: 0.4},
    media: joke("Kahveni nasıl içersin? Yanımda."),
  },
  {
    contentId: "hc_tr_img_011",
    type: "text",
    language: "tr",
    category: "dry",
    humorTags: ["kuru", "sakin"],
    humorVector: {dry: 0.86, situational: 0.4},
    media: joke("Evet. Güzel. Devam edelim."),
  },
  {
    contentId: "hc_tr_img_025",
    type: "text",
    language: "tr",
    category: "dry",
    humorTags: ["kuru"],
    humorVector: {dry: 0.88},
    media: joke("Heyecanlıyım. Öyle görünmüyor olabilirim."),
  },
  {
    contentId: "hc_tr_img_026",
    type: "text",
    language: "tr",
    category: "silly",
    humorTags: ["saçma"],
    humorVector: {silly: 0.87, absurd: 0.45},
    media: joke("Ördek sesi çıkarabiliyorum. Kimse istemedi."),
  },
  {
    contentId: "hc_en_vid_001",
    type: "text",
    language: "en",
    category: "silly",
    humorTags: ["silly"],
    humorVector: {silly: 0.8, meme: 0.5},
    media: joke("I put my phone on airplane mode. It still refuses to fly."),
  },
  {
    contentId: "hc_en_img_001",
    type: "text",
    language: "en",
    category: "meme",
    humorTags: ["meme"],
    humorVector: {meme: 0.85, situational: 0.5},
    media: joke("Me: I'll just check one thing. Also me, three hours later: still checking."),
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
