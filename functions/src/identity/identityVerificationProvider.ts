import type {
  IdentityVerificationProvider as ProviderId,
  IdentityVerificationStatus,
} from "./identityVerificationStatus.js";

/**
 * The seam between MEVORA's verification domain and whoever performs the
 * identity check.
 *
 * Only an implementation of this interface may know a provider's HTTP
 * contract, credentials, status vocabulary or signature scheme. Callables,
 * the webhook entry point and the account-deletion pipeline talk to this
 * interface and to nothing provider-shaped.
 *
 * Nothing here returns raw provider payloads. Every method returns a
 * MEVORA-shaped value, so a provider swap cannot ripple past this file.
 */
export interface IdentityVerificationProviderClient {
  readonly id: ProviderId;

  /**
   * Creates a verification session for one MEVORA user.
   *
   * `uid` must come from the caller's verified auth context. Implementations
   * pass it as the provider's correlation value (Didit's `vendor_data`) and
   * must never accept a uid supplied by a client request body.
   */
  createSession(input: CreateSessionInput): Promise<CreatedSession>;

  /**
   * Re-reads a session's decision from the provider, server to server.
   *
   * This is the trusted read. A webhook says *that* something changed; this
   * says *what* the provider actually decided, and is what may promote a user
   * to verified.
   */
  fetchSessionStatus(providerSessionId: string): Promise<ProviderSessionState>;

  /**
   * Authenticates and parses an inbound webhook.
   *
   * Implementations verify the signature over the raw body and reject stale
   * or malformed deliveries. Returning a value means the event is
   * authentic — callers do not re-check.
   */
  parseWebhookEvent(input: WebhookInput): ProviderWebhookEvent;

  /**
   * Asks the provider to erase everything it holds for a session.
   *
   * Phase 5 wires this into account deletion. Implementations report what
   * actually happened rather than assuming success — see
   * [ProviderErasureOutcome].
   */
  requestErasure(input: ErasureInput): Promise<ProviderErasureOutcome>;
}

export type CreateSessionInput = {
  /** Trusted uid from the auth context. Never from a request body. */
  uid: string;
  /** Optional UI language hint (ISO 639-1). Not identity data. */
  language?: string;
};

/**
 * What the client needs to launch the flow, and nothing more. No credential,
 * workflow id or provider secret may appear here — this value is returned to
 * the app.
 */
export type CreatedSession = {
  providerSessionId: string;
  /** Short-lived token for a native SDK launch, when the provider uses one. */
  launchToken?: string;
  /** Hosted verification URL, when the provider uses one instead. */
  launchUrl?: string;
  status: IdentityVerificationStatus;
};

/**
 * A provider's view of a session, already translated.
 *
 * `reason` is a MEVORA reason code, not the provider's reject label: the
 * provider's own wording about a document is identity data and is dropped at
 * this boundary.
 */
export type ProviderSessionState = {
  providerSessionId: string;
  status: IdentityVerificationStatus;
  reason?: IdentityVerificationReasonCode;
};

export type IdentityVerificationReasonCode =
  | "document_unreadable"
  | "document_unsupported"
  | "liveness_failed"
  | "face_mismatch"
  | "manual_review"
  | "provider_error";

export type WebhookInput = {
  /** Raw, unparsed bytes — signatures are computed over these, not over a
   * re-serialized object. */
  rawBody: Buffer | string;
  headers: Record<string, string | string[] | undefined>;
  /** Injectable for tests; defaults to now. */
  receivedAtMs?: number;
};

/**
 * An authenticated webhook, reduced to what MEVORA acts on.
 *
 * `eventId` is the idempotency key and `occurredAtMs` is the ordering key:
 * together they let the handler discard duplicates and refuse to let a stale
 * delivery overwrite a newer terminal state.
 */
export type ProviderWebhookEvent = {
  eventId: string;
  /** The MEVORA uid the provider was told to correlate against. */
  uid: string;
  providerSessionId: string;
  status: IdentityVerificationStatus;
  reason?: IdentityVerificationReasonCode;
  occurredAtMs: number;
};

export type ErasureInput = {
  uid: string;
  providerSessionId: string;
};

/**
 * What erasure actually achieved.
 *
 * `alreadyAbsent` exists because a provider may answer 404 on a repeat call;
 * that is success, not failure. `failedRetryable` must not be recorded as
 * erased — MEVORA does not claim an erasure it has not been told happened.
 */
export type ProviderErasureOutcome =
  | {result: "erased"}
  | {result: "alreadyAbsent"}
  | {result: "failedRetryable"; statusCode?: number}
  | {result: "unsupported"};

/** Thrown by `parseWebhookEvent` when a delivery must be rejected. */
export class WebhookRejectedError extends Error {
  constructor(
    readonly reason:
      | "missing_signature"
      | "invalid_signature"
      | "stale_timestamp"
      | "malformed_body"
      | "unknown_event"
      | "missing_correlation",
  ) {
    super(reason);
    this.name = "WebhookRejectedError";
  }
}

export class ProviderNotConfiguredError extends Error {
  constructor(readonly provider: ProviderId) {
    super(`${provider}-not-configured`);
    this.name = "ProviderNotConfiguredError";
  }
}
