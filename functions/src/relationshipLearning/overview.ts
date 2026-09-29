import {LEARNING_QUESTIONS, learningQuestion, type LearningQuestion, type LocalizedText} from "./catalog.js";
import type {LearningState, ProfileSignals} from "./model.js";

/**
 * "Mevora seni ne kadar tanıyor?" — what the learning dashboard shows, built
 * only from what the member actually told Mevora or already has on their
 * profile. No inferred traits, no invented percentages.
 *
 * Progress per category is plain coverage:
 *
 *   (questions answered + profile signals present) / (questions + signals possible)
 *
 * Highlights repeat the member's own answers back in soft wording ("daha çok
 * önemsiyorsun"), never as a verdict about who they are.
 */

export const LEARNING_CATEGORIES = [
  "relationship",
  "communication",
  "lifestyle",
  "values",
  "humor",
  "music",
  "interests",
] as const;
export type LearningCategory = (typeof LEARNING_CATEGORIES)[number];

/** Communication questions get their own category; the rest follow their dimension. */
export function learningCategoryOf(question: LearningQuestion): LearningCategory {
  return question.topic === "communication" ? "communication" : question.dimension;
}

/** Existing profile information that counts toward a category, and how many exist. */
function signalsFor(category: LearningCategory, signals: ProfileSignals): {present: number; possible: number} {
  switch (category) {
    case "relationship":
      return {present: signals.hasRelationshipGoal ? 1 : 0, possible: 1};
    case "lifestyle":
      return {present: signals.hasLifestyle ? 1 : 0, possible: 1};
    case "interests":
      return {present: signals.hasInterests ? 1 : 0, possible: 1};
    case "music":
      return {present: signals.hasMusic ? 1 : 0, possible: 1};
    case "humor":
      return {present: signals.humorReady ? 1 : 0, possible: 1};
    case "values":
      return {present: signals.relationshipAnswerCount >= 3 ? 1 : 0, possible: 1};
    case "communication":
      return {present: 0, possible: 0};
  }
}

export interface CategoryProgress {
  key: LearningCategory;
  answered: number;
  questions: number;
  signals: number;
  signalsPossible: number;
  /** 0..1, two decimals. */
  progress: number;
}

function ratio(done: number, total: number): number {
  return total <= 0 ? 0 : Math.round((done / total) * 100) / 100;
}

export function categoryProgress(state: LearningState, signals: ProfileSignals): CategoryProgress[] {
  const active = LEARNING_QUESTIONS.filter((question) => question.active);
  return LEARNING_CATEGORIES.map((key) => {
    const questions = active.filter((question) => learningCategoryOf(question) === key);
    const answered = questions.filter((question) => state.answers[question.id]).length;
    const {present, possible} = signalsFor(key, signals);
    return {
      key,
      answered,
      questions: questions.length,
      signals: present,
      signalsPossible: possible,
      progress: ratio(answered + present, questions.length + possible),
    };
  });
}

export function overallProgress(categories: CategoryProgress[]): number {
  const done = categories.reduce((sum, c) => sum + c.answered + c.signals, 0);
  const total = categories.reduce((sum, c) => sum + c.questions + c.signalsPossible, 0);
  return ratio(done, total);
}

/**
 * Soft read-backs of specific answers. Only answers listed here produce a
 * highlight; everything else is simply counted. Wording says what the member
 * leans towards, never what they "are".
 */
