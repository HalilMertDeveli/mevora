import type {PersonalizationDimension} from "../personalization/config.js";

/**
 * Relationship Learning — the questions Mevora asks so it can choose better
 * people for someone. This file is the single source of truth: the client
 * renders whatever `getRelationshipLearningState` sends and never ships its
 * own copy, so question text, order and versions cannot drift between the
 * two sides.
 *
 * Two kinds of question:
 *
 *  - `importance`: how much one compatibility dimension matters to the
 *    member. Answers become the member's DECLARED weight for that dimension
 *    (see declared.ts). Never compared between two people.
 *  - `stance`: how the member tends to do something (texting, conflict,
 *    plans...). Answers are compared between two people exactly like the
 *    existing relationship questions — same answer, one more shared view —
 *    and feed the canonical relationship-agreement score.
 *
 * Every question maps to one of the dimensions the compatibility engine
 * already measures. Nothing here diagnoses personality, attachment or mental
 * state, and nothing asks about religion, politics, health or sexuality.
 *
 * Changing a question: keep its id, bump its `version`. Retiring one: set
 * `active: false` (answers stay readable, it is simply never asked again).
 * The initial set must always hold exactly INITIAL_QUESTION_COUNT active
 * questions — catalog tests enforce it.
 */

export const LEARNING_CATALOG_VERSION = 1;
export const INITIAL_QUESTION_COUNT = 15;

export type LearningQuestionKind = "importance" | "stance";
export type LearningStage = "initial" | "progressive";
export type ImportanceLevel = "high" | "medium" | "low";

/** Topic names shared with relationshipCompatibility.ts / the client l10n. */
export type LearningTopic =
  | "communication"
  | "socialLife"
  | "personalSpace"
  | "futurePlans"
  | "friendship"
  | "expectations";

export interface LocalizedText {
  tr: string;
  en: string;
}

export interface LearningOption {
  id: "a" | "b" | "c";
  label: LocalizedText;
  /** Importance questions only. */
  importance?: ImportanceLevel;
}

export interface LearningQuestion {
  id: string;
  version: number;
  kind: LearningQuestionKind;
  dimension: PersonalizationDimension;
  topic: LearningTopic | null;
  stage: LearningStage;
  /** Order inside its stage; also the deterministic tie-break. */
  order: number;
  active: boolean;
  prompt: LocalizedText;
  options: LearningOption[];
}

function importance(
  id: string,
  order: number,
  dimension: PersonalizationDimension,
  prompt: LocalizedText,
  labels: [LocalizedText, LocalizedText, LocalizedText],
): LearningQuestion {
  const levels: ImportanceLevel[] = ["high", "medium", "low"];
  return {
    id,
    version: 1,
    kind: "importance",
    dimension,
    topic: null,
    stage: "initial",
    order,
    active: true,
    prompt,
    options: labels.map((label, index) => ({
      id: (["a", "b", "c"] as const)[index],
      label,
      importance: levels[index],
    })),
  };
}

function stance(
  id: string,
  stage: LearningStage,
  order: number,
  dimension: PersonalizationDimension,
  topic: LearningTopic | null,
  prompt: LocalizedText,
  labels: [LocalizedText, LocalizedText, LocalizedText],
): LearningQuestion {
  return {
    id,
    version: 1,
    kind: "stance",
    dimension,
    topic,
    stage,
    order,
    active: true,
    prompt,
    options: labels.map((label, index) => ({id: (["a", "b", "c"] as const)[index], label})),
  };
}

