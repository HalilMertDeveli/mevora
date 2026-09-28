import type {Firestore} from "firebase-admin/firestore";
import {
  normalizeHumorVector,
  type HumorCategory,
} from "./categories.js";
import {
  ANCHOR_INTERACTIONS,
  ANCHOR_SLOTS,
  COVERAGE_MASS_THRESHOLD,
  DISLIKE_VALIDATION_POSITION,
  HUMOR_CALIBRATION_VERSION,
  VALIDATION_POSITION,
  coverageDimensionsOf,
  positionsLeftInStage,
  primaryDimensionOf,
  rotatingIndex,
  scoreCalibrationCandidate,
  selectAdaptiveDimensions,
  selectExplorationDimensions,
  selectValidationDimension,
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

/**
 * Items that genuinely measure `dimension`, so rotation stays equivalent.
 *
 * Items *about* the dimension (it is their heaviest mass) come first: probing
 * `dry` with a clip that is mostly `dark` would record the answer against the
 * wrong trait. Only when no focused item exists does any item carrying enough
 * mass qualify.
 */
function qualifiedFor(
  pool: readonly HumorContentDoc[],
  dimension: HumorCategory,
): readonly HumorContentDoc[] {
  const carrying = pool.filter(
    (item) =>
      normalizeHumorVector(item.humorVector, 0)[dimension] >= COVERAGE_MASS_THRESHOLD,
  );
  const focused = carrying.filter((item) => primaryDimensionOf(item) === dimension);
  return focused.length > 0 ? focused : carrying;
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
 * Dimensions already probed after the anchor stage, reconstructed from server
 * state alone. `ratedContentIds` is positional (the n-th counted rating is
 * entry n), so everything past the anchors is an adaptive/exploration probe,
 * and a probe measures its item's primary dimension — the selector only picks
 * focused items when they exist. (When a thin pool forced a fallback item, the
 * original target is not recoverable from state; within one page the loop
 * excludes both.)
 */
function probedAfterAnchors(
  state: UserHumorCalibrationDoc,
  pool: readonly HumorContentDoc[],
): Set<string> {
  const byId = new Map(pool.map((item) => [item.contentId, item]));
  const probed = new Set<string>();
  for (const id of state.ratedContentIds.slice(ANCHOR_INTERACTIONS)) {
    const item = byId.get(id);
    const dim = item ? primaryDimensionOf(item) : null;
    if (dim) {
      probed.add(dim);
    }
  }
  return probed;
}

/**
 * Build the next run of calibration items.
 *
 * One Firestore read: the curated pool is small by construction, so it is
 * fetched once and partitioned in memory rather than queried per slot.
 *
 * Positions are filled strictly in order — anchor 1..6, adaptive 7..12,
 * exploration/validation 13..15 — from `state.completedCount`, which is the
 * only source of truth for where the user is. Nothing the client sends
 * influences the stage.
 *
 * A page never crosses a stage boundary ({@link positionsLeftInStage}): the
 * adaptive picks are computed only once the anchors have been rated, from the
 * profile those ratings produced, and likewise for exploration. The client
 * fetches again when it reaches the end of a stage.
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
  const wanted = Math.min(
    positionsLeftInStage(input.state.completedCount),
    Math.max(0, input.limit),
  );
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
  const note = (deficiency: string): void => {
    if (!deficiencies.includes(deficiency)) {
      deficiencies.push(deficiency);
    }
  };

  // Coverage and probes accumulate across the page so that two positions in
  // the same request never measure the same slot or probe the same dimension.
  const coveredSlots = new Set(input.state.coveredSlots);
  const coveredDimensions = new Set(input.state.coveredDimensions);
  const probed = probedAfterAnchors(input.state, pool);
  const exhaustedSlots = new Set<string>();
  const degradedSlots = new Set<string>();

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

  const pickAnchor = (): HumorContentDoc | null => {
    // Every uncovered slot that still has an unused candidate, in slot order.
    // An exhausted slot is recorded and skipped — it must not stop the others.
    for (const slot of ANCHOR_SLOTS) {
      if (coveredSlots.has(slot.id) || exhaustedSlots.has(slot.id)) {
        continue;
      }
      const slotPool = pool.filter((item) => item.calibration.slot === slot.id);
      const seed = `${input.uid}:${HUMOR_CALIBRATION_VERSION}:${slot.id}`;
      const chosen =
        pickRotating(preferLanguage(slotPool, input.languages), seed, used) ??
        pickRotating(slotPool, seed, used);
      if (chosen) {
        return chosen;
      }
      exhaustedSlots.add(slot.id);
      note(`anchor:${slot.id}`);
    }

    // Degraded: the slots still missing have no candidate left for this user.
    // Measure a missing slot's primary with the best remaining *curated* item
    // rather than stalling — the rating advances calibration as a recorded
    // degradation, never as a covered slot.
    const missing = ANCHOR_SLOTS.filter((s) => !coveredSlots.has(s.id));
    const targets = (missing.length > 0 ? missing : ANCHOR_SLOTS).filter(
      (s) => !degradedSlots.has(s.id),
    );
    const available = pool.filter((item) => !used.has(item.contentId));
    const preferred = preferLanguage(available, input.languages);
    for (const slot of targets) {
      const chosen = bestFor(preferred, slot.primary, input.languages, used);
      if (chosen) {
        degradedSlots.add(slot.id);
        return chosen;
      }
    }
    return null;
  };

  for (let offset = 0; offset < wanted; offset += 1) {
    const position = input.state.completedCount + offset;
    const stage = stageForPosition(position);

    if (stage === "anchor") {
      const chosen = pickAnchor();
      if (!chosen) {
        note("anchor:pool_exhausted");
        break;
      }
      take(chosen, stage);
      continue;
    }

    const exclude = [...probed];
    // Validation re-tests the clearest like / dislike with a different curated
    // item; when there is nothing clear (or it was already re-tested) the
    // position explores like the others.
    let dimension: HumorCategory | null =
      position === VALIDATION_POSITION
        ? selectValidationDimension({profile: input.profile, exclude})
        : position === DISLIKE_VALIDATION_POSITION
          ? selectValidationDimension({
              profile: input.profile,
              exclude,
              direction: "dislike",
            })
          : null;
    if (!dimension) {
      const dimensions =
        stage === "adaptive"
          ? selectAdaptiveDimensions({
              profile: input.profile,
              coveredDimensions: [...coveredDimensions],
              exclude,
            })
          : selectExplorationDimensions({
              profile: input.profile,
              coveredDimensions: [...coveredDimensions],
              exclude,
            });
      dimension = dimensions[0] ?? null;
    }
    if (!dimension) {
      note(`${stage}:no_target_dimension`);
      break;
    }

    // Rotate among items that genuinely measure the dimension — preferred
    // language first, then any language; only if none qualify fall back to the
    // best-scoring item available.
    const available = pool.filter((item) => !used.has(item.contentId));
    const preferred = preferLanguage(available, input.languages);
    const seed = `${input.uid}:${HUMOR_CALIBRATION_VERSION}:${stage}:${dimension}`;
    const chosen =
      pickRotating(qualifiedFor(preferred, dimension), seed, used) ??
      pickRotating(qualifiedFor(available, dimension), seed, used) ??
      bestFor(preferred, dimension, input.languages, used);

    if (!chosen) {
      note(`${stage}:${dimension}`);
      break;
    }
    // Record the target *and* what the item actually measures. They differ
    // only when a thin pool forced a fallback, and a resumed page can only
    // rebuild the latter (probedAfterAnchors), so both must be excluded here.
    probed.add(dimension);
    const measured = primaryDimensionOf(chosen);
    if (measured) {
      probed.add(measured);
    }
    take(chosen, stage);
  }

  return {
    picks,
    unfilled: wanted - picks.length,
    deficiencies,
  };
}

/**
 * Whether any curated calibration item is still unseen by this user.
 *
 * Only asked on a rare path — an *uncurated* item rated while the anchor stage
 * is open — to decide whether that rating may take an anchor position. Normally
 * a curated candidate remains and the answer keeps the anchor baseline intact;
 * a user who has already interacted with the whole curated pool (for example
 * one who rated it all before calibration existed) would otherwise be stuck in
 * the anchor stage forever. Exact per-item check, bounded by the pool size.
 */
export async function hasUnseenCuratedCandidate(input: {
  db: Firestore;
  uid: string;
  state: UserHumorCalibrationDoc;
}): Promise<boolean> {
  const pool = await listCalibrationPool(input.db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });
  const rated = new Set(input.state.ratedContentIds);
  const candidates = pool.filter((item) => !rated.has(item.contentId));
  if (candidates.length === 0) {
    return false;
  }
  const snaps = await input.db.getAll(
    ...candidates.map((item) =>
      input.db.doc(`users/${input.uid}/humorInteractions/${item.contentId}`),
    ),
  );
  return snaps.some((snap) => !snap.exists);
}