export const ANSWER_HIGHLIGHTS: Record<string, Partial<Record<"a" | "b" | "c", LocalizedText>>> = {
  rl_goal_importance: {
    a: {tr: "Aynı ilişki hedefini paylaşmayı çok önemsiyorsun.", en: "Sharing the same relationship goal matters a lot to you."},
    b: {tr: "İlişki hedefinde esnek olabiliyorsun.", en: "You can be flexible about the relationship goal."},
    c: {tr: "İlişki hedefinin zamanla netleşmesine açıksın.", en: "You're open to the goal becoming clear over time."},
  },
  rl_pace: {
    a: {tr: "Hissettiğinde işlerin hızlı ilerlemesine daha yakınsın.", en: "You lean towards things moving quickly when it feels right."},
    b: {tr: "İşlerin doğal akışında ilerlemesini tercih ediyorsun.", en: "You prefer things to move at their own pace."},
    c: {tr: "Adım adım ilerlemeye daha yakınsın.", en: "You lean towards taking things step by step."},
  },
  rl_texting: {
    a: {tr: "Gün içinde sık haberleşmeyi daha çok önemsiyorsun.", en: "Staying in touch through the day matters more to you."},
    b: {tr: "Günde birkaç mesaja daha yakınsın.", en: "A few messages a day feels right to you."},
    c: {tr: "Yazışmaktan çok buluşmayı tercih ediyorsun.", en: "You'd rather meet up than text a lot."},
  },
  rl_conflict: {
    a: {tr: "Anlaşmazlıkları hemen konuşarak çözmeye daha yakınsın.", en: "You lean towards talking disagreements through right away."},
    b: {tr: "Bir anlaşmazlıkta önce sakinleşmeyi tercih ediyorsun.", en: "In a disagreement, you prefer to cool off first."},
    c: {tr: "Anlaşmazlıkları büyütmemeye daha yakınsın.", en: "You lean towards letting disagreements go."},
  },
  rl_togetherness: {
    a: {tr: "Çoğu şeyi birlikte yapmayı daha çok önemsiyorsun.", en: "Doing most things together matters more to you."},
    b: {tr: "Birlikteliğin yanında kendi alanını da önemsiyorsun.", en: "You value togetherness and your own space."},
    c: {tr: "Bağımsızlığını daha çok önemsiyorsun.", en: "Your independence matters more to you."},
  },
  rl_humor_importance: {
    a: {tr: "Seni güldürebilen birini daha çok önemsiyorsun.", en: "Someone who can make you laugh matters more to you."},
    b: {tr: "Mizahı güzel bir artı olarak görüyorsun.", en: "You see humor as a nice plus."},
  },
  rl_music_importance: {
    a: {tr: "Müzik zevkinin uyuşmasını önemsiyorsun.", en: "A shared taste in music matters to you."},
  },
  rl_social_energy: {
    a: {tr: "Boş akşamlarda dışarıda olmaya daha yakınsın.", en: "You lean towards going out on free evenings."},
    c: {tr: "Boş akşamlarda sakinliği tercih ediyorsun.", en: "You prefer quiet free evenings."},
  },
  rl_future_talk: {
    a: {tr: "Gelecek planlarını erken konuşmayı önemsiyorsun.", en: "You value talking about the future early on."},
    c: {tr: "Anı yaşamaya daha yakınsın.", en: "You lean towards living in the moment."},
  },
};

export const MAX_HIGHLIGHTS = 5;

export interface LearningHighlight {
  questionId: string;
  category: LearningCategory;
  text: LocalizedText;
}

/** Read-backs for the member's answers, in catalog order, at most MAX_HIGHLIGHTS. */
export function answerHighlights(state: LearningState): LearningHighlight[] {
  const out: LearningHighlight[] = [];
  for (const question of LEARNING_QUESTIONS) {
    const answer = state.answers[question.id];
    const readBack = answer ? ANSWER_HIGHLIGHTS[question.id]?.[answer.answerId as "a" | "b" | "c"] : undefined;
    if (!readBack) continue;
    out.push({questionId: question.id, category: learningCategoryOf(question), text: {tr: readBack.tr, en: readBack.en}});
    if (out.length >= MAX_HIGHLIGHTS) break;
  }
  return out;
}

/** Every answered question (initial and follow-up), newest first, for editing. */
export function answeredQuestionIds(state: LearningState): string[] {
  return Object.entries(state.answers)
    .filter(([id]) => learningQuestion(id)?.active)
    .sort((a, b) => b[1].answeredAtMs - a[1].answeredAtMs || a[0].localeCompare(b[0]))
    .map(([id]) => id);
}
