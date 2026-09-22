import {getAuth} from "firebase-admin/auth";
import {evaluatePremiumAccess} from "./entitlementPolicy.js";
import {readCanonicalSubscription} from "./firestoreEntitlementStore.js";
import type {PremiumAccess} from "./types.js";

const FREE: PremiumAccess = {
  isPremium: false,
  reason: "no_subscription",
  accessUntil: null,
};

/**
 * Legacy Auth custom claim, consulted only when no canonical subscription
 * document exists. Claims are derived/cache data: the Admin SDK is the only
 * writer, and the canonical document always wins when both are present.
 */
async function hasLegacyPremiumClaim(uid: string): Promise<boolean> {
  try {
    const user = await getAuth().getUser(uid);
    return user.customClaims?.premium === true;
  } catch {
    return false;
  }
}

/**
 * The single authoritative Premium resolution for the backend.
 *
 * Order matters: the canonical `users/{uid}/subscription/current` document is
 * authoritative whenever it exists. Only when a user has no canonical document
 * at all — pre-P0 manual grants — does the legacy custom claim apply. The two
 * sources therefore cannot permanently disagree.
 */
export async function resolvePremiumAccess(
  uid: string,
  now: Date = new Date(),
): Promise<PremiumAccess> {
  if (!uid) {
    return FREE;
  }
  const canonical = await readCanonicalSubscription(uid);
  if (canonical) {
    return evaluatePremiumAccess(canonical, now);
  }
  if (await hasLegacyPremiumClaim(uid)) {
    return {isPremium: true, reason: "legacy_claim", accessUntil: null};
  }
  return FREE;
}
