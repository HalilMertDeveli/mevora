import type {PersonalizationDimension} from "../personalization/config.js";

/**
 * The relationship question bank — the single source of truth for every
 * relationship question Mevora asks. The client renders what the server
 * sends; it never ships its own copy.
 *
 * Every calendar day ALL members get the same 10 questions from this bank,
 * in the same order (see schedule.ts), so answers are directly comparable:
 * member A and member B answering question X with option Y is a real, shared
 * piece of evidence.
 *
 * Identity is stable and machine-readable:
 *   - question ids are semantic and versioned: relationship_<slug>_v<n>
 *   - option ids are semantic slugs, never display text
 * If a question's MEANING changes, add a new id with the next version and
 * retire the old one (active: false). Never change what an existing id means.
 *
 * Each question maps to one compatibility dimension and says how two answers
 * compare:
 *   - exact     the same option agrees, anything else does not
 *   - distance  ordered options; agreement falls with the distance between them
 *   - matrix    explicit agreement for pairs that fit without being identical
 *   - none      an importance question: it sets how much the dimension
 *               matters to the member (declared weight), it is never compared
 *
 * Nothing here diagnoses personality, attachment or mental state, and nothing
 * asks about religion, politics, health or sexuality.
 */

export const LEARNING_CATALOG_VERSION = 2;

/** Questions in every daily set. */
export const DAILY_QUESTION_COUNT = 10;

export type AnswerType = "choice" | "scale";
export type ComparisonType = "exact" | "distance" | "matrix" | "none";

/** Dashboard areas. Communication sits beside the engine dimensions. */
export type LearningCategory =
  | "relationship"
  | "communication"
  | "lifestyle"
  | "values"
  | "humor"
  | "music"
  | "interests";

/** Topic names shared with relationshipCompatibility.ts and the client l10n. */
export type LearningTopic =
  | "communication"
  | "expectations"
  | "personalSpace"
  | "socialLife"
  | "futurePlans"
  | "friendship"
  | "money"
  | "jealousy"
  | "boundaries"
  | "trust"
  | "exes";

export interface LocalizedText {
  tr: string;
  en: string;
}

export interface LearningOption {
  id: string;
  label: LocalizedText;
  /** Position for distance comparison (1..n) and importance level (1..5). */
  value: number;
}

export interface LearningQuestion {
  id: string;
  version: number;
  answerType: AnswerType;
  comparison: ComparisonType;
  dimension: PersonalizationDimension;
  category: LearningCategory;
  topic: LearningTopic | null;
  active: boolean;
  /** Can be scheduled into a daily set. */
  dailyEligible: boolean;
  prompt: LocalizedText;
  options: LearningOption[];
  /** Matrix comparison only: symmetric agreement for non-identical pairs (0..1). */
  matrix?: Array<[string, string, number]>;
}

/** Importance questions set a declared weight; they are the "none" comparison. */
export function isImportanceQuestion(question: LearningQuestion): boolean {
  return question.comparison === "none";
}

type OptionSpec = [id: string, tr: string, en: string];

function options(specs: OptionSpec[]): LearningOption[] {
  return specs.map(([id, tr, en], index) => ({id, label: {tr, en}, value: index + 1}));
}

function question(spec: {
  slug: string;
  version?: number;
  comparison: Exclude<ComparisonType, "none">;
  dimension: PersonalizationDimension;
  category: LearningCategory;
  topic?: LearningTopic | null;
  tr: string;
  en: string;
  options: OptionSpec[];
  matrix?: Array<[string, string, number]>;
}): LearningQuestion {
  const version = spec.version ?? 1;
  return {
    id: `relationship_${spec.slug}_v${version}`,
    version,
    answerType: "choice",
    comparison: spec.comparison,
    dimension: spec.dimension,
    category: spec.category,
    topic: spec.topic ?? null,
    active: true,
    dailyEligible: true,
    prompt: {tr: spec.tr, en: spec.en},
    options: options(spec.options),
    ...(spec.matrix ? {matrix: spec.matrix} : {}),
  };
}

const IMPORTANCE_SCALE: OptionSpec[] = [
  ["not_important", "Hiç önemli değil", "Not important"],
  ["slightly_important", "Biraz", "Slightly"],
  ["moderately_important", "Orta", "Moderately"],
  ["important", "Önemli", "Important"],
  ["very_important", "Çok önemli", "Very important"],
];

