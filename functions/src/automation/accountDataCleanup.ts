import {FieldValue, type Firestore, type DocumentReference} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";

const BATCH_LIMIT = 400;

/** Bounds a single deletion pass so one account cannot run the callable out of time. */
export const MAX_MATCHES_PER_PASS = 200;
export const MAX_SUPPORT_TICKETS_PER_PASS = 100;

/** Minimal Storage surface used here — keeps the helpers testable without a bucket. */
export type BucketLike = {
  file(path: string): {delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>};
  deleteFiles(options: {prefix: string}): Promise<unknown>;
};

async function commitDeletes(db: Firestore, refs: DocumentReference[]): Promise<void> {
  for (let i = 0; i < refs.length; i += BATCH_LIMIT) {
    const chunk = db.batch();
    for (const ref of refs.slice(i, i + BATCH_LIMIT)) {
      chunk.delete(ref);
    }
    await chunk.commit();
  }
}

/**
 * DL-2 — the deleting user's own messages are erased; the peer's are not.
 *
 * Hard-deleting the whole thread would destroy the peer's copy of a conversation
 * they are also a party to. Instead each message authored by `uid` is reduced to
 * the tombstone the app already understands (`deleted: true` with the content
 * fields cleared — the same shape `firestore.rules` permits a sender to write),
 * so the peer keeps their own history and sees a deleted-content marker where the
 * departed user's messages were.
 *
 * Returns the number of messages tombstoned. Idempotent: re-running writes the
 * same values over an already-tombstoned message.
 */
export async function anonymizeDeletedUserMessages(
  db: Firestore,
  uid: string,
  matchRef: DocumentReference,
): Promise<number> {
  const authored = await matchRef.collection("messages").where("senderId", "==", uid).get();
  if (authored.empty) {
    return 0;
  }

  for (let i = 0; i < authored.docs.length; i += BATCH_LIMIT) {
    const chunk = db.batch();
    for (const doc of authored.docs.slice(i, i + BATCH_LIMIT)) {
      chunk.set(
        doc.ref,
        {
          deleted: true,
          text: "",
          mediaUrl: null,
          imageStoragePath: null,
          voiceStoragePath: null,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    await chunk.commit();
  }
  return authored.size;
}

/**
 * The match document carries a `lastMessage` preview that can hold the deleting
 * user's plaintext. Clear it only when the newest message is theirs, so the peer
 * keeps the preview of their own last message.
 */
export async function clearLastMessagePreviewIfAuthored(
  uid: string,
  matchRef: DocumentReference,
): Promise<boolean> {
  const newest = await matchRef
    .collection("messages")
    .orderBy("createdAt", "desc")
    .limit(1)
    .get();
  if (newest.empty || String(newest.docs[0].get("senderId") ?? "") !== uid) {
    return false;
  }
  await matchRef.set({lastMessage: ""}, {merge: true});
  return true;
}

/**
 * DL-3 — moderation evidence outlives the account it concerns.
 *
 * A reported user must not be able to erase the report trail by deleting their
 * account, and a report filed *by* the departing user is evidence about someone
 * else. So reports are retained and flagged rather than deleted. No new identifier
 * is introduced: the uid already present on the document stays as the (now
 * unresolvable) pseudonym that correlates repeat reports about the same person.
 *
 * Retained reports stay out of normal app flows — `firestore.rules` exposes a
 * report only to an admin or to its own reporter, and the deleted user can no
 * longer authenticate.
 *
 * Retention *duration* is deliberately not set here: no policy defines one. See
 * the open item in the final report.
 */
export async function flagModerationRecordsForDeletedUser(
  db: Firestore,
  uid: string,
): Promise<{reports: number; humorReports: number}> {
  const [filed, against, humor] = await Promise.all([
    db.collection("reports").where("reporterId", "==", uid).get(),
    db.collection("reports").where("reportedUserId", "==", uid).get(),
    db.collection("humorReports").where("reporterId", "==", uid).get(),
  ]);

  const stamp = FieldValue.serverTimestamp();
  const writes: Array<[DocumentReference, Record<string, unknown>]> = [];
  for (const doc of filed.docs) {
    writes.push([doc.ref, {reporterDeleted: true, reporterDeletedAt: stamp}]);
  }
  for (const doc of against.docs) {
    writes.push([doc.ref, {reportedUserDeleted: true, reportedUserDeletedAt: stamp}]);
  }
  for (const doc of humor.docs) {
    writes.push([doc.ref, {reporterDeleted: true, reporterDeletedAt: stamp}]);
  }

  for (let i = 0; i < writes.length; i += BATCH_LIMIT) {
    const chunk = db.batch();
    for (const [ref, patch] of writes.slice(i, i + BATCH_LIMIT)) {
      chunk.set(ref, patch, {merge: true});
    }
    await chunk.commit();
  }

  return {
    reports: filed.size + against.size,
    humorReports: humor.size,
  };
}

/**
 * Support attachments live at `support/{ticketId}/...` — outside both prefixes the
 * account sweep clears, so they used to survive deletion entirely.
 *
 * Ownership is resolved from Firestore (`supportTickets.userId`), never from the
 * object path: only tickets that provably belong to `uid` are touched, so one
 * user's deletion can never reach another user's attachment. Objects named on the
 * ticket are deleted explicitly, then the ticket's own prefix is swept to catch
 * uploads the document never recorded.
 *
 * Returns the ticket ids so the verification job can re-check them after the
 * ticket documents themselves are gone.
 */
export async function deleteSupportAttachmentsForUser(
  db: Firestore,
  bucket: BucketLike,
  uid: string,
): Promise<{ticketIds: string[]; objectsDeleted: number}> {
  const tickets = await db
    .collection("supportTickets")
    .where("userId", "==", uid)
    .limit(MAX_SUPPORT_TICKETS_PER_PASS)
    .get();

  const ticketIds: string[] = [];
  let objectsDeleted = 0;

  for (const ticket of tickets.docs) {
    ticketIds.push(ticket.id);
    const data = ticket.data();
    const paths = new Set<string>();
    for (const entry of (data.attachments as unknown[] | undefined) ?? []) {
      if (typeof entry === "string" && entry.startsWith(`support/${ticket.id}/`)) {
        paths.add(entry);
      }
    }
    const legacy = data.attachmentUrl;
    if (typeof legacy === "string" && legacy.startsWith(`support/${ticket.id}/`)) {
      paths.add(legacy);
    }

    for (const path of paths) {
      try {
        await bucket.file(path).delete({ignoreNotFound: true});
        objectsDeleted += 1;
      } catch (error) {
        logger.warn(
          "support attachment delete failed",
          safeLogMeta({ticketId: ticket.id, error: String(error)}),
        );
      }
    }

    // Safety net for uploads the ticket document never recorded. Scoped to this
    // ticket's own prefix, which we have already proven belongs to `uid`.
    try {
      await bucket.deleteFiles({prefix: `support/${ticket.id}/`});
    } catch (error) {
      logger.warn(
        "support attachment prefix sweep failed",
        safeLogMeta({ticketId: ticket.id, error: String(error)}),
      );
    }
  }

  return {ticketIds, objectsDeleted};
}

/**
 * User-scoped leftovers that no other sweep covers. Each is keyed by the uid
 * itself, so this deletes nothing shared. Missing documents are a no-op, which is
 * what makes a repeated deletion safe.
 */
export async function deleteUserScopedRemnants(db: Firestore, uid: string): Promise<void> {
  await commitDeletes(db, [
    db.doc(`authRateLimits/spotify_${uid}`),
  ]);
}