export const LEARNING_QUESTIONS: readonly LearningQuestion[] = [
  // --- Initial set: exactly 15, every dimension asked about at least once. --
  stance("rl_pace", "initial", 1, "relationship", "expectations",
    {tr: "Yeni biriyle tanışınca işler nasıl ilerlesin?", en: "When you meet someone new, how should things move?"},
    [
      {tr: "Hızlı; hissediyorsam beklemem", en: "Quickly — if I feel it, I don't wait"},
      {tr: "Doğal akışında", en: "At their own natural pace"},
      {tr: "Yavaş ve adım adım", en: "Slowly, one step at a time"},
    ]),
  importance("rl_goal_importance", 2, "relationship",
    {tr: "Aynı ilişki hedefini paylaşmanız ne kadar önemli?", en: "How much does sharing the same relationship goal matter?"},
    [
      {tr: "Olmazsa olmaz", en: "It's a must"},
      {tr: "Önemli ama esneyebilir", en: "Important, but flexible"},
      {tr: "Zamanla netleşir", en: "It becomes clear over time"},
    ]),
  stance("rl_texting", "initial", 3, "values", "communication",
    {tr: "Tanışma döneminde ne kadar yazışmak istersin?", en: "Early on, how much do you like to text?"},
    [
      {tr: "Gün boyu haberleşelim", en: "Let's keep in touch all day"},
      {tr: "Günde birkaç mesaj yeter", en: "A few messages a day is enough"},
      {tr: "Az yazışalım, buluşmak daha iyi", en: "Less texting, meeting up is better"},
    ]),
  importance("rl_humor_importance", 4, "humor",
    {tr: "Birinin seni güldürebilmesi ne kadar önemli?", en: "How much does it matter that someone can make you laugh?"},
    [
      {tr: "Çok önemli", en: "A lot"},
      {tr: "Güzel olur", en: "It's a nice plus"},
      {tr: "Belirleyici değil", en: "Not a deciding factor"},
    ]),
  stance("rl_conflict", "initial", 5, "values", "communication",
    {tr: "Bir anlaşmazlıkta genelde ne yaparsın?", en: "When you disagree, what do you usually do?"},
    [
      {tr: "Hemen konuşup çözmek isterim", en: "Talk it through right away"},
      {tr: "Önce sakinleşir, sonra konuşurum", en: "Cool off first, then talk"},
      {tr: "Biraz zaman tanır, büyütmem", en: "Give it time and let it go"},
    ]),
  stance("rl_togetherness", "initial", 6, "values", "personalSpace",
    {tr: "İlişkide ideal denge sence hangisi?", en: "What's the ideal balance in a relationship?"},
    [
      {tr: "Çoğu şeyi birlikte yapmak", en: "Doing most things together"},
      {tr: "Birlikte ama herkesin kendi alanı olsun", en: "Together, with room for our own space"},
      {tr: "Bağımsızlık önce gelir", en: "Independence comes first"},
    ]),
  importance("rl_values_importance", 7, "values",
    {tr: "Hayata ve ilişkilere benzer bakmanız ne kadar önemli?", en: "How much does seeing life and relationships the same way matter?"},
    [
      {tr: "Çok önemli", en: "A lot"},
      {tr: "Önemli", en: "It matters"},
      {tr: "Farklılıklar da güzel", en: "Differences can be good too"},
    ]),
  stance("rl_social_energy", "initial", 8, "lifestyle", "socialLife",
    {tr: "Boş bir akşamı en çok nasıl geçirirsin?", en: "How do you most like to spend a free evening?"},
    [
      {tr: "Dışarıda, kalabalıkla", en: "Out, with a crowd"},
      {tr: "Duruma göre değişir", en: "It depends"},
      {tr: "Sakin; evde ya da birkaç kişiyle", en: "Quietly, at home or with a few people"},
    ]),
  importance("rl_lifestyle_importance", 9, "lifestyle",
    {tr: "Günlük rutinlerinizin uyuşması ne kadar önemli?", en: "How much does it matter that your daily routines fit?"},
    [
      {tr: "Çok önemli", en: "A lot"},
      {tr: "Biraz", en: "Somewhat"},
      {tr: "Pek değil", en: "Not much"},
    ]),
  stance("rl_plans", "initial", 10, "lifestyle", "socialLife",
    {tr: "Planlar konusunda hangisi sana daha yakın?", en: "Which is closer to you when it comes to plans?"},
    [
      {tr: "Önceden planlamayı severim", en: "I like planning ahead"},
      {tr: "Biraz plan, biraz sürpriz", en: "A bit of planning, a bit of surprise"},
      {tr: "Anlık kararlar daha keyifli", en: "Spur-of-the-moment is more fun"},
    ]),
  importance("rl_interests_importance", 11, "interests",
    {tr: "Ortak ilgi alanlarınızın olması ne kadar önemli?", en: "How much do shared interests matter?"},
    [
      {tr: "Çok önemli", en: "A lot"},
      {tr: "Birkaç ortak nokta yeter", en: "A few in common is enough"},
      {tr: "Farklı ilgiler de olur", en: "Different interests are fine"},
    ]),
  stance("rl_openness", "initial", 12, "values", "communication",
    {tr: "Duygularını genelde nasıl gösterirsin?", en: "How do you usually show how you feel?"},
    [
      {tr: "Açıkça söylerim", en: "I say it openly"},
      {tr: "Zamanla açılırım", en: "I open up over time"},
      {tr: "Daha çok davranışlarımla", en: "Mostly through what I do"},
    ]),
  importance("rl_music_importance", 13, "music",
    {tr: "Müzik zevkinizin uyuşması senin için ne ifade eder?", en: "What does a shared taste in music mean to you?"},
    [
      {tr: "Çok şey", en: "A lot"},
      {tr: "Biraz", en: "A little"},
      {tr: "Pek bir şey değil", en: "Not much"},
    ]),
  stance("rl_future_talk", "initial", 14, "relationship", "futurePlans",
    {tr: "Gelecek planlarını konuşmanın doğru zamanı…", en: "The right time to talk about the future is…"},
    [
      {tr: "En baştan", en: "Right from the start"},
      {tr: "Birbirimizi tanıyınca", en: "Once we know each other"},
      {tr: "Acele yok, anı yaşarım", en: "No rush, I live in the moment"},
    ]),
  stance("rl_friends_circle", "initial", 15, "interests", "friendship",
    {tr: "Partnerinin arkadaşlarınla vakit geçirmesi…", en: "Your partner spending time with your friends is…"},
    [
      {tr: "Benim için çok önemli", en: "Very important to me"},
      {tr: "Ara sıra yeterli", en: "Nice now and then"},
      {tr: "Ayrı çevrelerimiz olabilir", en: "We can keep separate circles"},
    ]),

  // --- Progressive bank: asked a few at a time, weakest dimensions first. --
  stance("rl_humor_style", "progressive", 1, "humor", null,
    {tr: "Hangi mizah sana daha yakın?", en: "Which kind of humor feels most like you?"},
    [
      {tr: "Absürt ve saçma", en: "Absurd and silly"},
      {tr: "İnce ve iğneleyici", en: "Dry and witty"},
      {tr: "Sıcak ve içten", en: "Warm and gentle"},
    ]),
  stance("rl_teasing", "progressive", 2, "humor", null,
    {tr: "Tatlı şakalaşmalar bir ilişkide…", en: "Playful teasing in a relationship is…"},
    [
      {tr: "Olmazsa olmaz", en: "Essential"},
      {tr: "Arada güzel", en: "Nice once in a while"},
      {tr: "Pek bana göre değil", en: "Not really my thing"},
    ]),
  stance("rl_music_together", "progressive", 3, "music", null,
    {tr: "Birlikte müzik dendiğinde aklına ne gelir?", en: "What does music together look like for you?"},
    [
      {tr: "Konserler ve festivaller", en: "Concerts and festivals"},
      {tr: "Evde ya da yolda birlikte dinlemek", en: "Listening together at home or on the road"},
      {tr: "Herkes kendi listesini dinlesin", en: "Everyone keeps their own playlist"},
    ]),
  stance("rl_music_discovery", "progressive", 4, "music", null,
    {tr: "Yeni müzik keşfetmek…", en: "Discovering new music…"},
    [
      {tr: "Sürekli yaptığım bir şey", en: "Is something I do all the time"},
      {tr: "Arada bir olur", en: "Happens now and then"},
      {tr: "Bildiklerim bana yeter", en: "I stick with what I know"},
    ]),
  stance("rl_new_things", "progressive", 5, "interests", null,
    {tr: "Birlikte yeni bir şey denemek…", en: "Trying something new together…"},
    [
      {tr: "Her hafta olsun", en: "Every week, please"},
      {tr: "Arada bir güzel", en: "Is nice once in a while"},
      {tr: "Alıştığımız şeyleri severim", en: "I like our familiar things"},
    ]),
  stance("rl_hobbies_shared", "progressive", 6, "interests", null,
    {tr: "Hobilerini partnerinle…", en: "Your hobbies with a partner…"},
    [
      {tr: "Paylaşmak isterim", en: "I'd love to share them"},
      {tr: "Bazılarını paylaşırım", en: "I'd share some"},
      {tr: "Kendime saklarım", en: "I keep them to myself"},
    ]),
  stance("rl_rhythm", "progressive", 7, "lifestyle", null,
    {tr: "Günün hangi saatinde daha canlısın?", en: "When do you have the most energy?"},
    [
      {tr: "Sabahları", en: "In the morning"},
      {tr: "Gün ortasında", en: "Around midday"},
      {tr: "Geceleri", en: "Late at night"},
    ]),
  stance("rl_travel", "progressive", 8, "lifestyle", null,
    {tr: "Tatilde seni en çok ne mutlu eder?", en: "What makes a good holiday for you?"},
    [
      {tr: "Yeni şehirler, bol gezmek", en: "New cities, lots of exploring"},
      {tr: "Biraz gezi, biraz dinlenme", en: "A bit of both"},
      {tr: "Sakin bir yerde dinlenmek", en: "Resting somewhere quiet"},
    ]),
  stance("rl_busy_day", "progressive", 9, "values", "communication",
    {tr: "Yoğun bir günde partnerinden hiç mesaj gelmezse…", en: "On a busy day with no message from your partner…"},
    [
      {tr: "Merak eder, yazarım", en: "I'd wonder and check in"},
      {tr: "Akşam konuşuruz", en: "We'll talk in the evening"},
      {tr: "Hiç sorun etmem", en: "No problem at all"},
    ]),
  stance("rl_making_up", "progressive", 10, "values", "communication",
    {tr: "Bir tartışmadan sonra barışmak için…", en: "After an argument, making up takes…"},
    [
      {tr: "Konuşup netleştirmek gerekir", en: "Talking it through"},
      {tr: "Küçük bir jest yeter", en: "A small gesture"},
      {tr: "Zaman her şeyi yumuşatır", en: "Time — it softens everything"},
    ]),
  stance("rl_alone_time", "progressive", 11, "values", "personalSpace",
    {tr: "Kendine ayırdığın zamana ne sıklıkla ihtiyaç duyarsın?", en: "How often do you need time for yourself?"},
    [
      {tr: "Sık sık", en: "Often"},
      {tr: "Ara sıra", en: "Sometimes"},
      {tr: "Nadiren", en: "Rarely"},
    ]),
  stance("rl_labels", "progressive", 12, "relationship", "expectations",
    {tr: "İlişkiye bir isim koymak…", en: "Putting a label on the relationship…"},
    [
      {tr: "Birkaç buluşmadan sonra olmalı", en: "Should happen after a few dates"},
      {tr: "Hissedince kendiliğinden olur", en: "Happens naturally when it feels right"},
      {tr: "Acelesi yok", en: "There's no rush"},
    ]),
];

