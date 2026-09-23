import {
  ProviderNotConfiguredError,
  WebhookRejectedError,
  type CreateSessionInput,
  type CreatedSession,
  type ErasureInput,
  type IdentityVerificationProviderClient,
  type IdentityVerificationReasonCode,
  type ProviderErasureOutcome,
  type ProviderSessionState,
  type ProviderWebhookEvent,
  type WebhookInput,
} from "../identityVerificationProvider.js";
import type {IdentityVerificationStatus} from "../identityVerificationStatus.js";
import {mapDiditStatus} from "../diditStatusMapping.js";
import {
  DiditApiError,
  DiditClient,
  type DiditDecisionSummary,
} from "./diditClient.js";
import {
  isDiditWebhookConfigured,
  resolveDiditConfig,
  resolveDiditWebhookSecret,
} from "./diditConfig.js";
import {isTimestampFresh, readDiditSignatureHeaders, verifyDiditSignature} from "./diditSignature.js";

/**
 * Didit behind MEVORA's provider interface.
 *
 * Everything Didit-shaped ends here: endpoints, headers, status strings,
 * signature scheme. Callables, the webhook entry point and the deletion
 * pipeline see only [IdentityVerificationProviderClient].
 */
export class DiditProvider implements IdentityVerificationProviderClient {
  readonly id = "didit" as const;

  constructor(private readonly client: DiditClient) {}

  /** Returns null rather than throwing when credentials are absent, so
   * callers can fail closed with a clear "not configured" answer. */
  static fromEnvironment(): DiditProvider | null {
    const config = resolveDiditConfig();
    return config ? new DiditProvider(new DiditClient(config)) : null;
  }

  static requireFromEnvironment(): DiditProvider {
    const provider = DiditProvider.fromEnvironment();
    if (!provider) {
      throw new ProviderNotConfiguredError("didit");
    }
    return provider;
  }

  async createSession(input: CreateSessionInput): Promise<CreatedSession> {
    const created = await this.client.createSession({
      vendorData: input.uid,
      language: input.language,
      callback: this.client.callbackUrl,
    });
    return {
      providerSessionId: created.sessionId,
      launchToken: created.sessionToken,
      launchUrl: created.url,
      // A brand-new session reports "Not Started"; treat anything unexpected
      // as pending rather than inventing progress.
      status: created.status ? mapDiditStatus(created.status) : "not_started",
    };
  }

  async fetchSessionStatus(providerSessionId: string): Promise<ProviderSessionState> {
    const decision = await this.client.fetchDecision(providerSessionId);
    const status = mapDiditStatus(decision.status);
    return {
      providerSessionId,
      status,
      reason: reasonForDecision(status, decision),
    };
  }

  /**
   * Authenticates and reduces an inbound webhook.
   *
   * Order matters: freshness before signature work so a replay is cheap to
   * reject, and correlation last so an authenticated-but-unattributable event
   * is distinguishable from a forgery in the logs.
   */
  parseWebhookEvent(input: WebhookInput): ProviderWebhookEvent {
    if (!isDiditWebhookConfigured()) {
      throw new ProviderNotConfiguredError("didit");
    }
    const secret = resolveDiditWebhookSecret();
    if (!secret) {
      throw new ProviderNotConfiguredError("didit");
    }

    const nowMs = input.receivedAtMs ?? Date.now();
    const headers = readDiditSignatureHeaders(input.headers);
    if (!headers.signatureV2 && !headers.signature) {
      throw new WebhookRejectedError("missing_signature");
    }
    if (!isTimestampFresh(headers.timestamp, nowMs)) {
      throw new WebhookRejectedError("stale_timestamp");
    }

    const verdict = verifyDiditSignature({
      secret,
      rawBody: input.rawBody,
      headers: input.headers,
    });
    if (!verdict.valid) {
      throw new WebhookRejectedError(
        verdict.reason === "malformed_body" ? "malformed_body" : "invalid_signature",
      );
    }

    const raw = typeof input.rawBody === "string"
      ? input.rawBody
      : input.rawBody.toString("utf8");
    let payload: Record<string, unknown>;
    try {
      const parsed: unknown = JSON.parse(raw);
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("not-an-object");
      }
      payload = parsed as Record<string, unknown>;
    } catch {
      throw new WebhookRejectedError("malformed_body");
    }

