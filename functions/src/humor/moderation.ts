import type {HumorSafetyFlags, HumorSafetyStatus} from "./types.js";

export const HUMOR_SAFETY_STATUSES: readonly HumorSafetyStatus[] = [
  "pending",
  "approved",
  "rejected",
  "needs_review",
] as const;

export function isHumorSafetyStatus(value: unknown): value is HumorSafetyStatus {
  return (
    typeof value === "string" &&
    (HUMOR_SAFETY_STATUSES as readonly string[]).includes(value)
  );
}

export function emptySafetyFlags(
  overrides: Partial<HumorSafetyFlags> = {},
): HumorSafetyFlags {
  return {
    nsfw: false,
    hate: false,
    harassment: false,
    violent: false,
    illegal: false,
    sexual: false,
    minorRelated: false,
    extreme: false,
    ...overrides,
  };
}

/**
 * Deterministic safety gate for ingest. AI may propose flags; this decides status.
 * Zero-tolerance: minorRelated / illegal / extreme → rejected.
 */
export function classifyHumorSafety(flags: Partial<HumorSafetyFlags> | null | undefined): {
  status: HumorSafetyStatus;
  flags: HumorSafetyFlags;
} {
  const normalized = emptySafetyFlags(flags ?? {});
  if (normalized.minorRelated || normalized.illegal || normalized.extreme) {
    return {status: "rejected", flags: normalized};
  }
  const borderline =
    normalized.nsfw ||
    normalized.hate ||
    normalized.harassment ||
    normalized.violent ||
    normalized.sexual;
  if (borderline) {
    return {status: "needs_review", flags: normalized};
  }
  return {status: "approved", flags: normalized};
}

export function canServeHumorContent(input: {
  active: boolean;
  safetyStatus: HumorSafetyStatus | string;
}): boolean {
  return input.active === true && input.safetyStatus === "approved";
}
