import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";
import {DiditApiError} from "./didit/diditClient.js";
import {diditSecrets, isDiditConfigured} from "./didit/diditConfig.js";
import {DiditProvider} from "./didit/diditProvider.js";
import {ProviderNotConfiguredError} from "./identityVerificationProvider.js";
import {
  IdentityStartBlockedError,
  attachProviderSession,
  readIdentityVerification,
  reserveIdentitySessionAttempt,
} from "./identityVerificationStore.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";

/**
 * Creates (or resumes) an identity verification session for the signed-in
 * user.
 *
 * The uid comes from `request.auth.uid` and from nowhere else — the callable
 * takes no uid argument, so there is no parameter a client could use to point
 * this at another account. That uid becomes Didit's `vendor_data`, which is
 * what the webhook correlates against.
 *
 * The response carries only launch handles. The API key, the webhook secret
 * and the workflow id never leave the server.
 */
export const createIdentityVerificationSession = onCall(
  {
    secrets: [...diditSecrets],
    enforceAppCheck,
    region: "europe-west1",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    if (!isDiditConfigured()) {
      // Fail closed. An unconfigured deployment reports that it cannot
      // verify rather than pretending a session exists.
      throw new HttpsError("failed-precondition", "verification-not-configured");
    }

    const accountSnap = await db.doc(`users/${uid}`).get();
    if (!accountSnap.exists) {
      throw new HttpsError("not-found", "account-not-found");
    }
    if (accountSnap.data()?.isVerified === true) {
      throw new HttpsError("failed-precondition", "already-verified");
    }

    const provider = DiditProvider.requireFromEnvironment();
    const language = readLanguage(request.data);

    let resumableSessionId: string | undefined;
    try {
      ({resumableSessionId} = await reserveIdentitySessionAttempt(db, uid, provider.id));
    } catch (error) {
      throw toHttpsError(error);
    }

    // A session already in flight is handed back rather than duplicated: the
    // user most likely backgrounded the app mid-flow, and a second provider
    // session would orphan the first and burn an attempt.
    if (resumableSessionId) {
      try {
        const state = await provider.fetchSessionStatus(resumableSessionId);
        logger.info("identity session resumed", safeLogMeta({uid, status: state.status}));
        return {
          providerSessionId: resumableSessionId,
          resumed: true,
          status: state.status,
        };
      } catch (error) {
        logger.warn("identity session resume failed", safeLogMeta({
          uid,
          error: describeError(error),
        }));
        throw new HttpsError("unavailable", "verification-unavailable");
      }
    }

    try {
      const session = await provider.createSession({uid, language});
      await attachProviderSession(db, uid, session.providerSessionId);
      logger.info("identity session created", safeLogMeta({uid, status: session.status}));
      return {
        providerSessionId: session.providerSessionId,
        sessionToken: session.launchToken ?? null,
        url: session.launchUrl ?? null,
        status: session.status,
        resumed: false,
      };
    } catch (error) {
      logger.warn("identity session creation failed", safeLogMeta({
        uid,
        error: describeError(error),
      }));
      throw toHttpsError(error);
    }
  },
);

/**
 * Reads the current state without contacting the provider.
 *
 * The client calls this when it returns from the provider flow. It is a read
 * of MEVORA's own authoritative state — returning from the SDK or a deep link
 * proves nothing, so this is how the app finds out what actually happened.
 */
export const getIdentityVerificationState = onCall(
  {enforceAppCheck, region: "europe-west1"},
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const doc = await readIdentityVerification(db, uid);
    return {
      status: doc.status,
      provider: doc.provider,
      reason: doc.reason ?? null,
      verifiedAt: doc.verifiedAt?.toMillis() ?? null,
      updatedAt: doc.updatedAt?.toMillis() ?? null,
    };
  },
);

function readLanguage(data: unknown): string | undefined {
  if (!data || typeof data !== "object") {
    return undefined;
  }
  const raw = (data as Record<string, unknown>).language;
  if (typeof raw !== "string") {
    return undefined;
  }
  // A UI hint only, and the one client-supplied value this callable accepts —
  // so it is constrained to an ISO 639-1 code rather than passed through.
  const code = raw.trim().slice(0, 2).toLowerCase();
  return /^[a-z]{2}$/.test(code) ? code : undefined;
}

function toHttpsError(error: unknown): HttpsError {
  if (error instanceof HttpsError) {
    return error;
  }
  if (error instanceof IdentityStartBlockedError) {
    switch (error.reason) {
      case "already_verified":
        return new HttpsError("failed-precondition", "already-verified");
      case "cooldown":
        return new HttpsError("resource-exhausted", "verification-cooldown", {
          retryAfterSeconds: error.retryAfterSeconds ?? 0,
        });
      case "attempt_limit":
        return new HttpsError("resource-exhausted", "verification-attempt-limit");
      default:
        return new HttpsError("failed-precondition", "verification-in-progress");
    }
  }
  if (error instanceof ProviderNotConfiguredError) {
    return new HttpsError("failed-precondition", "verification-not-configured");
  }
  if (error instanceof DiditApiError) {
    return new HttpsError("unavailable", "verification-unavailable");
  }
  return new HttpsError("internal", "verification-unavailable");
}

/** Error text for logs, with no payload, token or identity data in it. */
function describeError(error: unknown): string {
  if (error instanceof DiditApiError) {
    return `${error.code}:${error.statusCode}`;
  }
  if (error instanceof Error) {
    return error.name;
  }
  return "unknown";
}
