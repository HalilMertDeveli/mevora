import type {Firestore} from "firebase-admin/firestore";
import {
  normalizeHumorVector,
  type HumorCategory,
} from "./categories.js";
import {
  ANCHOR_SLOTS,
  CALIBRATION_TOTAL,
  COVERAGE_MASS_THRESHOLD,
  HUMOR_CALIBRATION_VERSION,
  coverageDimensionsOf,
  rotatingIndex,
  scoreCalibrationCandidate,
  selectAdaptiveDimensions,
  selectExplorationDimensions,
  stageForPosition,
} from "./calibration.js";
import {listCalibrationPool} from "./contentRepository.js";
import type {
  HumorCalibrationStage,
  HumorContentDoc,
  UserHumorCalibrationDoc,
  UserHumorProfileDoc,
} from "./types.js";

export type CalibrationPick = {
  content: HumorContentDoc;
  stage: HumorCalibrationStage;
};

export type CalibrationSelection = {
  picks: CalibrationPick[];
  /** Positions the curated pool could not fill. */
  unfilled: number;
  /** Human-readable pool gaps, for admin/catalog reporting. */
  deficiencies: string[];
};

/**
 * Rotate deterministically through a pool of measurement-equivalent items.
 *
 * The seed is stable per user + calibration version + role, so an interrupted
 * calibration resumes onto the same item, while different users spread across
 * the pool. Items already used are skipped by walking forward from the rotation
 * offset — still fully deterministic, no `Math.random`.
 */
function pickRotating(
  pool: readonly HumorContentDoc[],
  seed: string,
  used: ReadonlySet<string>,
): HumorContentDoc | null {
  if (pool.length === 0) {
    return null;
  }
  const start = rotatingIndex(pool.length, seed);
  for (let step = 0; step < pool.length; step += 1) {
    const candidate = pool[(start + step) % pool.length];
    if (!used.has(candidate.contentId)) {
      return candidate;
    }
  }
  return null;
}

/**
 * Prefer content in a language the user reads, but never let language alone
 * empty a pool — measurement coverage matters more than locale here.
 */
function preferLanguage(
  pool: readonly HumorContentDoc[],
  languages: readonly string[],
): readonly HumorContentDoc[] {
  if (languages.length === 0) {
    return pool;
  }
  const wanted = new Set(languages.map((l) => l.trim().toLowerCase()));
  const matching = pool.filter((item) => wanted.has(item.language));
  return matching.length > 0 ? matching : pool;
}

/** Items that genuinely measure `dimension`, so rotation stays equivalent. */
function qualifiedFor(
  pool: readonly HumorContentDoc[],
  dimension: HumorCategory,
): readonly HumorContentDoc[] {
  return pool.filter(
    (item) =>
      normalizeHumorVector(item.humorVector, 0)[dimension] >= COVERAGE_MASS_THRESHOLD,
  );
}

function bestFor(
  pool: readonly HumorContentDoc[],
  dimension: HumorCategory,
  languages: readonly string[],
  used: ReadonlySet<string>,
): HumorContentDoc | null {
  const available = pool.filter((item) => !used.has(item.contentId));
  if (available.length === 0) {
    return null;
  }
  return [...available].sort((a, b) => {
    const diff =
      scoreCalibrationCandidate({content: b, dimension, userLanguages: languages}) -
      scoreCalibrationCandidate({content: a, dimension, userLanguages: languages});
    if (diff !== 0) {
      return diff;
    }
    return a.contentId < b.contentId ? -1 : a.contentId > b.contentId ? 1 : 0;
  })[0];
}

/**
 * Build the next run of calibration items.
 *
 * One Firestore read: the curated pool is small by construction, so it is
 * fetched once and partitioned in memory rather than queried per slot.
 *
 * Positions are filled strictly in order — anchor 1..6, adaptive 7..12,
 * exploration 13..15 — from `state.completedCount`, which is the only source of
 * truth for where the user is. Nothing the client sends influences the stage.
 */
export async function selectCalibrationItems(input: {
  db: Firestore;
  uid: string;
  state: UserHumorCalibrationDoc;
  profile: UserHumorProfileDoc;
  languages: string[];
  limit: number;
  /** Content the user has already interacted with outside calibration. */
  excludeContentIds?: ReadonlySet<string>;
}): Promise<CalibrationSelection> {
  const remaining = Math.max(0, CALIBRATION_TOTAL - input.state.completedCount);
  const wanted = Math.min(remaining, Math.max(0, input.limit));
  if (wanted === 0) {
    return {picks: [], unfilled: 0, deficiencies: []};
  }

  const pool = await listCalibrationPool(input.db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });

  const used = new Set<string>([
    ...input.state.ratedContentIds,
    ...(input.excludeContentIds ?? []),
  ]);
  const picks: CalibrationPick[] = [];
  const deficiencies: string[] = [];

  // Coverage accumulates across the page so that two positions in the same
  // request never probe the same dimension.
  const coveredSlots = new Set(input.state.coveredSlots);
  const coveredDimensions = new Set(input.state.coveredDimensions);

  const take = (content: HumorContentDoc, stage: HumorCalibrationStage): void => {
    picks.push({content, stage});
    used.add(content.contentId);
    for (const dim of coverageDimensionsOf(content)) {
      coveredDimensions.add(dim);
    }
    if (content.calibration.slot) {
      coveredSlots.add(content.calibration.slot);
    }
  };

  for (let offset = 0; offset < wanted; offset += 1) {
    const position = input.state.completedCount + offset;
    const stage = stageForPosition(position);

    if (stage === "anchor") {
      const slot = ANCHOR_SLOTS.find((s) => !coveredSlots.has(s.id));
      if (!slot) {
        // Every slot is covered but the stage still has positions left, which
        // only happens on a degraded/legacy state. Fall through to adaptive
        // selection rather than serving nothing.
        deficiencies.push("anchor:no_uncovered_slot");
        break;
      }
      const slotPool = preferLanguage(
        pool.filter((item) => item.calibration.slot === slot.id),
        input.languages,
      );
      const chosen = pickRotating(
        slotPool,
        `${input.uid}:${HUMOR_CALIBRATION_VERSION}:${slot.id}`,
        used,
      );
      if (!chosen) {
        deficiencies.push(`anchor:${slot.id}`);
        break;
      }
      take(chosen, stage);
      continue;
    }

    const dimensions =
      stage === "adaptive"
        ? selectAdaptiveDimensions({
            profile: input.profile,
            coveredDimensions: [...coveredDimensions],
          })
        : selectExplorationDimensions({
            profile: input.profile,
            coveredDimensions: [...coveredDimensions],
          });

    const dimension = dimensions[0];
    if (!dimension) {
      deficiencies.push(`${stage}:no_target_dimension`);
      break;
    }

    // Rotate among items that genuinely measure the dimension; only if none
    // qualify do we fall back to the best-scoring item available.
    const eligible = preferLanguage(
      pool.filter((item) => !used.has(item.contentId)),
      input.languages,
    );
    const chosen =
      pickRotating(
        qualifiedFor(eligible, dimension),
        `${input.uid}:${HUMOR_CALIBRATION_VERSION}:${stage}:${dimension}`,
        used,
      ) ?? bestFor(eligible, dimension, input.languages, used);

    if (!chosen) {
      deficiencies.push(`${stage}:${dimension}`);
      break;
    }
    take(chosen, stage);
  }

  return {
    picks,
    unfilled: wanted - picks.length,
    deficiencies,
  };
}
