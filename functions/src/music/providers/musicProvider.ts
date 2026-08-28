import type {NormalizedMusicProfile} from "../types/normalizedMusicProfile.js";

/** Minimum provider contract for taste ingestion. */
export interface MusicProvider {
  readonly providerId: string;
  fetchTaste(input: MusicProviderFetchInput): Promise<NormalizedMusicProfile>;
}

export type MusicProviderFetchInput = {
  accessToken: string;
  scope?: string;
  providerUserId?: string;
  displayName?: string | null;
};
