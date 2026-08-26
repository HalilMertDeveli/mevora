import {Timestamp, getFirestore, type DocumentReference} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

const db = getFirestore();

const WINDOW_MS = 60_000;
const MAX_MESSAGES_PER_MATCH = 20;
const MAX_MESSAGES_GLOBAL = 60;

function isWithinWindow(createdAt: unknown, nowMs: number): boolean {
  if (!(createdAt instanceof Timestamp)) {
    return false;
  }
  return createdAt.toMillis() >= nowMs - WINDOW_MS;
}

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
  const recentInMatch = await db
    .collection(`matches/${options.matchId}/messages`)
    .orderBy("createdAt", "desc")
    .limit(40)
    .get();
  const senderInMatch = recentInMatch.docs.filter(
    (doc) =>
      doc.id !== options.messageId &&
      doc.get("senderId") === options.senderId &&
      isWithinWindow(doc.get("createdAt"), nowMs),
  );
  if (senderInMatch.length >= MAX_MESSAGES_PER_MATCH) {
    await options.messageRef.delete();
    logger.warn("Message rate limit exceeded (match)", {
      senderId: options.senderId,
      matchId: options.matchId,
    });
    return false;
  }

  const rateRef = db.doc(`users/${options.senderId}/rateLimits/messages`);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(rateRef);
      const data = snap.data() ?? {};
      const previousWindow = data.windowStart instanceof Timestamp
        ? data.windowStart.toMillis()
        : 0;
      let count = Number(data.count ?? 0);
      let windowStart = previousWindow;
      if (nowMs - previousWindow > WINDOW_MS) {
        windowStart = nowMs;
        count = 0;
      }
      if (count >= MAX_MESSAGES_GLOBAL) {
        throw new Error("global-rate-limit");
      }
      tx.set(
        rateRef,
        {
          windowStart: Timestamp.fromMillis(windowStart),
          count: count + 1,
          updatedAt: Timestamp.fromMillis(nowMs),
        },
        {merge: true},
      );
    });
  } catch (error) {
    await options.messageRef.delete();
    logger.warn("Message rate limit exceeded (global)", {
      senderId: options.senderId,
      matchId: options.matchId,
      error,
    });
    return false;
  }
  return true;
}