function importance(spec: {
  slug: string;
  dimension: PersonalizationDimension;
  category: LearningCategory;
  tr: string;
  en: string;
}): LearningQuestion {
  return {
    id: `relationship_${spec.slug}_v1`,
    version: 1,
    answerType: "scale",
    comparison: "none",
    dimension: spec.dimension,
    category: spec.category,
    topic: null,
    active: true,
    dailyEligible: true,
    prompt: {tr: spec.tr, en: spec.en},
    options: options(IMPORTANCE_SCALE),
  };
}

export const LEARNING_QUESTIONS: readonly LearningQuestion[] = [
  // --- Communication ---------------------------------------------------------
  question({
    slug: "daily_contact", comparison: "distance", dimension: "values", category: "communication", topic: "communication",
    tr: "Partnerinle gün içinde ne sıklıkla haberleşmek istersin?", en: "How often do you want to be in touch during the day?",
    options: [
      ["rarely", "Nadiren, akşam konuşuruz", "Rarely, we talk in the evening"],
      ["few_times", "Günde birkaç kez", "A few times a day"],
      ["often", "Sık sık", "Often"],
      ["all_day", "Gün boyu", "All day long"],
    ],
  }),
  question({
    slug: "conflict_timing", comparison: "matrix", dimension: "values", category: "communication", topic: "communication",
    tr: "Bir tartışmadan sonra hangisi sana daha yakın?", en: "After an argument, which is closer to you?",
    options: [
      ["talk_now", "Hemen konuşmak", "Talking it through right away"],
      ["cool_down_then_talk", "Biraz sakinleşip sonra konuşmak", "Cooling off, then talking"],
      ["depends", "Duruma göre değişir", "It depends"],
    ],
    matrix: [["talk_now", "cool_down_then_talk", 0.5], ["talk_now", "depends", 0.75], ["cool_down_then_talk", "depends", 0.75]],
  }),
  question({
    slug: "late_reply", comparison: "distance", dimension: "values", category: "communication", topic: "communication",
    tr: "Mesajına geç cevap gelmesi seni ne kadar rahatsız eder?", en: "How much does a late reply bother you?",
    options: [
      ["not_at_all", "Hiç", "Not at all"],
      ["a_little", "Biraz", "A little"],
      ["quite", "Epey", "Quite a bit"],
      ["a_lot", "Çok", "A lot"],
    ],
  }),
  question({
    slug: "feelings_expression", comparison: "matrix", dimension: "values", category: "communication", topic: "communication",
    tr: "Hislerini genelde nasıl ifade edersin?", en: "How do you usually express your feelings?",
    options: [
      ["say_it", "Açıkça söylerim", "I say them openly"],
      ["show_it", "Davranışlarımla gösteririm", "I show them through actions"],
      ["over_time", "Zamanla açılırım", "I open up over time"],
    ],
    matrix: [["say_it", "show_it", 0.25], ["say_it", "over_time", 0.5], ["show_it", "over_time", 0.5]],
  }),
  question({
    slug: "raising_issues", comparison: "distance", dimension: "values", category: "communication", topic: "communication",
    tr: "Seni rahatsız eden bir şeyi ne zaman dile getirirsin?", en: "When do you bring up something that bothers you?",
    options: [
      ["immediately", "Hemen", "Right away"],
      ["same_day", "Aynı gün içinde", "The same day"],
      ["when_ready", "Hazır hissettiğimde", "When I feel ready"],
      ["rarely", "Pek dile getirmem", "I rarely bring it up"],
    ],
  }),
  question({
    slug: "apart_contact", comparison: "exact", dimension: "values", category: "communication", topic: "communication",
    tr: "Uzaktayken hangisini tercih edersin?", en: "When you're apart, which do you prefer?",
    options: [
      ["voice_call", "Sesli arama", "A voice call"],
      ["video_call", "Görüntülü arama", "A video call"],
      ["texting", "Mesajlaşma", "Texting"],
    ],
  }),
  question({
    slug: "joke_when_tense", comparison: "distance", dimension: "values", category: "communication", topic: "communication",
    tr: "Gergin bir anda espri yapılması…", en: "A joke in a tense moment…",
    options: [
      ["eases_it", "Ortamı yumuşatır", "Eases things"],
      ["depends", "Duruma bağlı", "Depends"],
      ["worsens_it", "Beni daha çok gerer", "Makes it worse"],
    ],
  }),
  question({
    slug: "phones_together", comparison: "distance", dimension: "lifestyle", category: "communication", topic: "communication",
    tr: "Birlikteyken telefonlar…", en: "When you're together, phones…",
    options: [
      ["put_away", "Kenara koyulmalı", "Should be put away"],
      ["sometimes", "Arada bakılabilir", "Can be checked now and then"],
      ["no_issue", "Sorun değil", "Are no problem"],
    ],
  }),

  // --- Relationship expectations and future -----------------------------------
  question({
    slug: "pace", comparison: "distance", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Yeni biriyle işler nasıl ilerlesin?", en: "With someone new, how should things move?",
    options: [
      ["fast", "Hızlı; hissediyorsam beklemem", "Quickly — if I feel it, I don't wait"],
      ["natural", "Doğal akışında", "At their own natural pace"],
      ["slow", "Yavaş ve adım adım", "Slowly, step by step"],
    ],
  }),
  question({
    slug: "exclusivity_timing", comparison: "distance", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Birbirinize özel olmayı ne zaman konuşmak istersin?", en: "When would you talk about being exclusive?",
    options: [
      ["early", "İlk buluşmalarda", "In the first dates"],
      ["few_weeks", "Birkaç hafta içinde", "Within a few weeks"],
      ["when_natural", "Kendiliğinden olunca", "When it happens naturally"],
      ["no_rush", "Acelesi yok", "There's no rush"],
    ],
  }),
  question({
    slug: "future_talk", comparison: "distance", dimension: "relationship", category: "relationship", topic: "futurePlans",
    tr: "Gelecek planlarını konuşmanın doğru zamanı…", en: "The right time to talk about the future is…",
    options: [
      ["from_start", "En baştan", "Right from the start"],
      ["once_close", "Birbirimizi tanıyınca", "Once we know each other"],
      ["live_moment", "Acele yok, anı yaşarım", "No rush, I live in the moment"],
    ],
  }),
  question({
    slug: "marriage_view", comparison: "matrix", dimension: "relationship", category: "relationship", topic: "futurePlans",
    tr: "Evlilik senin için…", en: "Marriage, for you, is…",
    options: [
      ["important_goal", "Önemli bir hedef", "An important goal"],
      ["open_to_it", "Olursa güzel", "Nice if it happens"],
      ["undecided", "Henüz karar vermedim", "Something I haven't decided"],
      ["not_for_me", "Bana göre değil", "Not for me"],
    ],
    matrix: [
      ["important_goal", "open_to_it", 0.5], ["important_goal", "undecided", 0.5], ["important_goal", "not_for_me", 0],
      ["open_to_it", "undecided", 0.75], ["open_to_it", "not_for_me", 0.25], ["undecided", "not_for_me", 0.5],
    ],
  }),
  question({
    slug: "children_view", comparison: "matrix", dimension: "relationship", category: "relationship", topic: "futurePlans",
    tr: "Çocuk sahibi olmak konusunda hangisi sana daha yakın?", en: "About having children, which is closer to you?",
    options: [
      ["want_children", "İstiyorum", "I want children"],
      ["open_to_it", "Açığım", "I'm open to it"],
      ["unsure", "Emin değilim", "I'm not sure"],
      ["dont_want", "İstemiyorum", "I don't want children"],
    ],
    matrix: [
      ["want_children", "open_to_it", 0.5], ["want_children", "unsure", 0.25], ["want_children", "dont_want", 0],
      ["open_to_it", "unsure", 0.75], ["open_to_it", "dont_want", 0.25], ["unsure", "dont_want", 0.5],
    ],
  }),
  question({
    slug: "long_distance", comparison: "distance", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Uzak mesafe ilişki senin için…", en: "A long-distance relationship, for you, is…",
    options: [
      ["possible", "Olabilir", "Possible"],
      ["hard_but_try", "Zor ama denerim", "Hard, but I'd try"],
      ["not_for_me", "Bana göre değil", "Not for me"],
    ],
  }),
  question({
    slug: "moving_in", comparison: "distance", dimension: "relationship", category: "relationship", topic: "futurePlans",
    tr: "Birlikte yaşamak için sana göre doğru zaman…", en: "The right time to move in together is…",
    options: [
      ["few_months", "Birkaç ay yeter", "After a few months"],
      ["after_a_year", "En az bir yıl sonra", "After at least a year"],
      ["after_marriage", "Evlendikten sonra", "After marriage"],
    ],
  }),
  question({
    slug: "affection_style", comparison: "exact", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Sevgini en çok nasıl gösterirsin?", en: "How do you most often show love?",
    options: [
      ["words", "Sözlerle", "With words"],
      ["time", "Birlikte vakit geçirerek", "By spending time together"],
      ["gestures", "Küçük jestlerle", "With small gestures"],
      ["touch", "Dokunarak", "Through touch"],
      ["helping", "Yardım ederek", "By helping out"],
    ],
  }),
  question({
    slug: "public_affection", comparison: "distance", dimension: "relationship", category: "relationship", topic: "boundaries",
    tr: "Toplum içinde sevgi göstermek…", en: "Showing affection in public…",
    options: [
      ["comfortable", "Rahatım", "I'm comfortable with it"],
      ["a_little", "Biraz olabilir", "A little is fine"],
      ["keep_private", "Özelde kalsın", "Better kept private"],
    ],
  }),
  question({
    slug: "surprises", comparison: "distance", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Sürprizler…", en: "Surprises…",
    options: [
      ["love_them", "Bayılırım", "I love them"],
      ["sometimes", "Arada güzel", "Are nice now and then"],
      ["prefer_plans", "Planı bilmek isterim", "I'd rather know the plan"],
    ],
  }),
  question({
    slug: "special_days", comparison: "distance", dimension: "relationship", category: "relationship", topic: "expectations",
    tr: "Özel günleri kutlamak senin için…", en: "Celebrating special days is…",
    options: [
      ["very_important", "Çok önemli", "Very important"],
      ["nice", "Güzel ama şart değil", "Nice, not essential"],
      ["not_important", "Pek önemli değil", "Not important"],
    ],
  }),
  importance({
    slug: "goal_importance", dimension: "relationship", category: "relationship",
    tr: "Aynı ilişki hedefini paylaşmanız ne kadar önemli?", en: "How much does sharing the same relationship goal matter?",
  }),

  // --- Personal space, trust and boundaries (values) -------------------------
  question({
    slug: "togetherness_balance", comparison: "distance", dimension: "values", category: "values", topic: "personalSpace",
    tr: "İlişkide ideal denge sence hangisi?", en: "What's the ideal balance in a relationship?",
    options: [
      ["mostly_together", "Çoğu şeyi birlikte yapmak", "Doing most things together"],
      ["together_with_space", "Birlikte ama herkesin kendi alanı olsun", "Together, with room for our own space"],
      ["independence_first", "Bağımsızlık önce gelir", "Independence comes first"],
    ],
  }),
  question({
    slug: "alone_time", comparison: "distance", dimension: "values", category: "values", topic: "personalSpace",
    tr: "Kendine ayırdığın zamana ne sıklıkla ihtiyaç duyarsın?", en: "How often do you need time for yourself?",
    options: [
      ["often", "Sık sık", "Often"],
      ["sometimes", "Ara sıra", "Sometimes"],
      ["rarely", "Nadiren", "Rarely"],
    ],
  }),
  question({
    slug: "phone_privacy", comparison: "distance", dimension: "values", category: "values", topic: "trust",
    tr: "Partnerlerin birbirinin telefonuna bakması…", en: "Partners looking at each other's phones…",
    options: [
      ["fine", "Sorun değil", "Is fine"],
      ["ask_first", "Sorulursa olur", "Is fine if you ask"],
      ["private", "Telefon kişiseldir", "A phone is private"],
    ],
  }),
  question({
    slug: "friends_one_on_one", comparison: "distance", dimension: "values", category: "values", topic: "jealousy",
    tr: "Partnerinin yakın arkadaşlarıyla baş başa vakit geçirmesi…", en: "Your partner spending one-on-one time with close friends…",
    options: [
      ["no_problem", "Hiç sorun değil", "Is no problem at all"],
      ["depends", "Duruma göre", "Depends"],
      ["uncomfortable", "Beni rahatsız eder", "Makes me uncomfortable"],
    ],
  }),
  question({
    slug: "jealousy_view", comparison: "distance", dimension: "values", category: "values", topic: "jealousy",
    tr: "Biraz kıskançlık bir ilişkide…", en: "A little jealousy in a relationship is…",
    options: [
      ["sweet", "Tatlıdır", "Sweet"],
      ["normal", "Normaldir", "Normal"],
      ["pushes_away", "Beni uzaklaştırır", "Something that pushes me away"],
    ],
  }),
  question({
    slug: "social_media_sharing", comparison: "distance", dimension: "values", category: "values", topic: "boundaries",
    tr: "İlişkini sosyal medyada paylaşmak…", en: "Sharing your relationship on social media…",
    options: [
      ["love_to", "Severim", "I like to"],
      ["sometimes", "Arada bir", "Now and then"],
      ["keep_private", "Özel tutarım", "I keep it private"],
    ],
  }),
  question({
    slug: "exes_friendship", comparison: "distance", dimension: "values", category: "values", topic: "exes",
    tr: "Eski sevgililerle arkadaş kalmak…", en: "Staying friends with exes…",
    options: [
      ["fine", "Sorun değil", "Is fine"],
      ["depends", "Duruma göre", "Depends"],
      ["not_ok", "Bana göre değil", "Isn't for me"],
    ],
  }),
  question({
    slug: "honesty_style", comparison: "distance", dimension: "values", category: "values", topic: "trust",
    tr: "Zor bir konuda hangisi sana daha yakın?", en: "On a hard topic, which is closer to you?",
    options: [
      ["blunt", "Kırıcı olsa da tam dürüstlük", "Full honesty, even if it stings"],
      ["honest_gentle", "Dürüst ama incelikli", "Honest, but gentle"],
      ["gentle_first", "Önce incelik", "Gentleness first"],
    ],
  }),
  question({
    slug: "decision_making", comparison: "distance", dimension: "values", category: "values", topic: "expectations",
    tr: "Önemli kararlar bir ilişkide nasıl alınmalı?", en: "How should big decisions be made in a relationship?",
    options: [
      ["always_together", "Her şeyi birlikte", "Always together"],
      ["mostly_together", "Çoğunu birlikte", "Mostly together"],
      ["own_areas", "Herkes kendi alanında", "Each in their own area"],
    ],
  }),
  question({
    slug: "household_split", comparison: "matrix", dimension: "values", category: "values", topic: "expectations",
    tr: "Ev işleri nasıl paylaşılmalı?", en: "How should chores be shared?",
    options: [
      ["equally", "Eşit", "Equally"],
      ["by_preference", "Kim neyi seviyorsa", "By who likes what"],
      ["by_time", "Kimin vakti varsa", "By who has time"],
    ],
    matrix: [["equally", "by_preference", 0.5], ["equally", "by_time", 0.5], ["by_preference", "by_time", 0.75]],
  }),
  question({
    slug: "money_sharing", comparison: "matrix", dimension: "values", category: "values", topic: "money",
    tr: "Bir ilişkide ortak harcamalar nasıl olmalı?", en: "How should shared expenses work?",
    options: [
      ["split_equally", "Eşit bölüşülmeli", "Split equally"],
      ["by_income", "Gelire göre", "According to income"],
      ["whoever_can", "Kim o an ödeyebilirse", "Whoever can at the time"],
    ],
    matrix: [["split_equally", "by_income", 0.5], ["split_equally", "whoever_can", 0.25], ["by_income", "whoever_can", 0.75]],
  }),
  question({
    slug: "money_approach", comparison: "distance", dimension: "values", category: "values", topic: "money",
    tr: "Paraya yaklaşımın hangisine daha yakın?", en: "Your approach to money is closer to…",
    options: [
      ["saver", "Biriktiririm", "Saving"],
      ["balanced", "Dengeli", "Balanced"],
      ["spender", "Anı yaşar, harcarım", "Living in the moment"],
    ],
  }),
  question({
    slug: "family_involvement", comparison: "distance", dimension: "values", category: "values", topic: "boundaries",
    tr: "Ailenin ilişkine dahil olması…", en: "Your family being involved in your relationship…",
    options: [
      ["very_involved", "Çok önemli", "Matters a lot"],
      ["somewhat", "Biraz olmalı", "Should be a little"],
      ["separate", "Ayrı tutarım", "I keep them separate"],
    ],
  }),
  question({
    slug: "career_centrality", comparison: "distance", dimension: "values", category: "values", topic: "expectations",
    tr: "Kariyer hedeflerin hayatında ne kadar merkezde?", en: "How central are career goals in your life?",
    options: [
      ["central", "Çok merkezde", "Very central"],
      ["important", "Önemli", "Important"],
      ["secondary", "Geri planda", "In the background"],
    ],
  }),
  question({
    slug: "traditions", comparison: "distance", dimension: "values", category: "values", topic: null,
    tr: "Gelenekler ve bayramlar senin için…", en: "Traditions and holidays are…",
    options: [
      ["very_important", "Çok önemli", "Very important"],
      ["somewhat", "Biraz önemli", "Somewhat important"],
      ["not_much", "Pek önemli değil", "Not very important"],
    ],
  }),
  importance({
    slug: "values_importance", dimension: "values", category: "values",
    tr: "Hayata ve ilişkilere benzer bakmanız ne kadar önemli?", en: "How much does seeing life the same way matter?",
  }),

  // --- Lifestyle and social life ---------------------------------------------
  question({
    slug: "free_evening", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "socialLife",
    tr: "Boş bir akşamı en çok nasıl geçirirsin?", en: "How do you most like to spend a free evening?",
    options: [
      ["out_with_crowd", "Dışarıda, kalabalıkla", "Out, with a crowd"],
      ["depends", "Duruma göre değişir", "It depends"],
      ["quiet_home", "Sakin; evde ya da birkaç kişiyle", "Quietly, at home or with a few people"],
    ],
  }),
  question({
    slug: "weekend_style", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "socialLife",
    tr: "İdeal hafta sonu…", en: "The ideal weekend is…",
    options: [
      ["busy", "Dolu dolu plan", "Full of plans"],
      ["mix", "Biraz plan, biraz dinlenme", "Some plans, some rest"],
      ["rest", "Tamamen dinlenme", "All rest"],
    ],
  }),
  question({
    slug: "plans_or_spontaneous", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "socialLife",
    tr: "Planlar konusunda hangisi sana daha yakın?", en: "Which is closer to you when it comes to plans?",
    options: [
      ["plan_ahead", "Önceden planlamayı severim", "I like planning ahead"],
      ["mix", "Biraz plan, biraz sürpriz", "A bit of both"],
      ["spontaneous", "Anlık kararlar daha keyifli", "Spur of the moment is more fun"],
    ],
  }),
  question({
    slug: "friends_circle", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "friendship",
    tr: "Partnerinin arkadaşlarınla vakit geçirmesi…", en: "Your partner spending time with your friends is…",
    options: [
      ["very_important", "Benim için çok önemli", "Very important to me"],
      ["sometimes", "Ara sıra yeterli", "Nice now and then"],
      ["separate", "Ayrı çevrelerimiz olabilir", "We can keep separate circles"],
    ],
  }),
  question({
    slug: "nights_out", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "socialLife",
    tr: "Haftada kaç akşam dışarıda olmayı seversin?", en: "How many evenings a week do you like going out?",
    options: [
      ["rarely", "Nadiren", "Rarely"],
      ["one_or_two", "Bir iki akşam", "One or two"],
      ["three_plus", "Üç ya da daha fazla", "Three or more"],
    ],
  }),
  question({
    slug: "hosting", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: "socialLife",
    tr: "Evde misafir ağırlamak…", en: "Having people over…",
    options: [
      ["love_it", "Çok severim", "I love it"],
      ["sometimes", "Arada güzel", "Is nice sometimes"],
      ["rarely", "Pek tercih etmem", "Isn't really my thing"],
    ],
  }),
  question({
    slug: "daily_rhythm", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Günün hangi saatinde daha canlısın?", en: "When do you have the most energy?",
    options: [
      ["morning", "Sabahları", "In the morning"],
      ["midday", "Gün ortasında", "Around midday"],
      ["night", "Geceleri", "Late at night"],
    ],
  }),
  question({
    slug: "tidiness", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Ev düzeni konusunda…", en: "When it comes to a tidy home…",
    options: [
      ["very_tidy", "Her şey yerinde olmalı", "Everything has its place"],
      ["in_between", "Arada bir yerdeyim", "Somewhere in between"],
      ["relaxed", "Biraz dağınıklık olabilir", "A little mess is fine"],
    ],
  }),
  question({
    slug: "work_life_balance", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "İş ve özel hayat dengesinde…", en: "Between work and private life…",
    options: [
      ["work_first", "İş öncelikli", "Work comes first"],
      ["balanced", "Dengeli", "Balanced"],
      ["life_first", "Özel hayat öncelikli", "Private life comes first"],
    ],
  }),
  question({
    slug: "active_lifestyle", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Spor ve hareket hayatında ne kadar yer tutuyor?", en: "How big a part of your life is exercise?",
    options: [
      ["a_lot", "Çok", "A big part"],
      ["some", "Biraz", "Some"],
      ["little", "Pek yok", "Not much"],
    ],
  }),
  question({
    slug: "holiday_style", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Tatilde seni en çok ne mutlu eder?", en: "What makes a good holiday for you?",
    options: [
      ["explore", "Yeni şehirler, bol gezmek", "New cities, lots of exploring"],
      ["mix", "Biraz gezi, biraz dinlenme", "A bit of both"],
      ["rest", "Sakin bir yerde dinlenmek", "Resting somewhere quiet"],
    ],
  }),
  question({
    slug: "travel_frequency", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Ne sıklıkla seyahat etmek istersin?", en: "How often do you want to travel?",
    options: [
      ["whenever_possible", "Fırsat buldukça", "Whenever possible"],
      ["few_times_a_year", "Yılda birkaç kez", "A few times a year"],
      ["rarely", "Nadiren", "Rarely"],
    ],
  }),
  question({
    slug: "pets_at_home", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Evde evcil hayvan…", en: "A pet at home…",
    options: [
      ["must", "Olmazsa olmaz", "Is a must"],
      ["open", "Olabilir", "Could be nice"],
      ["rather_not", "Tercih etmem", "I'd rather not"],
    ],
  }),
  question({
    slug: "city_or_nature", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Hangisi sana daha iyi gelir?", en: "What recharges you more?",
    options: [
      ["city", "Şehrin hareketi", "The buzz of the city"],
      ["both", "İkisi de", "Both"],
      ["nature", "Doğa ve sessizlik", "Nature and quiet"],
    ],
  }),
  question({
    slug: "family_visits", comparison: "distance", dimension: "lifestyle", category: "lifestyle", topic: null,
    tr: "Ailenle ne sıklıkla görüşürsün?", en: "How often do you see your family?",
    options: [
      ["several_weekly", "Haftada birkaç kez", "Several times a week"],
      ["weekly", "Haftada bir", "Once a week"],
      ["monthly", "Ayda bir", "Once a month"],
      ["rarely", "Nadiren", "Rarely"],
    ],
  }),
  importance({
    slug: "lifestyle_importance", dimension: "lifestyle", category: "lifestyle",
    tr: "Günlük rutinlerinizin uyuşması ne kadar önemli?", en: "How much does it matter that your routines fit?",
  }),

  // --- Humor --------------------------------------------------------------
  importance({
    slug: "humor_importance", dimension: "humor", category: "humor",
    tr: "Birinin seni güldürebilmesi ne kadar önemli?", en: "How much does it matter that someone makes you laugh?",
  }),
  question({
    slug: "humor_style", comparison: "exact", dimension: "humor", category: "humor", topic: null,
    tr: "Hangi mizah sana daha yakın?", en: "Which kind of humor feels most like you?",
    options: [
      ["absurd", "Absürt ve saçma", "Absurd and silly"],
      ["dry_witty", "İnce ve iğneleyici", "Dry and witty"],
      ["warm", "Sıcak ve içten", "Warm and gentle"],
    ],
  }),
  question({
    slug: "teasing", comparison: "distance", dimension: "humor", category: "humor", topic: null,
    tr: "Tatlı şakalaşmalar bir ilişkide…", en: "Playful teasing in a relationship is…",
    options: [
      ["essential", "Olmazsa olmaz", "Essential"],
      ["sometimes", "Arada güzel", "Nice once in a while"],
      ["not_mine", "Pek bana göre değil", "Not really my thing"],
    ],
  }),
  question({
    slug: "laugh_together", comparison: "exact", dimension: "humor", category: "humor", topic: null,
    tr: "Birlikte en çok neye gülmek istersin?", en: "What would you most like to laugh at together?",
    options: [
      ["everyday_moments", "Günlük hallerimize", "Everyday moments"],
      ["comedy", "Komedi içeriklerine", "Comedy shows and clips"],
      ["teasing_each_other", "Birbirimize takılmaya", "Teasing each other"],
    ],
  }),

  // --- Music ----------------------------------------------------------------
  importance({
    slug: "music_importance", dimension: "music", category: "music",
    tr: "Müzik zevkinizin uyuşması ne kadar önemli?", en: "How much does a shared taste in music matter?",
  }),
  question({
    slug: "music_together", comparison: "exact", dimension: "music", category: "music", topic: null,
    tr: "Birlikte müzik dendiğinde aklına ne gelir?", en: "What does music together look like for you?",
    options: [
      ["concerts", "Konserler ve festivaller", "Concerts and festivals"],
      ["listening_together", "Evde ya da yolda birlikte dinlemek", "Listening together at home or on the road"],
      ["own_playlists", "Herkes kendi listesini dinlesin", "Everyone keeps their own playlist"],
    ],
  }),
  question({
    slug: "music_discovery", comparison: "distance", dimension: "music", category: "music", topic: null,
    tr: "Yeni müzik keşfetmek…", en: "Discovering new music…",
    options: [
      ["constantly", "Sürekli yaptığım bir şey", "Is something I do all the time"],
      ["sometimes", "Arada bir olur", "Happens now and then"],
      ["stick_to_known", "Bildiklerim bana yeter", "I stick with what I know"],
    ],
  }),

  // --- Interests ------------------------------------------------------------
  importance({
    slug: "interests_importance", dimension: "interests", category: "interests",
    tr: "Ortak ilgi alanlarınızın olması ne kadar önemli?", en: "How much do shared interests matter?",
  }),
  question({
    slug: "new_activities", comparison: "distance", dimension: "interests", category: "interests", topic: null,
    tr: "Birlikte yeni bir şey denemek…", en: "Trying something new together…",
    options: [
      ["every_week", "Her hafta olsun", "Every week, please"],
      ["sometimes", "Arada bir güzel", "Is nice once in a while"],
      ["familiar", "Alıştığımız şeyleri severim", "I like our familiar things"],
    ],
  }),
  question({
    slug: "hobbies_shared", comparison: "distance", dimension: "interests", category: "interests", topic: null,
    tr: "Hobilerini partnerinle…", en: "Your hobbies with a partner…",
    options: [
      ["share_all", "Paylaşmak isterim", "I'd love to share them"],
      ["share_some", "Bazılarını paylaşırım", "I'd share some"],
      ["keep_own", "Kendime saklarım", "I keep them to myself"],
    ],
  }),
  question({
    slug: "together_activity", comparison: "exact", dimension: "interests", category: "interests", topic: null,
    tr: "Birlikte en çok ne yapmak istersin?", en: "What would you most like to do together?",
    options: [
      ["events", "Konser ve etkinlikler", "Concerts and events"],
      ["outdoors", "Doğa ve yürüyüş", "Nature and walks"],
      ["food_places", "Yeni mekanlar ve yemek", "New places and food"],
      ["home_films_games", "Evde film ve oyun", "Films and games at home"],
    ],
  }),
  question({
    slug: "learning_together", comparison: "distance", dimension: "interests", category: "interests", topic: null,
    tr: "Birlikte yeni bir şey öğrenmek…", en: "Learning something new together…",
    options: [
      ["love_it", "Harika olur", "Sounds great"],
      ["maybe", "Olabilir", "Could be nice"],
      ["not_needed", "Şart değil", "Isn't necessary"],
    ],
  }),
];

