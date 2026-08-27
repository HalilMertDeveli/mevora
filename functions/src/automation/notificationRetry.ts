import {FieldValue, Timestamp, getFirestore, type Firestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import {logger} from "firebase-functions";
import {collectDeviceTokens} from "../notifications.js";

const FAILED_COLLECTION = "failedNotifications";

/**
 * Persist a failed FCM attempt for scheduled retry.
 * Payload must not include message body/plaintext content.
 */
export async function recordFailedNotification(entry: {
  uid: string;
  type: string;
  data: Record<string, string>;
  idempotencyKey: string;
  error: string;
}, db: Firestore = getFirestore()): Promise<void> {
  await db.doc(`${FAILED_COLLECTION}/${entry.idempotencyKey}`).set(
    {
      uid: entry.uid,
      type: entry.type,
      data: entry.data,
      idempotencyKey: entry.idempotencyKey,
      error: entry.error.slice(0, 500),
      attempts: FieldValue.increment(1),
      status: "queued",
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

export async function retryFailedNotifications(
  limit = 50,
  db: Firestore = getFirestore(),
): Promise<{retried: number; succeeded: number; failed: number}> {
  const snap = await db
    .collection(FAILED_COLLECTION)
    .where("status", "==", "queued")
    .limit(limit)
    .get();
  let succeeded = 0;
  let failed = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const uid = String(data.uid ?? "");
    const type = String(data.type ?? "");
    const payload = (data.data as Record<string, string>) ?? {};
    const attempts = Number(data.attempts ?? 0);
    if (!uid || !type) {
      await doc.ref.set({status: "failed", updatedAt: FieldValue.serverTimestamp()}, {merge: true});
      failed += 1;
      continue;
    }
    if (attempts >= 5) {
      await doc.ref.set(
        {status: "manual_review", updatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      failed += 1;
      continue;
    }
    const tokens = await collectDeviceTokens(uid);
    if (tokens.length === 0) {
      await doc.ref.set(
        {status: "succeeded", note: "no_tokens", updatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      succeeded += 1;
      continue;
    }
    try {
      await getMessaging().sendEachForMulticast({
        tokens,
        notification: {title: "Mevora", body: genericBody(type)},
        data: {type, ...payload},
        android: {priority: "high"},
      });
      await doc.ref.set(
        {status: "succeeded", updatedAt: FieldValue.serverTimestamp()},
        {merge: true},
      );
      succeeded += 1;
    } catch (error) {
      logger.warn("notification retry failed", {id: doc.id, error: String(error)});
      await doc.ref.set(
        {
          status: "queued",
          attempts: attempts + 1,
          error: String(error).slice(0, 500),
          nextRetryAt: Timestamp.fromMillis(Date.now() + 60_000 * Math.pow(2, attempts)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      failed += 1;
    }
  }
  return {retried: snap.size, succeeded, failed};
}

function genericBody(type: string): string {
  switch (type) {
  case "newMatch":
    return "You have a new match!";
  case "newMessage":
  case "newPhoto":
  case "newVoice":
    return "New message";
  case "incomingCall":
    return "Incoming video call";
  case "missedCall":
    return "Missed video call";
  case "incomingLike":
    return "Someone liked you";
  default:
    return "Mevora";
  }
}
