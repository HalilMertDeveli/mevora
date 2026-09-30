import {LEARNING_QUESTIONS, learningQuestion, type LearningCategory, type LocalizedText} from "./catalog.js";
import type {LearningState, ProfileSignals} from "./model.js";

/**
 * "Mevora seni ne kadar tanıyor?" — what the learning dashboard shows, built
 * only from what the member actually answered or already has on their
 * profile. No inferred traits, no invented percentages.
 *
 * Coverage per area is plain:
 *
 *   (bank questions answered + profile signals present) / (bank questions + signals possible)
 *
 * Read-backs repeat the member's own answers in soft wording ("daha çok
 * önemsiyorsun"), never as a verdict about who they are.
 */

export const LEARNING_CATEGORIES: readonly LearningCategory[] = [
  "relationship",
  "communication",
  "lifestyle",
  "values",
  "humor",
  "music",
  "interests",
];

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

function answeredInCurrentVersion(state: LearningState, questionId: string, version: number): boolean {
  return state.answers[questionId]?.version === version;
}

export function categoryProgress(state: LearningState, signals: ProfileSignals): CategoryProgress[] {
  const active = LEARNING_QUESTIONS.filter((question) => question.active);
  return LEARNING_CATEGORIES.map((key) => {
    const questions = active.filter((question) => question.category === key);
    const answered = questions.filter((question) => answeredInCurrentVersion(state, question.id, question.version)).length;
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
export const ANSWER_HIGHLIGHTS: Record<string, Record<string, LocalizedText>> = {
  relationship_daily_contact_v1: {
    all_day: {tr: "Gün içinde sık haberleşmeyi daha çok önemsiyorsun.", en: "Staying in touch through the day matters more to you."},
    rarely: {tr: "Gün içinde az yazışıp akşam konuşmaya daha yakınsın.", en: "You lean towards texting less and talking in the evening."},
  },
  relationship_conflict_timing_v1: {
    talk_now: {tr: "Tartışmaları hemen konuşarak çözmeye daha yakınsın.", en: "You lean towards talking disagreements through right away."},
    cool_down_then_talk: {tr: "Bir tartışmada önce sakinleşmeyi tercih ediyorsun.", en: "In an argument, you prefer to cool off first."},
  },
  relationship_pace_v1: {
    fast: {tr: "Hissettiğinde işlerin hızlı ilerlemesine daha yakınsın.", en: "You lean towards things moving quickly when it feels right."},
    natural: {tr: "İşlerin doğal akışında ilerlemesini tercih ediyorsun.", en: "You prefer things to move at their own pace."},
    slow: {tr: "Adım adım ilerlemeye daha yakınsın.", en: "You lean towards taking things step by step."},
  },
  relationship_togetherness_balance_v1: {
    mostly_together: {tr: "Çoğu şeyi birlikte yapmayı daha çok önemsiyorsun.", en: "Doing most things together matters more to you."},
    together_with_space: {tr: "Birlikteliğin yanında kendi alanını da önemsiyorsun.", en: "You value togetherness and your own space."},
    independence_first: {tr: "Bağımsızlığını daha çok önemsiyorsun.", en: "Your independence matters more to you."},
  },
  relationship_future_talk_v1: {
    from_start: {tr: "Gelecek planlarını erken konuşmayı önemsiyorsun.", en: "You value talking about the future early on."},
    live_moment: {tr: "Anı yaşamaya daha yakınsın.", en: "You lean towards living in the moment."},
  },
  relationship_goal_importance_v1: {
    very_important: {tr: "Aynı ilişki hedefini paylaşmayı çok önemsiyorsun.", en: "Sharing the same relationship goal matters a lot to you."},
    important: {tr: "Aynı ilişki hedefini paylaşmayı önemsiyorsun.", en: "Sharing the same relationship goal matters to you."},
  },
  relationship_humor_importance_v1: {
    very_important: {tr: "Seni güldürebilen birini daha çok önemsiyorsun.", en: "Someone who can make you laugh matters more to you."},
    important: {tr: "Mizahı önemsiyorsun.", en: "Humor matters to you."},
  },
  relationship_music_importance_v1: {
    very_important: {tr: "Müzik zevkinin uyuşmasını çok önemsiyorsun.", en: "A shared taste in music matters a lot to you."},
    important: {tr: "Müzik zevkinin uyuşmasını önemsiyorsun.", en: "A shared taste in music matters to you."},
  },
  relationship_free_evening_v1: {
    out_with_crowd: {tr: "Boş akşamlarda dışarıda olmaya daha yakınsın.", en: "You lean towards going out on free evenings."},
    quiet_home: {tr: "Boş akşamlarda sakinliği tercih ediyorsun.", en: "You prefer quiet free evenings."},
  },
  relationship_alone_time_v1: {
    often: {tr: "Kendine ayırdığın zamanı önemsiyorsun.", en: "Time for yourself matters to you."},
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
    if (!question.active) continue;
    const answer = state.answers[question.id];
    if (!answer || answer.version !== question.version) continue;
    const readBack = ANSWER_HIGHLIGHTS[question.id]?.[answer.answerId];
    if (!readBack) continue;
    out.push({questionId: question.id, category: question.category, text: {tr: readBack.tr, en: readBack.en}});
    if (out.length >= MAX_HIGHLIGHTS) break;
  }
  return out;
}

/** Every answered active question, newest first, for viewing and changing. */
export function answeredQuestionIds(state: LearningState): string[] {
  return Object.entries(state.answers)
    .filter(([id, answer]) => {
      const question = learningQuestion(id);
      return question?.active && answer.version === question.version;
    })
    .sort((a, b) => b[1].answeredAtMs - a[1].answeredAtMs || a[0].localeCompare(b[0]))
    .map(([id]) => id);
}

/** Real counts for the dashboard header. */
export function answerTotals(state: LearningState, dateKey: string): {
  thisMonth: number;
  total: number;
  completedDays: number;
} {
  return {
    thisMonth: state.answerCounts[dateKey.slice(0, 7)] ?? 0,
    total: Object.values(state.answerCounts).reduce((sum, n) => sum + n, 0),
    completedDays: state.completedDays,
  };
}
