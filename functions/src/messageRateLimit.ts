import {Timestamp, getFirestore, type DocumentReference} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {messageRateDecision, parseMessageRateState} from "./messageRateLimitPolicy.js";

const db = getFirestore();

/**
 * One transaction on the sender's counter document decides both limits.
 * The per-match limit used to read the match's last 40 messages on every
 * send; the counter already holds what that read reconstructed.
 */
export async function enforceMessageRateLimit(options: {
  matchId: string;
  messageId: string;
  senderId: string;
  type: string;
  messageRef: DocumentReference;
}): Promise<boolean> {
  if (!options.senderId || options.type === "system") {
    return true;
  }
  const nowMs = Date.now();
  const rateRef = db.doc(`users/${options.senderId}/rateLimits/messages`);
  let rejected = null as "match" | "global" | null;
  try {
    await db.runTransaction(async (tx) => {
      rejected = null;
      const snap = await tx.get(rateRef);
      const data = snap.data();
      const windowStart = data?.windowStart instanceof Timestamp
        ? data.windowStart.toMillis()
        : 0;
      const decision = messageRateDecision(parseMessageRateState(data, windowStart), {
        matchId: options.matchId,
        messageId: options.messageId,
        nowMs,
      });
      if (decision.action === "reject") {
        rejected = decision.reason;
        return;
      }
      if (decision.action === "duplicate") {
        return;
      }
      // A full replace, not a merge: a merge would keep per-match counts
      // from the previous window.
      tx.set(rateRef, {
        windowStart: Timestamp.fromMillis(decision.state.windowStartMs),
        count: decision.state.count,
        perMatch: decision.state.perMatch,
        messageIds: decision.state.messageIds,
        updatedAt: Timestamp.fromMillis(nowMs),
      });
    });
  } catch (error) {
    await options.messageRef.delete();
    logger.warn("Message rate limit check failed", {
      senderId: options.senderId,
      matchId: options.matchId,
      error,
    });
    return false;
  }
  if (rejected) {
    await options.messageRef.delete();
    logger.warn(`Message rate limit exceeded (${rejected})`, {
      senderId: options.senderId,
      matchId: options.matchId,
    });
    return false;
  }
  return true;
}
