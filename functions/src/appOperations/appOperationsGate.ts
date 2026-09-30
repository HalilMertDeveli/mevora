import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {APP_OPERATIONS_PUBLIC, parseAppOperationsState, type AppFeature, type AppOperationsState} from "./appOperationsConfig.js";

/**
 * Server-side enforcement of the owner's App Control switches.
 *
 * Hiding a button is not enough: an old app build, or a hand-made request,
 * would still reach the callable. Every guarded callable calls this first.
 *
 *   maintenance on          → HttpsError("unavailable", "maintenance")
 *   feature switched off    → HttpsError("unavailable", "feature_disabled")
 *
 * Only member-facing, non-safety operations are guarded. Account deletion,
 * data export, support, report, block, unmatch and appeals are never gated,
 * and neither is verifyBoostPurchase: a store purchase the member already paid
 * for must still be credited.
 *
 * The public projection is cached per Firestore instance for a few seconds so
 * a busy callable does not add a read per request; a switch reaches every
 * instance within CACHE_MS. A config that cannot be read fails open (logged):
 * the switches default to "enabled".
 */

const CACHE_MS = 15_000;
const cache = new WeakMap<Firestore, {atMs: number; state: AppOperationsState}>();

export async function readAppOperationsState(db: Firestore, nowMs = Date.now()): Promise<AppOperationsState> {
  const hit = cache.get(db);
  if (hit && nowMs - hit.atMs < CACHE_MS) {
    return hit.state;
  }
  let state: AppOperationsState;
  try {
    const snap = await db.doc(APP_OPERATIONS_PUBLIC).get();
    state = parseAppOperationsState(snap.data());
  } catch (error) {
    logger.warn("app_operations_config_unreadable", {error: String(error)});
    state = parseAppOperationsState(undefined);
  }
  cache.set(db, {atMs: nowMs, state});
  return state;
}

/** Test hook: forget the cached projection for this Firestore instance. */
export function resetAppOperationsCache(db: Firestore): void {
  cache.delete(db);
}

export async function assertAppFeatureAvailable(db: Firestore, feature: AppFeature | null): Promise<void> {
  const state = await readAppOperationsState(db);
  if (state.maintenance.enabled) {
    throw new HttpsError("unavailable", "maintenance");
  }
  if (feature && !state.features[feature]) {
    throw new HttpsError("unavailable", "feature_disabled", {feature});
  }
}
