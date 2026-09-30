import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {isAccountEligible} from "./profileSafety.js";

/**
 * The one reusable eligibility gate for social callables.
 *
 * A suspended or banned account keeps safety tools (report, block, unmatch,
 * delete, export, support, appeal) but loses everything that reaches another
 * member: discovery, likes, incoming likes, boosts, calls and compatibility
 * lookups. The error string is the one the client already recognises.
 */
export async function assertCallerAccountEligible(db: Firestore, uid: string): Promise<void> {
  const snap = await db.doc(`users/${uid}`).get();
  if (!isAccountEligible(snap.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
}
