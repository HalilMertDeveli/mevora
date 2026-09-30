import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {caseKeyId} from "./cases/caseService.js";
import {ACTIVE_CASE_STATUSES, CASE_COLLECTION, CASE_KEY_COLLECTION} from "./cases/caseTypes.js";
import {LOOKUP_COLLECTION} from "./users/userLookup.js";

/**
 * What account deletion does to the Trust & Safety records.
 *
 * Deleted with the member (their own content, or an index of it):
 *   - appeals they wrote
 *   - the support thread and internal notes under each of their tickets
 *     (deleteUserAccount already removes the ticket documents; Firestore does
 *     not cascade to subcollections, so they are removed here first)
 *   - their adminUserLookup row
 *
 * Kept, by policy (docs/ADMIN_TRUST_SAFETY_ARCHITECTURE.md §Deletion):
 *   - moderationActions and adminAuditLog — the record of decisions staff
 *     took, needed to show a ban was applied lawfully and to detect ban
 *     evasion. They reference the member by uid only (no name, email,
 *     phone or message content) and expire under the retention policy.
 *   - moderationCases — closed as `subject_deleted` so they leave the queue;
 *     their reports are deleted by deleteUserAccount, so a case keeps only
 *     reason codes and counts.
 */
export async function purgeTrustSafetyUserData(db: Firestore, uid: string): Promise<{
  appeals: number;
  supportThreadDocs: number;
  casesClosed: number;
}> {
  const BATCH = 400;
  const deleteRefs = async (refs: FirebaseFirestore.DocumentReference[]) => {
    for (let i = 0; i < refs.length; i += BATCH) {
      const batch = db.batch();
      refs.slice(i, i + BATCH).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
  };

  const [appeals, tickets, cases] = await Promise.all([
    db.collection("appeals").where("userId", "==", uid).limit(200).get(),
    db.collection("supportTickets").where("userId", "==", uid).limit(100).get(),
    db.collection(CASE_COLLECTION)
      .where("subjectUserId", "==", uid)
      .where("status", "in", [...ACTIVE_CASE_STATUSES])
      .limit(100)
      .get(),
  ]);

  const threadRefs: FirebaseFirestore.DocumentReference[] = [];
  for (const ticket of tickets.docs) {
    const [messages, notes] = await Promise.all([
      ticket.ref.collection("messages").limit(500).get(),
      ticket.ref.collection("internalNotes").limit(500).get(),
    ]);
    threadRefs.push(...messages.docs.map((d) => d.ref), ...notes.docs.map((d) => d.ref));
  }

  await deleteRefs([
    ...appeals.docs.map((d) => d.ref),
    ...threadRefs,
    db.doc(`${LOOKUP_COLLECTION}/${uid}`),
  ]);

  for (const doc of cases.docs) {
    const batch = db.batch();
    batch.set(doc.ref, {
      status: "dismissed",
      resolution: {outcome: "dismissed", code: "subject_deleted"},
      resolvedBy: "system",
      resolvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    const key = doc.get("correlationKey");
    if (typeof key === "string" && key) {
      batch.delete(db.doc(`${CASE_KEY_COLLECTION}/${caseKeyId(key)}`));
    }
    await batch.commit();
  }

  return {appeals: appeals.size, supportThreadDocs: threadRefs.length, casesClosed: cases.size};
}
