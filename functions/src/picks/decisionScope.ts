import type {Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {likeId} from "../ids.js";
import {isUserPremium} from "../premium.js";
import {parseBatch} from "./lifecycle.js";
import {picksDocPath} from "./service.js";

/**
 * Where a like or pass may come from.
 *
 * Mevora shows people in two places: the member's daily Picks, and — for
 * Premium — Likes You, the people who already liked them. A decision about
 * anyone else was never offered, so it is refused: a hand-made call must not
 * be able to like or pass its way around the finite daily batch.
 *
 * Active match partners need no scope of their own; both decision callables
 * refuse them as `already-matched` before this runs.
 */
export type DecisionSource = "pick" | "incomingLike";

const POSITIVE_ACTIONS = new Set(["like", "superLike"]);

/**
 * The surface that offered `candidateUid` to `viewerUid`, or null when none
 * did. Picks first — it is where nearly every decision comes from, and costs
 * one read; the Likes You check reads the like and, only if there is one,
 * the member's entitlement.
 *
 * Any state counts in the current batch: a Pick that was already liked,
 * passed or went ineligible was still shown, so a retried decision about it
 * stays idempotent instead of turning into a refusal.
 */
export async function offeredDecisionSource(input: {
  db: Firestore;
  viewerUid: string;
  candidateUid: string;
  isPremium?: (uid: string) => Promise<boolean>;
}): Promise<DecisionSource | null> {
  const {db, viewerUid, candidateUid} = input;
  const batch = parseBatch((await db.doc(picksDocPath(viewerUid)).get()).data());
  if (batch?.picks.some((pick) => pick.candidateUid === candidateUid)) {
    return "pick";
  }
  const incoming = await db.doc(`likes/${likeId(candidateUid, viewerUid)}`).get();
  if (!incoming.exists || !POSITIVE_ACTIONS.has(String(incoming.data()?.action ?? ""))) {
    return null;
  }
  // Likes You names its people to Premium only; for anyone else a liker is
  // not shown, so a decision about them was not offered either.
  const premium = await (input.isPremium ?? isUserPremium)(viewerUid);
  return premium ? "incomingLike" : null;
}

/** Refuses a decision about someone the member was never shown. */
export function assertDecisionOffered(source: DecisionSource | null): DecisionSource {
  if (!source) {
    throw new HttpsError("failed-precondition", "candidate-not-offered");
  }
  return source;
}
