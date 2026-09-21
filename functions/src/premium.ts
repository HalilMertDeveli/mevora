import {resolvePremiumAccess} from "./subscription/entitlementResolver.js";
import type {PremiumAccess} from "./subscription/types.js";

export type {PremiumAccess};

/**
 * Premium entitlement resolution for backend consumers.
 *
 * All of it now goes through the canonical subscription model in
 * `./subscription`. `users/{uid}/subscription/current` is authoritative; the
 * legacy Auth custom claim only covers users who have no canonical document
 * yet. Clients cannot write either source.
 */
export async function isUserPremium(uid: string): Promise<boolean> {
  const access = await resolvePremiumAccess(uid);
  return access.isPremium;
}

/** Same resolution, with the reason — useful for logs and callable payloads. */
export async function resolveUserPremiumAccess(
  uid: string,
  now: Date = new Date(),
): Promise<PremiumAccess> {
  return resolvePremiumAccess(uid, now);
}
