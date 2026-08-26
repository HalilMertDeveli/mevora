import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {
  isSumsubConfigured,
  resolveSumsubConfig,
  sumsubSecrets,
} from "./sumsubConfig.js";
import {SumsubApiError, SumsubClient} from "./sumsubClient.js";
import {
  VerificationGateError,
  markVerificationStarted,
  parseVerificationRecord,
  verificationRef,
} from "./sumsubVerification.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

/** Returns a short-lived Sumsub SDK access token. Secrets never leave the server. */
export const createSumsubAccessToken = onCall(
  {
    secrets: [...sumsubSecrets],
    enforceAppCheck,
    region: "europe-west1",
  },
  async (request) => {
    const uid = requireUid(request.auth?.uid);
    if (!isSumsubConfigured()) {
      throw new HttpsError("failed-precondition", "verification-not-configured");
    }
    const creds = resolveSumsubConfig();
    if (!creds) {
      throw new HttpsError("failed-precondition", "verification-not-configured");
    }

    const accountSnap = await db.doc(`users/${uid}`).get();
    if (!accountSnap.exists) {
      throw new HttpsError("not-found", "account-not-found");
    }
    if (accountSnap.data()?.isVerified === true) {
      throw new HttpsError("failed-precondition", "already-verified");
    }

    const existing = parseVerificationRecord(
      (await verificationRef(db, uid).get()).data(),
    );
    if (existing.verificationStatus === "approved") {
      throw new HttpsError("failed-precondition", "already-verified");
    }

    try {
      await markVerificationStarted(db, uid, creds.levelName);
    } catch (error) {
      if (error instanceof VerificationGateError) {
        if (error.reason === "cooldown") {
          throw new HttpsError("resource-exhausted", "verification-cooldown", {
            retryAfterSeconds: error.retryAfterSeconds ?? 0,
          });
        }
        if (error.reason === "attempt_limit") {
          throw new HttpsError("resource-exhausted", "verification-attempt-limit");
        }
        if (error.reason === "already_verified") {
          throw new HttpsError("failed-precondition", "already-verified");
        }
      }
      throw error;
    }

    const email = accountSnap.data()?.email as string | undefined;
    const phone = accountSnap.data()?.phoneNumber as string | undefined;
    const client = new SumsubClient(creds.appToken, creds.secretKey, creds.baseUrl);

    try {
      const result = await client.generateAccessToken({
        userId: uid,
        levelName: creds.levelName,
        ttlInSecs: 600,
        email,
        phone,
      });
      return {token: result.token};
    } catch (error) {
      logger.warn("Sumsub token generation failed", {uid, error: String(error)});
      if (error instanceof SumsubApiError) {
        throw new HttpsError("unavailable", "verification-unavailable");
      }
      throw new HttpsError("internal", "verification-unavailable");
    }
  },
);
