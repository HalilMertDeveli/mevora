/**
 * Spotify account identity.
 *
 * Spotify's May 2026 Web API change added `account_id` to `/v1/me`: "a public,
 * immutable, pseudoanonymous identifier for the user's account". The docs are
 * explicit that the older `id` field "should not be used for account linking"
 * — a Spotify user id can change over the life of an account.
 *
 * Mevora's existing `spotifyIndex/{id}` and `musicSpotifyIndex/{id}` documents
 * are keyed by that legacy id. They are live data, so this module resolves an
 * identity that carries both: new links claim the `account_id` key, and lookups
 * fall back to the legacy key so no already-linked account is orphaned.
 *
 * `account_id` is also treated as optional. A token issued before the field
 * existed, or an API that has not rolled it out, must degrade to the legacy id
 * rather than fail the link.
 */

/** The `/v1/me` fields this module needs. Everything else is ignored. */
export type SpotifyIdentityInput = {
  id?: unknown;
  account_id?: unknown;
};

export type SpotifyIdentity = {
  /** Immutable account identifier when Spotify supplied one. */
  accountId: string | null;
  /** Legacy Spotify user id. Still stored for display and back-compat. */
  userId: string;
  /** Key new index documents are written under. */
  primaryKey: string;
  /** Every key that may hold an index document for this account, in lookup order. */
  lookupKeys: string[];
};

function cleanId(value: unknown): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Resolves the identity for a `/v1/me` payload.
 *
 * Throws nothing: callers decide what a missing legacy id means, because the
 * two callables already report that as an `oauth` failure.
 */
export function resolveSpotifyIdentity(
  profile: SpotifyIdentityInput | null | undefined,
): SpotifyIdentity | null {
  const userId = cleanId(profile?.id);
  const accountId = cleanId(profile?.account_id);
  if (!userId && !accountId) {
    return null;
  }
  // A payload with only account_id is valid; the legacy id then mirrors it so
  // downstream display fields and older documents keep a single string.
  const effectiveUserId = userId ?? (accountId as string);
  const primaryKey = accountId ?? effectiveUserId;
  const lookupKeys = accountId && accountId !== effectiveUserId
    ? [accountId, effectiveUserId]
    : [effectiveUserId];
  return {
    accountId,
    userId: effectiveUserId,
    primaryKey,
    lookupKeys,
  };
}

/** An index document as the ownership check sees it. */
export type IndexLookup = {key: string; exists: boolean; uid?: unknown};

export type OwnershipResolution = {
  /** The uid that already owns this Spotify account, if any. */
  ownerUid: string | null;
  /** Index keys that still need a document written for `uid`. */
  missingKeys: string[];
};

/**
 * Folds the index lookups for every key of one Spotify account into a single
 * ownership answer.
 *
 * A legacy-keyed document and an account_id-keyed document describe the same
 * Spotify account, so the first one that exists decides the owner. Keys with no
 * document are reported so the caller can backfill them and converge the two
 * over time without a migration job.
 */
export function resolveIndexOwnership(
  lookups: IndexLookup[],
): OwnershipResolution {
  let ownerUid: string | null = null;
  const missingKeys: string[] = [];
  for (const lookup of lookups) {
    if (!lookup.exists) {
      missingKeys.push(lookup.key);
      continue;
    }
    const uid = typeof lookup.uid === "string" ? lookup.uid.trim() : "";
    if (ownerUid === null) {
      // An existing document with an unusable uid still counts as claimed:
      // silently taking it over would move ownership of a linked account.
      ownerUid = uid.length > 0 ? uid : "";
    }
  }
  return {ownerUid, missingKeys};
}
