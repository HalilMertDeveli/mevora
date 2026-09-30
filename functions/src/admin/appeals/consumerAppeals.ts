import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {effectiveAccountStatus} from "../../profileSafety.js";
import {safeLogMeta} from "../../security/logHygiene.js";
import {ACTION_COLLECTION, APPEALABLE_ACTION_TYPES} from "../actions/actionTypes.js";
import {AdminError} from "../errors.js";
import {iso, toMillis} from "../validation.js";
import {APPEAL_COLLECTION, APPEAL_WINDOW_DAYS, appealIdFor, openAppeal} from "./appealService.js";

/**
 * Member-facing moderation callables. Ordinary consumer callables: App Check
 * enforced exactly like every other one. They work for a suspended member
 * (who can still sign in) — being restricted must never remove the way to
 * contest the restriction. A banned member's Auth account is disabled, so
 * ban appeals arrive through the public support site and staff file them.
 *
 * Nothing here exposes who decided, internal notes, or case details.
 */

const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {enforceAppCheck, region: "europe-west1" as const};

function requireUid(request: CallableRequest): string {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return request.auth.uid;
}

/** What the member sees about decisions concerning them. */
export async function buildMyModerationStatus(db: FirebaseFirestore.Firestore, uid: string, nowMs: number) {
  const [account, actions, appeals] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.collection(ACTION_COLLECTION).where("targetUserId", "==", uid).orderBy("createdAt", "desc").limit(20).get(),
    db.collection(APPEAL_COLLECTION).where("userId", "==", uid).orderBy("createdAt", "desc").limit(20).get(),
  ]);
  const appealByAction = new Map(appeals.docs.map((a) => [String(a.get("moderationActionId")), a]));
  const suspendedUntil = toMillis(account.get("suspendedUntil"));
  return {
    accountStatus: effectiveAccountStatus(account.data(), nowMs),
    suspendedUntil: suspendedUntil && suspendedUntil > nowMs ? new Date(suspendedUntil).toISOString() : null,
    statusReasonCode: account.get("statusReasonCode") ?? null,
    decisions: actions.docs
      .filter((doc) => APPEALABLE_ACTION_TYPES.includes(doc.get("type")))
      .map((doc) => {
        const appeal = appealByAction.get(doc.id);
        const effectiveMs = toMillis(doc.get("effectiveAt")) ?? toMillis(doc.get("createdAt")) ?? nowMs;
        const windowOpen = nowMs - effectiveMs <= APPEAL_WINDOW_DAYS * 24 * 60 * 60 * 1000;
        return {
          actionId: doc.id,
          type: doc.get("type"),
          reasonCode: doc.get("reasonCode") ?? null,
          message: doc.get("userMessage") ?? null,
          effectiveAt: iso(doc.get("effectiveAt") ?? doc.get("createdAt")),
          expiresAt: iso(doc.get("expiresAt")),
          overturned: Boolean(doc.get("overturnedByActionId")),
          appealable: !appeal && windowOpen && !doc.get("overturnedByActionId"),
          appeal: appeal
            ? {
              appealId: appeal.id,
              status: appeal.get("status") ?? "open",
              decision: appeal.get("decision") ?? null,
              message: appeal.get("resolution")?.userMessage ?? null,
            }
            : null,
        };
      }),
  };
}

export const getMyModerationStatus = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  return buildMyModerationStatus(getFirestore(), uid, Date.now());
});

export const submitModerationAppeal = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const actionId = typeof request.data?.actionId === "string" ? request.data.actionId.trim() : "";
  const reason = typeof request.data?.reason === "string" ? request.data.reason.trim() : "";
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(actionId)) {
    throw new HttpsError("invalid-argument", "actionId");
  }
  if (reason.length < 10 || reason.length > 2000) {
    throw new HttpsError("invalid-argument", "reason");
  }
  try {
    const result = await openAppeal(getFirestore(), {
      userId: uid,
      moderationActionId: actionId,
      reason,
      source: "app",
      sourceTicketId: null,
      openedBy: uid,
      openedByRole: "member",
      requestId: null,
    }, Date.now());
    return {appealId: result.appealId, created: result.created};
  } catch (error) {
    if (error instanceof AdminError) {
      throw new HttpsError("failed-precondition", error.code);
    }
    logger.error("submitModerationAppeal failed", safeLogMeta({uid, error: String(error)}));
    throw new HttpsError("internal", "appeal-unavailable");
  }
});

export {appealIdFor};
