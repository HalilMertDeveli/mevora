import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {
  verifyWebhookDigest,
  type WebhookDigestAlgorithm,
} from "./sumsubAuth.js";
import {
  isSumsubWebhookConfigured,
  resolveSumsubWebhookSecret,
  sumsubSecrets,
} from "./sumsubConfig.js";
import {
  mapSumsubToVerificationStatus,
  shouldSetVerified,
  type SumsubWebhookPayload,
} from "./sumsubStatus.js";
import {
  VERIFICATION_DOC_ID,
  parseVerificationRecord,
  verificationRef,
} from "./sumsubVerification.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

function webhookCorrelationId(payload: SumsubWebhookPayload, rawBody: string): string {
  const applicantId = String(payload.applicantId ?? "");
  const type = String(payload.type ?? "");
  const reviewStatus = String(payload.reviewStatus ?? "");
  const answer = String(payload.reviewResult?.reviewAnswer ?? "");
  return `${applicantId}:${type}:${reviewStatus}:${answer}:${rawBody.length}`;
}

/** Authoritative Sumsub verification webhook. Clients never set verified state. */
export const sumsubWebhook = onRequest(
  {
    secrets: [...sumsubSecrets],
    region: "europe-west1",
    cors: false,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    if (!isSumsubWebhookConfigured()) {
      logger.error("Sumsub webhook secret not configured");
      res.status(503).send("Not configured");
      return;
    }

    const secret = resolveSumsubWebhookSecret();
    if (!secret) {
      logger.error("Sumsub webhook secret not configured");
      res.status(503).send("Not configured");
      return;
    }

    const rawBody = typeof req.rawBody === "string"
      ? req.rawBody
      : req.rawBody?.toString("utf8") ?? "";
    if (!rawBody) {
      res.status(400).send("Empty body");
      return;
    }

    const digestHeader = String(req.headers["x-payload-digest"] ?? "");
    const digestAlg = String(req.headers["x-payload-digest-alg"] ?? "HMAC_SHA256_HEX") as WebhookDigestAlgorithm;
    if (!digestHeader) {
      res.status(401).send("Missing digest");
      return;
    }

    const valid = verifyWebhookDigest({
      secretKey: secret,
      rawBody,
      digest: digestHeader,
      algorithm: digestAlg,
    });
    if (!valid) {
      logger.warn("Sumsub webhook digest mismatch");
      res.status(401).send("Invalid digest");
      return;
    }

    let payload: SumsubWebhookPayload;
    try {
      payload = JSON.parse(rawBody) as SumsubWebhookPayload;
    } catch {
      res.status(400).send("Invalid JSON");
      return;
    }

    const uid = String(payload.externalUserId ?? "").trim();
    if (!uid) {
      logger.warn("Sumsub webhook missing externalUserId");
      res.status(400).send("Missing externalUserId");
      return;
    }

    const status = mapSumsubToVerificationStatus(payload);
    const correlationId = webhookCorrelationId(payload, rawBody);
    const ref = verificationRef(db, uid);
    const userRef = db.doc(`users/${uid}`);

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const existing = parseVerificationRecord(snap.data());
        if (
          existing.lastWebhookCorrelationId === correlationId &&
          existing.verificationStatus === status
        ) {
          return;
        }

        const verificationUpdate: Record<string, unknown> = {
          verificationStatus: status,
          sumsubApplicantId: payload.applicantId ?? existing.sumsubApplicantId ?? null,
          verificationUpdatedAt: FieldValue.serverTimestamp(),
          lastWebhookType: payload.type ?? null,
          lastWebhookAt: FieldValue.serverTimestamp(),
          lastWebhookCorrelationId: correlationId,
        };

        if (shouldSetVerified(status)) {
          verificationUpdate.verifiedAt = FieldValue.serverTimestamp();
        }

        tx.set(ref, verificationUpdate, {merge: true});

        if (shouldSetVerified(status)) {
          tx.set(
            userRef,
            {
              isVerified: true,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        } else if (status === "rejected" || status === "retry_required") {
          tx.set(
            userRef,
            {
              isVerified: false,
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
        }
      });
    } catch (error) {
      logger.error("Sumsub webhook processing failed", {uid, error: String(error)});
      res.status(500).send("Processing failed");
      return;
    }

    if (payload.testMode === true) {
      logger.info("Sumsub test webhook processed", {uid, status});
    }

    res.status(200).json({ok: true, docId: VERIFICATION_DOC_ID});
  },
);
