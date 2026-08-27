export type HumorSourceKind = "internal" | "licensed_api";

export class InternalHumorSourceAdapter {
  readonly kind: HumorSourceKind = "internal";
  readonly provider = "mevora-internal";
}

/** Stub for future licensed providers. Not wired in MVP runtime. */
export class LicensedApiHumorSourceAdapter {
  readonly kind: HumorSourceKind = "licensed_api";
  constructor(readonly provider: string) {}
}

export function resolveHumorSourceAdapter(
  kind: HumorSourceKind = "internal",
  provider = "mevora-internal",
): InternalHumorSourceAdapter | LicensedApiHumorSourceAdapter {
  if (kind === "licensed_api") {
    return new LicensedApiHumorSourceAdapter(provider);
  }
  return new InternalHumorSourceAdapter();
}
