import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isUserPremium} from "./premium.js";
import {
  shapePartnerQuestionAnswers,
  type PartnerQuestionAnswerRow,
} from "./premiumQuestionAnswersShape.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

function canonicalMatchId(a: string, b: string): string {
  const ids = [a, b].sort();
  return `${ids[0]}_${ids[1]}`;
}

async function hasActiveMatch(a: string, b: string): Promise<boolean> {
  const matchId = canonicalMatchId(a, b);
  const snap = await db.doc(`matches/${matchId}`).get();
  if (!snap.exists) {
    return false;
  }
  const data = snap.data() ?? {};
  if (data.isActive !== true) {
    return false;
  }
  const userIds = Array.isArray(data.userIds) ? data.userIds.map(String) : [];
  return userIds.includes(a) && userIds.includes(b);
}

/**
 * Partner profile question answers — Premium + active match.
 *
 * Free clients must not read peer `questionAnswers` from Firestore (rules deny).
 * This callable is the only unlock path for answer fields.
 *
 * Matching continues to use private `relationshipAnswers` (unchanged).
 */
export const getPartnerQuestionAnswers = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    const partnerUid = String(
      request.data?.partnerUid ?? request.data?.uid ?? "",
    ).trim();
    if (!partnerUid || partnerUid === uid) {
      throw new HttpsError("invalid-argument", "invalid-partner");
    }

    const matched = await hasActiveMatch(uid, partnerUid);
    const premium = await isUserPremium(uid);

    if (!matched) {
      return shapePartnerQuestionAnswers({
        matched: false,
        isPremium: premium,
        rows: [],
      });
    }

    const snap = await db
      .collection(`users/${partnerUid}/questionAnswers`)
      .limit(100)
      .get();

    const rows: PartnerQuestionAnswerRow[] = snap.docs.map((doc) => {
      const data = doc.data();
      return {
        questionId: String(data.questionId ?? doc.id),
        answerId: String(data.answerId ?? ""),
        isVisible: data.isVisible !== false,
      };
    });

    return shapePartnerQuestionAnswers({
      matched: true,
      isPremium: premium,
      rows,
    });
  },
);
