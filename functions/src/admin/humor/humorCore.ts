import {buildHumorCoreSequenceReport} from "../../humor/coreService.js";
import type {AdminDeps} from "../deps.js";

/**
 * The Humor Core sequence, surfaced read-only in the console.
 *
 * Every position (V1 …) with what it measures and whether a member can be
 * given it right now. There is deliberately no command here that changes the
 * sequence: the order lives in `humor/coreSequence.ts` and is frozen by a lock
 * fixture, so a change is a reviewed commit, never a click.
 */

function httpsOrNull(value: string | null): string | null {
  return typeof value === "string" && /^https:\/\//.test(value) ? value : null;
}

export async function listHumorCoreSequence(deps: AdminDeps) {
  const report = await buildHumorCoreSequenceReport(deps.db);
  return {
    released: report.released,
    onboardingCount: report.onboardingCount,
    dailyCount: report.dailyCount,
    total: report.total,
    servableCount: report.servableCount,
    healthy: report.healthy,
    problems: report.problems,
    warnings: report.warnings,
    items: report.items.map((item) => ({
      position: item.position,
      contentId: item.contentId,
      onboarding: item.onboarding,
      // "active" is the sequence's word; "retired" is its opposite.
      coreStatus: item.active ? "active" : "retired",
      retiredReason: item.retiredReason,
      supersedes: item.supersedes,
      servable: item.servable,
      contentExists: item.exists,
      contentActive: item.contentActive,
      safetyStatus: item.safetyStatus,
      type: item.type,
      category: item.category,
      vectorSummary: item.topDimensions,
      provider: item.provider,
      sourceTrust: item.sourceTrust,
      previewUrl: httpsOrNull(item.thumbUrl),
      ratingCount: item.ratingCount,
    })),
  };
}