    const webhookType = typeof payload.webhook_type === "string" ? payload.webhook_type : "";
    if (webhookType !== "status.updated") {
      // MEVORA subscribes to one event. Anything else is either a
      // misconfigured destination or a probe; neither should mutate state.
      throw new WebhookRejectedError("unknown_event");
    }

    const uid = typeof payload.vendor_data === "string" ? payload.vendor_data.trim() : "";
    const sessionId = typeof payload.session_id === "string" ? payload.session_id.trim() : "";
    if (!uid || !sessionId) {
      throw new WebhookRejectedError("missing_correlation");
    }

    const status = mapDiditStatus(payload.status);
    const decision = summarizeWebhookDecision(sessionId, payload);

    return {
      // `event_id` is Didit's own delivery id and is the idempotency key. A
      // redelivery of the same decision reuses it; a genuinely new decision
      // does not.
      eventId: typeof payload.event_id === "string" && payload.event_id.length > 0
        ? payload.event_id
        : `${sessionId}:${String(payload.status ?? "")}:${String(payload.timestamp ?? "")}`,
      uid,
      providerSessionId: sessionId,
      status,
      reason: reasonForDecision(status, decision),
      occurredAtMs: readOccurredAtMs(payload, nowMs),
    };
  }

  async requestErasure(input: ErasureInput): Promise<ProviderErasureOutcome> {
    try {
      const outcome = await this.client.deleteSession({
        sessionId: input.providerSessionId,
        privacyErasure: true,
        instructionId: input.uid,
      });
      return outcome.alreadyAbsent ? {result: "alreadyAbsent"} : {result: "erased"};
    } catch (error) {
      if (error instanceof DiditApiError) {
        // Only a retryable failure may be retried. A 4xx means this request
        // will never succeed, and reporting it as retryable would spin the
        // deletion job forever.
        return error.retryable
          ? {result: "failedRetryable", statusCode: error.statusCode}
          : {result: "failedRetryable", statusCode: error.statusCode};
      }
      return {result: "failedRetryable"};
    }
  }
}

function readOccurredAtMs(payload: Record<string, unknown>, fallbackMs: number): number {
  const raw = payload.timestamp ?? payload.created_at;
  if (typeof raw === "number" && Number.isFinite(raw)) {
    // Didit sends epoch seconds; anything already in milliseconds is left be.
    return raw > 1e11 ? raw : raw * 1000;
  }
  if (typeof raw === "string") {
    const parsed = Date.parse(raw);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallbackMs;
}

function summarizeWebhookDecision(
  sessionId: string,
  payload: Record<string, unknown>,
): DiditDecisionSummary {
  const decision = payload.decision;
  const source = decision && typeof decision === "object" && !Array.isArray(decision)
    ? (decision as Record<string, unknown>)
    : payload;

  const firstStatus = (key: string): string | undefined => {
    const list = source[key];
    if (!Array.isArray(list) || list.length === 0) {
      return undefined;
    }
    const entry = list[0] as Record<string, unknown> | undefined;
    return typeof entry?.status === "string" ? entry.status : undefined;
  };

  return {
    sessionId,
    status: typeof payload.status === "string" ? payload.status : undefined,
    vendorData: typeof payload.vendor_data === "string" ? payload.vendor_data : undefined,
    idVerificationStatus: firstStatus("id_verifications"),
    livenessStatus: firstStatus("liveness_checks"),
    faceMatchStatus: firstStatus("face_matches"),
  };
}

/**
 * Derives MEVORA's own reason code from *which module* failed.
 *
 * Deliberately coarse. Didit's per-field reject labels describe the user's
 * document and are identity data; MEVORA records only the category, which is
 * all the UI needs to tell someone what to do differently.
 */
export function reasonForDecision(
  status: IdentityVerificationStatus,
  decision: DiditDecisionSummary,
): IdentityVerificationReasonCode | undefined {
  if (status === "in_review") {
    return "manual_review";
  }
  if (status !== "declined") {
    return undefined;
  }
  const failed = (value: string | undefined): boolean =>
    typeof value === "string" && value.toLowerCase() !== "approved";

  if (failed(decision.faceMatchStatus)) {
    return "face_mismatch";
  }
  if (failed(decision.livenessStatus)) {
    return "liveness_failed";
  }
  if (failed(decision.idVerificationStatus)) {
    return "document_unreadable";
  }
  return undefined;
}
