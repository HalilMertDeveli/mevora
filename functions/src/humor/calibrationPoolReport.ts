import type {Firestore} from "firebase-admin/firestore";
import {
  ANCHOR_SLOTS,
  CALIBRATION_TOTAL,
  COVERAGE_MASS_THRESHOLD,
  HUMOR_CALIBRATION_VERSION,
  coverageDimensionsOf,
} from "./calibration.js";
import {ANCHOR_POOL_TARGET} from "./calibrationSeed.js";
import {HUMOR_CATEGORIES, normalizeHumorVector} from "./categories.js";
import {listCalibrationPool} from "./contentRepository.js";
import type {HumorContentDoc} from "./types.js";

/**
 * Operational view of the calibration catalog.
 *
 * Calibration silently degrades when a pool runs thin — it fills the gap from
 * ordinary content and records `degradedCount` rather than stalling. That is
 * the right runtime behaviour, but it means a catalog problem is invisible
 * unless something reports it. This is that report: it answers "is the
 * calibration catalog healthy enough to ship?" without anyone reading code.
 */

export type AnchorSlotHealth = {
  slotId: string;
  primary: string;
  contrast: string;
  /** Approved, active, eligible candidates currently tagged for this slot. */
  candidates: number;
  /** Candidates that actually carry decisive mass on the slot's primary. */
  measuring: number;
  languages: string[];
  ok: boolean;
  warnings: string[];
};

export type CalibrationPoolReport = {
  calibrationVersion: number;
  generatedAt: string;
  totalEligible: number;
  anchorSlots: AnchorSlotHealth[];
  /** Eligible items with no slot — what adaptive and exploration draw from. */
  openPoolSize: number;
  /** Dimensions the anchor stage measures, whichever candidates rotate in. */
  guaranteedAnchorCoverage: string[];
  /** Dimensions no eligible item measures at all. */
  uncoveredDimensions: string[];
  /** True when calibration can run its full 6/6/3 without degrading. */
  healthy: boolean;
  warnings: string[];
};

function measuresPrimary(item: HumorContentDoc, primary: string): boolean {
  const vector = normalizeHumorVector(item.humorVector, 0);
  return (vector as Record<string, number>)[primary] >= COVERAGE_MASS_THRESHOLD;
}

/**
 * Dimensions guaranteed to be measured by the anchor stage.
 *
 * Deliberately the *intersection* across every candidate of every slot: a
 * dimension only counts as guaranteed if the user gets it no matter which
 * candidate rotation gives them. That is what keeps two users' profiles
 * comparable, so it is the number worth reporting.
 */
function guaranteedCoverage(pools: Map<string, HumorContentDoc[]>): string[] {
  const guaranteed = new Set<string>();
  for (const dim of HUMOR_CATEGORIES) {
    let everySlotCandidateCovers = false;
    for (const [, candidates] of pools) {
      if (candidates.length === 0) {
        continue;
      }
      if (candidates.every((item) => coverageDimensionsOf(item).includes(dim))) {
        everySlotCandidateCovers = true;
        break;
      }
    }
    if (everySlotCandidateCovers) {
      guaranteed.add(dim);
    }
  }
  return [...guaranteed].sort();
}

export async function buildCalibrationPoolReport(
  db: Firestore,
): Promise<CalibrationPoolReport> {
  const eligible = await listCalibrationPool(db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });

  const pools = new Map<string, HumorContentDoc[]>();
  for (const slot of ANCHOR_SLOTS) {
    pools.set(slot.id, []);
  }
  let openPoolSize = 0;
  for (const item of eligible) {
    const slot = item.calibration.slot;
    if (slot && pools.has(slot)) {
      pools.get(slot)!.push(item);
    } else {
      openPoolSize += 1;
    }
  }

  const warnings: string[] = [];
  const anchorSlots: AnchorSlotHealth[] = ANCHOR_SLOTS.map((slot) => {
    const candidates = pools.get(slot.id) ?? [];
    const measuring = candidates.filter((item) =>
      measuresPrimary(item, slot.primary),
    );
    const slotWarnings: string[] = [];
    if (measuring.length === 0) {
      slotWarnings.push("no candidate measures the slot primary");
    } else if (measuring.length < 2) {
      slotWarnings.push("cannot rotate — every user sees the same item");
    } else if (measuring.length < ANCHOR_POOL_TARGET) {
      slotWarnings.push(
        `below the target of ${ANCHOR_POOL_TARGET} interchangeable candidates`,
      );
    }
    if (candidates.length > measuring.length) {
      slotWarnings.push(
        `${candidates.length - measuring.length} tagged candidate(s) do not measure ${slot.primary}`,
      );
    }
    return {
      slotId: slot.id,
      primary: slot.primary,
      contrast: slot.contrast,
      candidates: candidates.length,
      measuring: measuring.length,
      languages: [...new Set(candidates.map((i) => i.language))].sort(),
      ok: measuring.length >= 2,
      warnings: slotWarnings,
    };
  });

  const measuredByAnything = new Set<string>();
  for (const item of eligible) {
    for (const dim of coverageDimensionsOf(item)) {
      measuredByAnything.add(dim);
    }
  }
  const uncoveredDimensions = HUMOR_CATEGORIES.filter(
    (dim) => !measuredByAnything.has(dim),
  );

  // Adaptive (6) and exploration (3) both draw from the open pool, and no item
  // may repeat inside one calibration.
  const openPoolNeeded = CALIBRATION_TOTAL - ANCHOR_SLOTS.length;
  if (openPoolSize < openPoolNeeded) {
    warnings.push(
      `open pool has ${openPoolSize} items, needs ${openPoolNeeded} for adaptive + exploration`,
    );
  }
  for (const slot of anchorSlots) {
    for (const warning of slot.warnings) {
      warnings.push(`${slot.slotId}: ${warning}`);
    }
  }
  if (uncoveredDimensions.length > 0) {
    warnings.push(`no eligible content measures: ${uncoveredDimensions.join(", ")}`);
  }

  const healthy =
    anchorSlots.every((slot) => slot.ok) && openPoolSize >= openPoolNeeded;

  return {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    generatedAt: new Date().toISOString(),
    totalEligible: eligible.length,
    anchorSlots,
    openPoolSize,
    guaranteedAnchorCoverage: guaranteedCoverage(pools),
    uncoveredDimensions,
    healthy,
    warnings,
  };
}
