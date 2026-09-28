import {PICK_COMPOSITION} from "./config.js";
import {buildPickReasons, evaluateCandidate, passesQualityFloor, rankLabels} from "./categories.js";
import type {ComposedPick, PickEvaluation, PickSignals, PickType} from "./types.js";
import type {Adjustments} from "../personalization/learner.js";
import {
  explorationScore,
  explorationSlotCount,
  explorationSlotPositions,
  isExplorationCandidate,
  isPersonalizationActive,
  personalRankingPoints,
  vectorFromSignals,
} from "../personalization/ranking.js";

/**
 * Batch composition for Mevora Picks.
 *
 *   candidate pool (already through the canonical Discover eligibility chain)
 *     → quality floor → category qualification
 *     → rank by canonical overall compatibility
 *     → greedy selection with bounded diversity and bounded Boost
 *     → at most `targetCount`, fewer when quality runs out
 *
 * Deterministic: every ordering breaks ties on uid, and nothing reads the
 * clock or a random source. Reopening the app never reshuffles a batch.
 */

function byOverallThenUid(a: PickSignals, b: PickSignals): number {
  if (b.overall !== a.overall) return b.overall - a.overall;
  return a.uid.localeCompare(b.uid);
}

/** Qualify a whole pool. Best Overall's relative bar needs the pool's order. */
export function evaluatePool(signals: PickSignals[]): PickEvaluation[] {
  const floorPassers = signals.filter(passesQualityFloor).sort(byOverallThenUid);
  const rankByUid = new Map(floorPassers.map((item, index) => [item.uid, index]));
  return signals.map((item) =>
    evaluateCandidate(item, rankByUid.get(item.uid) ?? Number.POSITIVE_INFINITY),
  );
}

export interface ComposeOptions {
  targetCount: number;
  /** Picks already live in this batch (a top-up), so diversity counts them. */
  existing?: Array<{pickType: PickType; isBoosted: boolean}>;
  /** First rank to hand out (a top-up continues after the existing ones). */
  firstRank?: number;
  /**
   * The viewer's effective observed adjustments (all 1.00 when switched off
   * or nothing is learned). Absent means canonical ranking, exactly as before.
   */
  personalization?: {
    viewerUid: string;
    /** Stable for the batch, so exploration never reshuffles on reopen. */
    batchKey: string;
    adjustments: Adjustments;
  };
}

/**
 * Choose which label to lead with, given what the batch already shows: the
 * candidate's strongest label not yet used, else its strongest. Unexpected
 * Match is skipped once its per-batch cap is reached.
 */
function chooseDisplayType(
  evaluation: PickEvaluation,
  used: Map<PickType, number>,
): PickType | null {
  const ranked = rankLabels(evaluation).filter(
    (type) =>
      type !== "unexpectedMatch" ||
      (used.get("unexpectedMatch") ?? 0) < PICK_COMPOSITION.maxUnexpectedPerBatch,
  );
  if (ranked.length === 0) return null;
  return ranked.find((type) => (used.get(type) ?? 0) === 0) ?? ranked[0];
}

export function composePicks(
  evaluations: PickEvaluation[],
  options: ComposeOptions,
): ComposedPick[] {
  const used = new Map<PickType, number>();
  let boostedUsed = 0;
  for (const existing of options.existing ?? []) {
    used.set(existing.pickType, (used.get(existing.pickType) ?? 0) + 1);
    if (existing.isBoosted) boostedUsed += 1;
  }
  const slots = Math.max(0, options.targetCount - (options.existing?.length ?? 0));
  const eligible = evaluations.filter((item) => item.passesFloor && item.labels.length > 0);
  // Inside the preferred radius first; beyond it only when that runs out —
  // the same order Discover's radius ladder uses.
  const stages = [
    eligible.filter((item) => item.signals.withinPreferredRadius),
    eligible.filter((item) => !item.signals.withinPreferredRadius),
  ];

  // Adaptive personalization: a bounded per-candidate ranking term from the
  // viewer's learned adjustments, and — once anything has been learned — a
  // minority of exploration slots. Both sit on top of the quality floor and
  // the eligibility chain, never instead of them.
  const personalization = options.personalization ?? null;
  const personalPoints = new Map<string, number>();
  if (personalization) {
    for (const item of eligible) {
      const {points} = personalRankingPoints(
        vectorFromSignals(item.signals),
        personalization.adjustments,
      );
      personalPoints.set(item.signals.uid, points);
    }
  }
  const exploreSlots = explorationSlotPositions(
    slots,
    explorationSlotCount(
      slots,
      personalization !== null && isPersonalizationActive(personalization.adjustments),
    ),
  );

  const chosen: ComposedPick[] = [];
  let rank = options.firstRank ?? 0;
  for (const stage of stages) {
    const remaining = [...stage];
    while (chosen.length < slots && remaining.length > 0) {
      const exploring = personalization !== null && exploreSlots.has(chosen.length);
      const pickBest = (explore: boolean) => {
        let best: {index: number; type: PickType; adjusted: number; boosted: boolean} | null = null;
        for (let i = 0; i < remaining.length; i++) {
          const item = remaining[i];
          const personal = personalPoints.get(item.signals.uid) ?? 0;
          if (explore && !isExplorationCandidate(item.signals.overall, personal)) continue;
          const type = chooseDisplayType(item, used);
          if (type === null) continue;
          // Once the batch carries its boosted profile, further boosted people
          // compete on compatibility alone — exactly as if they had not bought.
          // An exploration slot is never bought: Boost does not apply there.
          const boostApplies =
            !explore &&
            item.signals.isBoosted && boostedUsed < PICK_COMPOSITION.maxBoostedPerBatch;
          const penalty = Math.min(
            PICK_COMPOSITION.maxRepeatPenalty,
            PICK_COMPOSITION.repeatPenalty * (used.get(type) ?? 0),
          );
          const base = explore && personalization
            ? explorationScore(
                item.signals.overall,
                personalization.viewerUid,
                item.signals.uid,
                personalization.batchKey,
              )
            : item.signals.overall + personal;
          const adjusted = base + (boostApplies ? PICK_COMPOSITION.boostBonus : 0) - penalty;
          if (
            best === null ||
            adjusted > best.adjusted ||
            (adjusted === best.adjusted &&
              byOverallThenUid(item.signals, remaining[best.index].signals) < 0)
          ) {
            best = {index: i, type, adjusted, boosted: boostApplies};
          }
        }
        return best;
      };
      // No strong candidate outside the learned pattern: the slot stays a
      // normal one rather than lowering the bar.
      const explored = exploring ? pickBest(true) : null;
      const best = explored ?? pickBest(false);
      if (best === null) break;
      const [picked] = remaining.splice(best.index, 1);
      used.set(best.type, (used.get(best.type) ?? 0) + 1);
      if (best.boosted) boostedUsed += 1;
      chosen.push({
        candidateUid: picked.signals.uid,
        rank: rank++,
        pickType: best.type,
        labels: rankLabels(picked),
        reasons: buildPickReasons(picked, best.type),
        overallScore: picked.signals.overall,
        isBoosted: picked.signals.isBoosted,
        selectionStrategy: explored ? "explore" : "exploit",
      });
    }
  }
  return chosen;
}
