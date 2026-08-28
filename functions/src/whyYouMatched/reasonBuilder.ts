import {
  WHY_YOU_MATCHED_MAX_KM,
  WHY_YOU_MATCHED_TOP_N,
  type WhyYouMatchedReasonDto,
} from "./types.js";
import {
  humorAnswerConfidence,
  humorAnswerStrength,
  meetsHumorAnswerReasonThreshold,
} from "./humorAnswerComparison.js";
import {
  WYM_COMMUNICATION_ALIGNED_RATIO,
  WYM_COMMUNICATION_MIN_SCORE,
  WYM_HUMOR_LAB_MIN_CONFIDENCE,
  WYM_HUMOR_LAB_MIN_SCORE,
  WYM_INTEREST_MIN_COMMON,
  WYM_LIFESTYLE_MIN_SCORE,
  WYM_LIFESTYLE_MIN_SHARED_TAGS,
  WYM_MUSIC_SCORE_ONLY_CONFIDENCE,
  WYM_MUSIC_SCORE_ONLY_MIN,
} from "./wymContract.js";

export type WhyYouMatchedBuildInput = {
  viewerUid: string;
  peerUid: string;
  viewerInterests: string[];
  peerInterests: string[];
  viewerLanguages: string[];
  peerLanguages: string[];
  viewerLifestyleTags: string[];
  peerLifestyleTags: string[];
  musicScore: number | null;
  sharedArtistNames: string[];
  sharedArtistCount: number;
  sharedTrackCount: number;
  sharedGenreNames: string[];
  humorScore: number | null;
  humorConfidence: number;
  humorSharedDims: string[];
  humorMatchingAnswers: number | null;
  humorComparableAnswers: number | null;
  questionAlignedCount: number | null;
  questionSharedCount: number | null;
  communicationTopic: boolean;
  distanceKm: number | null;
  overallScore: number | null;
};

function strengthFromScore(score: number): "weak" | "moderate" | "strong" {
  if (score >= 75) return "strong";
  if (score >= 50) return "moderate";
  return "weak";
}

function norm(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    const t = raw.trim();
    if (!t) continue;
    const key = t.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(t);
  }
  return out;
}

function intersect(a: string[], b: string[]): string[] {
  const other = new Set(norm(b).map((x) => x.toLowerCase()));
  return norm(a).filter((x) => other.has(x.toLowerCase()));
}

function rankingScore(r: WhyYouMatchedReasonDto): number {
  const strengthPts =
    r.strength === "strong" ? 90 : r.strength === "moderate" ? 55 : 25;
  return (
    0.4 * r.score +
    0.2 * strengthPts +
    0.25 * r.confidence * 100 +
    0.15 * 50
  );
}

function selectTop(reasons: WhyYouMatchedReasonDto[]): WhyYouMatchedReasonDto[] {
  const ranked = [...reasons].sort((a, b) => rankingScore(b) - rankingScore(a));
  const selected: WhyYouMatchedReasonDto[] = [];
  const categories = new Set<string>();
  const diversityBonus = 15;

  const remaining = [...ranked];
  while (selected.length < WHY_YOU_MATCHED_TOP_N && remaining.length > 0) {
    let bestIdx = 0;
    let bestEff = -Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const r = remaining[i];
      const base = rankingScore(r);
      const bonus = categories.has(r.category) ? 0 : diversityBonus;
      const eff = base + bonus;
      if (eff > bestEff) {
        bestEff = eff;
        bestIdx = i;
      }
    }
    const pick = remaining.splice(bestIdx, 1)[0];
    selected.push(pick);
    categories.add(pick.category);
  }
  return selected.sort((a, b) => rankingScore(b) - rankingScore(a));
}

/**
 * Builds evidence-backed reasons from already-computed aggregates.
 * Never invents overlap; never embeds coordinates or raw answers.
 */
