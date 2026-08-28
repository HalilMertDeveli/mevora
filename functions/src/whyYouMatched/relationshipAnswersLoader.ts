import type {Firestore} from "firebase-admin/firestore";
import {
  answersFromSummary,
  isValidRelationshipAnswer,
  type RelationshipAnswers,
} from "../relationshipCompatibility.js";

/** Loads relationship Q&A answers for WYM (Admin SDK only — never sent to client). */
export async function loadRelationshipAnswers(
  db: Firestore,
  uid: string,
): Promise<RelationshipAnswers> {
  const summarySnap = await db.doc(`users/${uid}/relationshipMatch/summary`).get();
  const fromSummary = answersFromSummary(summarySnap.data());
  if (Object.keys(fromSummary).length > 0) {
    return fromSummary;
  }

  const snap = await db
    .collection(`users/${uid}/relationshipAnswers`)
    .limit(120)
    .get();
  const answers: RelationshipAnswers = {};
  for (const doc of snap.docs) {
    const answerId = doc.data().answerId;
    if (
      typeof answerId === "string" &&
      isValidRelationshipAnswer(doc.id, answerId)
    ) {
      answers[doc.id] = answerId;
    }
  }
  return answers;
}
