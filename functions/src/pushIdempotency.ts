import {createHash} from "node:crypto";

/** Devices read per collection when sending a push. A member has a handful;
 * the cap keeps a stale-token pile from turning one push into a big read. */
export const MAX_DEVICE_TOKENS_PER_COLLECTION = 20;

/**
 * The `notifications/{id}` document for a push that carries an idempotency
 * key. Creating it is the claim: a second delivery of the same event finds
 * it already there and sends nothing.
 */
export function pushNotificationId(uid: string, idempotencyKey: string): string {
  const digest = createHash("sha256").update(`${uid}\u0000${idempotencyKey}`).digest("hex");
  return `push_${digest.slice(0, 40)}`;
}

/** Firestore's ALREADY_EXISTS, as the Admin SDK reports it. */
export function isAlreadyExists(error: unknown): boolean {
  const code = (error as {code?: unknown} | null)?.code;
  return code === 6 || code === "already-exists" || code === "ALREADY_EXISTS";
}
