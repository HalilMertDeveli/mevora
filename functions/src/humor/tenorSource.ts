/**
 * Tenor GIF API — DISABLED.
 * Google sunset the public Tenor API on 2026-06-30.
 * Do not activate; keep stub for explicit fallback documentation.
 */
import type {
  HumorContentSource,
  HumorSourcePage,
} from "./sourceAdapter.js";

export const TENOR_API_STATUS = {
  active: false as const,
  reason: "tenor-public-api-sunset-2026-06-30",
  docs: "https://developers.google.com/tenor",
};

export class TenorHumorSource implements HumorContentSource {
  readonly kind = "licensed_api" as const;
  readonly provider = "tenor";

  static tryCreate(): null {
    return null;
  }

  async getVideos(): Promise<HumorSourcePage> {
    throw new Error(TENOR_API_STATUS.reason);
  }
  async getImages(): Promise<HumorSourcePage> {
    throw new Error(TENOR_API_STATUS.reason);
  }
  async getNextPage(): Promise<HumorSourcePage> {
    throw new Error(TENOR_API_STATUS.reason);
  }
  async search(): Promise<HumorSourcePage> {
    throw new Error(TENOR_API_STATUS.reason);
  }
}
