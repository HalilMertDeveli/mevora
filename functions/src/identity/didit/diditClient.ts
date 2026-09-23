import type {DiditRuntimeConfig} from "./diditConfig.js";

/**
 * Didit HTTP transport.
 *
 * The only place in MEVORA that knows Didit's endpoints, headers and response
 * shapes. Every method returns a narrow, MEVORA-shaped value: raw decision
 * bodies, document images, media URLs and provider reject text stop here and
 * are never returned to a caller, logged, or written to Firestore.
 */

export class DiditApiError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
  ) {
    super(code);
    this.name = "DiditApiError";
  }

  /** 5xx and 429 are worth retrying; a 4xx means the request itself is wrong. */
  get retryable(): boolean {
    return this.statusCode >= 500 || this.statusCode === 429;
  }
}

export type DiditCreatedSession = {
  sessionId: string;
  sessionToken?: string;
  url?: string;
  status?: string;
};

/**
 * The parts of a decision MEVORA reads.
 *
 * Note what is absent: `id_verifications[].document_number`, portrait and
 * document image URLs, the full extracted identity record. Those are read
 * past on purpose — MEVORA has no product requirement for them and storing
 * them would create a deletion obligation it does not need.
 */
export type DiditDecisionSummary = {
  sessionId: string;
  status?: string;
  vendorData?: string;
  idVerificationStatus?: string;
  livenessStatus?: string;
  faceMatchStatus?: string;
};

export type DiditDeletionOutcome = {
  deleted: boolean;
  alreadyAbsent: boolean;
  statusCode: number;
};

export class DiditClient {
  constructor(private readonly config: DiditRuntimeConfig) {}

  /**
   * Creates a verification session.
   *
   * `vendorData` is the MEVORA uid and is the only correlation handle the
   * webhook will carry back. Callers must pass a uid taken from a verified
   * auth context — this class cannot tell a trusted uid from a forged one.
   */
  async createSession(input: {
    vendorData: string;
    language?: string;
    callback?: string;
  }): Promise<DiditCreatedSession> {
    const body: Record<string, unknown> = {
      workflow_id: this.config.workflowId,
      vendor_data: input.vendorData,
    };
    if (input.language) {
      body.language = input.language;
    }
    if (input.callback) {
      body.callback = input.callback;
    }

    const data = await this.request<Record<string, unknown>>(
      "POST",
      "/v3/session/",
      body,
      "didit-session-create-failed",
    );

    const sessionId = typeof data.session_id === "string" ? data.session_id : "";
    if (!sessionId) {
      throw new DiditApiError(502, "didit-session-id-missing");
    }
    return {
      sessionId,
      sessionToken: typeof data.session_token === "string" ? data.session_token : undefined,
      url: typeof data.url === "string" ? data.url : undefined,
      status: typeof data.status === "string" ? data.status : undefined,
    };
  }

  /**
   * Re-reads a session's decision, server to server.
   *
   * This is the trusted read. A webhook tells MEVORA that something changed;
   * this tells it what Didit actually decided, and is what may promote a user
   * to verified.
   */
  async fetchDecision(sessionId: string): Promise<DiditDecisionSummary> {
    const data = await this.request<Record<string, unknown>>(
      "GET",
      `/v3/session/${encodeURIComponent(sessionId)}/decision/`,
      undefined,
      "didit-decision-failed",
    );
    return summarizeDecision(sessionId, data);
  }

  /**
   * Asks Didit to erase everything it holds for a session.
   *
   * A 404 on a repeat call is success, not failure: the session is already
   * gone. Anything else 4xx is a request problem and is not retried.
   */
  async deleteSession(input: {
    sessionId: string;
    privacyErasure: boolean;
    instructionId?: string;
  }): Promise<DiditDeletionOutcome> {
    const body: Record<string, unknown> = {
      deletion_instruction: input.privacyErasure
        ? "privacy_erasure"
        : "operational_session_delete",
    };
    if (input.instructionId) {
      body.instruction_id = input.instructionId;
    }

    const response = await this.send(
      "DELETE",
      `/v3/session/${encodeURIComponent(input.sessionId)}/delete/`,
      body,
    );
    if (response.status === 404) {
      return {deleted: false, alreadyAbsent: true, statusCode: 404};
    }
    if (!response.ok) {
      throw new DiditApiError(response.status, "didit-delete-failed");
    }
    return {deleted: true, alreadyAbsent: false, statusCode: response.status};
  }

  private async request<T>(
    method: "GET" | "POST" | "DELETE",
    path: string,
    body: unknown,
    failureCode: string,
  ): Promise<T> {
    const response = await this.send(method, path, body);
    if (!response.ok) {
      throw new DiditApiError(response.status, failureCode);
    }
    return (await response.json()) as T;
  }

  private send(
    method: "GET" | "POST" | "DELETE",
    path: string,
    body: unknown,
  ): Promise<Response> {
    const headers: Record<string, string> = {
      "x-api-key": this.config.apiKey,
      "Accept": "application/json",
    };
    const init: RequestInit = {method, headers};
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }
    return fetch(`${this.config.baseUrl}${path}`, init);
  }
}

/**
 * Reduces a decision body to the four statuses MEVORA acts on.
 *
 * Exported for tests, and kept separate from the transport so the "what we
 * deliberately do not read" decision is reviewable in one place.
 */
export function summarizeDecision(
  sessionId: string,
  data: Record<string, unknown>,
): DiditDecisionSummary {
  const firstStatus = (key: string): string | undefined => {
    const list = data[key];
    if (!Array.isArray(list) || list.length === 0) {
      return undefined;
    }
    const entry = list[0] as Record<string, unknown> | undefined;
    const status = entry?.status;
    return typeof status === "string" ? status : undefined;
  };

  return {
    sessionId,
    status: typeof data.status === "string" ? data.status : undefined,
    vendorData: typeof data.vendor_data === "string" ? data.vendor_data : undefined,
    idVerificationStatus: firstStatus("id_verifications"),
    livenessStatus: firstStatus("liveness_checks"),
    faceMatchStatus: firstStatus("face_matches"),
  };
}
