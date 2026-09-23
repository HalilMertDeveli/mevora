import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {onRequest} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {DiditApiError} from "./didit/diditClient.js";
import {diditSecrets, isDiditWebhookConfigured} from "./didit/diditConfig.js";
import {DiditProvider} from "./didit/diditProvider.js";
import {
  ProviderNotConfiguredError,
  WebhookRejectedError,
} from "./identityVerificationProvider.js";
import {grantsVerifiedBadge} from "./identityVerificationStatus.js";
import {applyIdentityProviderEvent} from "./identityVerificationStore.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

/**
 * The authoritative identity verification webhook.
 *
 * A signed event is the *trigger*, not the proof. For any event that would
 * grant the badge, MEVORA re-reads the decision from the provider server to
 * server before promoting the user — so a forged body that somehow passed
 * signature checks still could not verify anyone, and a signed body whose
 * decision has since changed cannot verify someone on stale information.
 *
 * Non-granting transitions are applied from the signed event directly: they
 * only ever move a user away from verified, which is the safe direction.
 */
export const identityVerificationWebhook = onRequest(
  {
    secrets: [...diditSecrets],
    region: "europe-west1",
    cors: false,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    if (!isDiditWebhookConfigured()) {
      logger.error("identity webhook secret not configured");
      res.status(503).send("Not configured");
      return;
    }

    const provider = DiditProvider.fromEnvironment();
    if (!provider) {
      logger.error("identity provider not configured");
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

    let event;
    try {
      event = provider.parseWebhookEvent({rawBody, headers: req.headers});
    } catch (error) {
      if (error instanceof WebhookRejectedError) {
        // An unsubscribed event type is not an error on MEVORA's side —
        // acknowledge it so the provider stops retrying, but change nothing.
        if (error.reason === "unknown_event") {
          logger.info("identity webhook ignored", safeLogMeta({reason: error.reason}));
          res.status(200).json({ok: true, ignored: true});
          return;
        }
        logger.warn("identity webhook rejected", safeLogMeta({reason: error.reason}));
        res.status(error.reason === "malformed_body" ? 400 : 401).send("Rejected");
        return;
      }
      if (error instanceof ProviderNotConfiguredError) {
        res.status(503).send("Not configured");
        return;
      }
      logger.error("identity webhook parse failed");
      res.status(400).send("Rejected");
      return;
    }

    let effective = event;
    if (grantsVerifiedBadge(event.status)) {
      try {
        const confirmed = await provider.fetchSessionStatus(event.providerSessionId);
        if (!grantsVerifiedBadge(confirmed.status)) {
          logger.warn("identity webhook approval not confirmed by provider", safeLogMeta({
            uid: event.uid,
            claimed: event.status,
            confirmed: confirmed.status,
          }));
        }
        effective = {...event, status: confirmed.status, reason: confirmed.reason};
      } catch (error) {
        // Could not confirm — do not promote on the webhook's word alone.
        // 503 asks the provider to redeliver, which is the correct outcome:
        // the user stays unverified until MEVORA can actually check.
        logger.warn("identity decision confirmation failed", safeLogMeta({
          uid: event.uid,
          error: error instanceof DiditApiError ? error.code : "unknown",
        }));
        res.status(503).send("Confirmation unavailable");
        return;
      }
    }

    try {
      const result = await applyIdentityProviderEvent(db, effective, provider.id);
      if (!result.applied) {
        logger.info("identity webhook not applied", safeLogMeta({
          uid: effective.uid,
          skipped: result.skipped,
        }));
        // Acknowledged on purpose: a duplicate, a stale delivery, a mismatched
        // session and a deleted account are all correctly handled outcomes,
        // and asking the provider to retry them would achieve nothing.
        res.status(200).json({ok: true, applied: false, skipped: result.skipped});
        return;
      }
      logger.info("identity verification state updated", safeLogMeta({
        uid: effective.uid,
        status: result.status,
      }));
      res.status(200).json({ok: true, applied: true});
    } catch (error) {
      logger.error("identity webhook processing failed", safeLogMeta({
        uid: effective.uid,
        error: error instanceof Error ? error.name : "unknown",
      }));
      res.status(500).send("Processing failed");
    }
  },
);