const BY_ID = new Map(LEARNING_QUESTIONS.map((question) => [question.id, question]));

export const LEARNING_QUESTION_ID_PATTERN = /^rl_[a-z0-9_]{2,40}$/;

export function learningQuestion(id: unknown): LearningQuestion | null {
  if (typeof id !== "string" || !LEARNING_QUESTION_ID_PATTERN.test(id)) return null;
  return BY_ID.get(id) ?? null;
}

/** The active initial set, in the order it is asked. */
export function initialQuestions(): LearningQuestion[] {
  return LEARNING_QUESTIONS
    .filter((question) => question.active && question.stage === "initial")
    .sort((a, b) => a.order - b.order);
}

export function progressiveQuestions(): LearningQuestion[] {
  return LEARNING_QUESTIONS
    .filter((question) => question.active && question.stage === "progressive")
    .sort((a, b) => a.order - b.order);
}

/** True when `answerId` is one of the question's own options. */
export function isValidLearningAnswer(questionId: unknown, answerId: unknown): boolean {
  const question = learningQuestion(questionId);
  return !!question && question.active &&
    question.options.some((option) => option.id === answerId);
}

/** Topic for a stance question's shared view, for "why this person" copy. */
export function learningTopicOf(questionId: string): LearningTopic | null {
  const question = BY_ID.get(questionId);
  return question && question.kind === "stance" ? question.topic : null;
}

/** Whether a stored stance answer may be compared between two people. */
export function isComparableLearningAnswer(questionId: string, answerId: unknown): boolean {
  const question = BY_ID.get(questionId);
  return !!question && question.active && question.kind === "stance" &&
    question.options.some((option) => option.id === answerId);
}