export function buildWhyYouMatchedReasons(
  input: WhyYouMatchedBuildInput,
): WhyYouMatchedReasonDto[] {
  const reasons: WhyYouMatchedReasonDto[] = [];
  const peer = input.peerUid;

  // Interests
  const sharedInterests = intersect(input.viewerInterests, input.peerInterests);
  if (sharedInterests.length >= WYM_INTEREST_MIN_COMMON) {
    const count = sharedInterests.length;
    const score = Math.min(100, 40 + (count - 1) * 20);
    const names = sharedInterests.slice(0, 3).join(", ");
    const confidence = Math.min(1, Math.max(0.4, count / 3));
    reasons.push({
      id: `interests_${peer}`,
      category: "interests",
      score,
      strength: strengthFromScore(score),
      confidence,
      priority: Math.round(score * confidence),
      titleKey: "wymInterestsTitle",
      descriptionKey: "wymInterestsEvidence",
      descriptionArgs: [names, String(count)],
      evidence: {
        type: "commonInterests",
        values: {count, items: sharedInterests.slice(0, 5), score},
      },
    });
  }

  // Music
  if (input.musicScore != null && input.musicScore >= 1 && input.musicScore <= 100) {
    const score = Math.round(input.musicScore);
    if (input.sharedArtistCount > 0) {
      const named = input.sharedArtistNames.slice(0, 2).join(", ");
      reasons.push({
        id: `music_artists_${peer}`,
        category: "music",
        score,
        strength: strengthFromScore(score),
        confidence: Math.min(1, Math.max(0.5, input.sharedArtistCount / 3)),
        priority: Math.round(score * 0.8),
        titleKey: "wymMusicTitle",
        descriptionKey: named
          ? "wymMusicArtistsNamedEvidence"
          : "wymMusicArtistsCountEvidence",
        descriptionArgs: named
          ? [named, String(input.sharedArtistCount)]
          : [String(input.sharedArtistCount)],
        evidence: {
          type: "commonArtists",
          values: {
            count: input.sharedArtistCount,
            names: input.sharedArtistNames.slice(0, 5),
            score,
            dataComplete: true,
          },
        },
      });
    } else if (input.sharedTrackCount > 0) {
      reasons.push({
        id: `music_tracks_${peer}`,
        category: "music",
        score,
        strength: strengthFromScore(score),
        confidence: Math.min(1, Math.max(0.5, input.sharedTrackCount / 3)),
        priority: Math.round(score * 0.7),
        titleKey: "wymMusicTitle",
        descriptionKey: "wymMusicTracksEvidence",
        descriptionArgs: [String(input.sharedTrackCount)],
        evidence: {
          type: "commonTracks",
          values: {count: input.sharedTrackCount, score, dataComplete: true},
        },
      });
    } else if (input.sharedGenreNames.length > 0) {
      const named = input.sharedGenreNames.slice(0, 2).join(", ");
      reasons.push({
        id: `music_genres_${peer}`,
        category: "music",
        score,
        strength: strengthFromScore(score),
        confidence: 0.55,
        priority: Math.round(score * 0.65),
        titleKey: "wymMusicTitle",
        descriptionKey: named
          ? "wymMusicGenresNamedEvidence"
          : "wymMusicGenresCountEvidence",
        descriptionArgs: named
          ? [named, String(input.sharedGenreNames.length)]
          : [String(input.sharedGenreNames.length)],
        evidence: {
          type: "commonGenres",
          values: {
            count: input.sharedGenreNames.length,
            names: input.sharedGenreNames.slice(0, 5),
            score,
            dataComplete: true,
          },
        },
      });
    } else if (score >= WYM_MUSIC_SCORE_ONLY_MIN) {
      reasons.push({
        id: `music_score_${peer}`,
        category: "music",
        score,
        strength: strengthFromScore(score),
        confidence: WYM_MUSIC_SCORE_ONLY_CONFIDENCE,
        priority: Math.round(score * 0.45),
        titleKey: "wymMusicTitle",
        descriptionKey: "wymMusicScoreEvidence",
        descriptionArgs: [String(score)],
        evidence: {
          type: "musicSimilarity",
          values: {score, dataComplete: false},
        },
      });
    }
  }

  // Humor answers (preferred) or lab score
  if (
    input.humorMatchingAnswers != null &&
    input.humorComparableAnswers != null
  ) {
    const matching = input.humorMatchingAnswers;
    const total = input.humorComparableAnswers;
    const comparison = {
      comparableAnswers: total,
      matchingAnswers: matching,
      similarity: total > 0 ? matching / total : 0,
      score: total > 0 ? Math.round((matching / total) * 100) : 0,
    };
    if (meetsHumorAnswerReasonThreshold(comparison)) {
      const score = comparison.score;
      const confidence = humorAnswerConfidence(comparison);
      reasons.push({
        id: `humor_answers_${peer}`,
        category: "humor",
        score,
        strength: humorAnswerStrength(comparison),
        confidence,
        priority: Math.round(score * confidence),
        titleKey: "wymHumorTitle",
        descriptionKey: "wymHumorEvidence",
        descriptionArgs: [String(matching), String(total)],
        evidence: {
          type: "sharedHumorAnswers",
          values: {matching, comparable: total, score},
        },
      });
    }
  } else if (
    input.humorScore != null &&
    input.humorScore >= WYM_HUMOR_LAB_MIN_SCORE &&
    input.humorConfidence >= WYM_HUMOR_LAB_MIN_CONFIDENCE
  ) {
    const score = Math.round(input.humorScore);
    const dims = input.humorSharedDims.slice(0, 5);
    reasons.push({
      id: `humor_lab_${peer}`,
      category: "humor",
      score,
      strength: strengthFromScore(score),
      confidence: Math.min(1, Math.max(0.15, input.humorConfidence)),
      priority: Math.round(score * input.humorConfidence),
      titleKey: "wymHumorTitle",
      descriptionKey: dims.length
        ? "wymHumorDimsEvidence"
        : "wymHumorScoreEvidence",
      descriptionArgs: dims.length
        ? [String(dims.length), "11"]
        : [String(score)],
      evidence: {
        type: "humorVectorSimilarity",
        values: {
          score,
          confidence: input.humorConfidence,
          sharedDims: dims,
        },
      },
    });
  }

  // Lifestyle tags
  const sharedLifestyle = intersect(
    input.viewerLifestyleTags,
    input.peerLifestyleTags,
  );
  if (sharedLifestyle.length >= WYM_LIFESTYLE_MIN_SHARED_TAGS) {
    const comparable = Math.max(
      input.viewerLifestyleTags.length,
      input.peerLifestyleTags.length,
      sharedLifestyle.length,
    );
    const score = Math.round((sharedLifestyle.length / comparable) * 100);
    if (score >= WYM_LIFESTYLE_MIN_SCORE || sharedLifestyle.length >= 2) {
      const labels = sharedLifestyle.slice(0, 3).join(", ");
      reasons.push({
        id: `lifestyle_${peer}`,
        category: "lifestyle",
        score: Math.max(score, 70),
        strength: strengthFromScore(Math.max(score, 70)),
        confidence: Math.min(1, 0.5 + sharedLifestyle.length * 0.1),
        priority: Math.round(Math.max(score, 70) * 0.7),
        titleKey: "wymLifestyleTitle",
        descriptionKey: "wymLifestyleEvidence",
        descriptionArgs: [
          labels,
          String(sharedLifestyle.length),
          String(comparable),
        ],
        evidence: {
          type: "lifestyleOverlap",
          values: {
            matching: sharedLifestyle.length,
            comparable,
            sharedTags: sharedLifestyle.slice(0, 8),
            score: Math.max(score, 70),
          },
        },
      });
    }
  }

  // Languages
  const sharedLangs = intersect(input.viewerLanguages, input.peerLanguages);
  if (sharedLangs.length > 0) {
    reasons.push({
      id: `preferences_lang_${peer}`,
      category: "preferences",
      score: 70,
      strength: "moderate",
      confidence: Math.min(1, sharedLangs.length / 2),
      priority: 50,
      titleKey: "wymPreferencesTitle",
      descriptionKey: "wymPreferencesLanguageEvidence",
      descriptionArgs: [sharedLangs.slice(0, 3).join(", ")],
      evidence: {
        type: "sharedLanguages",
        values: {languages: sharedLangs, count: sharedLangs.length, score: 70},
      },
    });
  }

  // Communication / questions
  if (
    input.communicationTopic ||
    (input.questionAlignedCount != null &&
      input.questionSharedCount != null &&
      input.questionSharedCount > 0 &&
      input.questionAlignedCount / input.questionSharedCount >=
        WYM_COMMUNICATION_ALIGNED_RATIO)
  ) {
    const score =
      input.questionAlignedCount != null && input.questionSharedCount
        ? Math.round(
            (input.questionAlignedCount / input.questionSharedCount) * 100,
          )
        : WYM_COMMUNICATION_MIN_SCORE;
    if (score >= WYM_COMMUNICATION_MIN_SCORE || input.communicationTopic) {
      reasons.push({
        id: `communication_${peer}`,
        category: "communication",
        score: Math.max(score, 75),
        strength: strengthFromScore(Math.max(score, 75)),
        confidence: 0.72,
        priority: Math.round(Math.max(score, 75) * 0.72),
        titleKey: "wymCommunicationTitle",
        descriptionKey: "wymCommunicationEvidence",
        descriptionArgs: [],
        evidence: {
          type: "communicationAlignment",
          values: {
            score: Math.max(score, 75),
            topicPresent: input.communicationTopic,
            aligned: input.questionAlignedCount ?? 0,
            shared: input.questionSharedCount ?? 0,
          },
        },
      });
    }
  }

  // Distance — rounded km only
  const km = input.distanceKm;
  if (km != null && Number.isFinite(km) && km >= 0 && km <= WHY_YOU_MATCHED_MAX_KM) {
    const sameArea = km < 1;
    const nearby = km <= 5;
    const score = sameArea ? 90 : nearby ? 85 : 70;
    const label = sameArea ? "<1" : String(Math.round(km));
    reasons.push({
      id: `distance_${peer}`,
      category: "distance",
      score,
      strength: sameArea || nearby ? "strong" : "moderate",
      confidence: sameArea ? 0.85 : 0.9,
      priority: score,
      titleKey: sameArea ? "wymDistanceNearbyTitle" : "wymDistanceTitle",
      descriptionKey: sameArea
        ? "wymDistanceNearbyEvidence"
        : "wymDistanceKmEvidence",
      descriptionArgs: sameArea ? [] : [label],
      evidence: {
        type: "proximityKm",
        values: {
          kmRounded: label,
          km: sameArea ? 0 : Math.round(km),
          bucket: sameArea ? "sameArea" : nearby ? "nearby" : "withinRadius",
        },
      },
    });
  }

  return selectTop(reasons);
}