const BY_ID = new Map(LEARNING_QUESTIONS.map((question) => [question.id, question]));

export const LEARNING_QUESTION_ID_PATTERN = /^relationship_[a-z0-9_]{2,60}_v[1-9][0-9]*$/;

export function learningQuestion(id: unknown): LearningQuestion | null {
  if (typeof id !== "string" || !LEARNING_QUESTION_ID_PATTERN.test(id)) return null;
  return BY_ID.get(id) ?? null;
}

/** Every question that may appear in a daily set, in catalog order. */
export function dailyEligibleQuestions(): LearningQuestion[] {
  return LEARNING_QUESTIONS.filter((question) => question.active && question.dailyEligible);
}

/** True when `answerId` is one of an active question's own options. */
export function isValidLearningAnswer(questionId: unknown, answerId: unknown): boolean {
  const question = learningQuestion(questionId);
  return !!question && question.active &&
    question.options.some((option) => option.id === answerId);
}

/** Topic for a shared view, for "why this person" copy. */
export function learningTopicOf(questionId: string): LearningTopic | null {
  const question = BY_ID.get(questionId);
  return question && !isImportanceQuestion(question) ? question.topic : null;
}

/** Whether a stored answer may be compared between two people. */
export function isComparableLearningAnswer(questionId: string, answerId: unknown): boolean {
  const question = BY_ID.get(questionId);
  return !!question && question.active && !isImportanceQuestion(question) &&
    question.options.some((option) => option.id === answerId);
}

/**
 * How well two answers to the same question agree, 0..1, by the question's
 * own rule. Null when the question cannot be compared or either answer is
 * not one of its options.
 */
export function answerAgreement(questionId: string, a: unknown, b: unknown): number | null {
  const question = BY_ID.get(questionId);
  if (!question || !question.active || isImportanceQuestion(question)) return null;
  const optionA = question.options.find((option) => option.id === a);
  const optionB = question.options.find((option) => option.id === b);
  if (!optionA || !optionB) return null;
  if (optionA.id === optionB.id) return 1;
  switch (question.comparison) {
    case "exact":
      return 0;
    case "distance": {
      const span = question.options.length - 1;
      return span <= 0 ? 0 : 1 - Math.abs(optionA.value - optionB.value) / span;
    }
    case "matrix": {
      const pair = (question.matrix ?? []).find(
        ([x, y]) => (x === optionA.id && y === optionB.id) || (x === optionB.id && y === optionA.id),
      );
      return pair ? pair[2] : 0;
    }
    default:
      return null;
  }
}
