import {HttpsError} from "firebase-functions/v2/https";
import {
  EXTERNAL_PROVIDER_ID,
  isExternalMusicApiConfigured,
} from "../externalMusicConfig.js";
import type {MusicProvider, MusicProviderFetchInput} from "./musicProvider.js";
import type {NormalizedMusicProfile} from "../types/normalizedMusicProfile.js";

/**
 * External music provider — API wiring deferred to Phase 4.
 * Normalization helpers live in normalizeExternalMusicProfile.ts.
 */
export class ExternalMusicProvider implements MusicProvider {
  readonly providerId = EXTERNAL_PROVIDER_ID;

  async fetchTaste(_input: MusicProviderFetchInput): Promise<NormalizedMusicProfile> {
    if (!isExternalMusicApiConfigured()) {
      throw new HttpsError("failed-precondition", "external-api-not-configured");
    }
    // Phase 4: HTTP fetch + buildExternalNormalizedProfile(payload)
    throw new HttpsError("unavailable", "external-api-not-implemented");
  }
}
