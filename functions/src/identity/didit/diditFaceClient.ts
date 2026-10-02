import {DiditApiError} from "./diditClient.js";

/**
 * Didit standalone biometric APIs: Passive Liveness and Face Match 1:1.
 *
 * Like diditClient.ts, this is the only place that knows these endpoints and
 * their response shapes, and it returns narrow MEVORA-shaped values. What the
 * responses also carry — similarity and liveness scores, face bounding boxes,
 * estimated age and gender, image quality figures, the request id — is read
 * past here and never returned, logged or stored.
 *
 * Every request sends `save_api_request=false`: Didit then keeps neither the
 * images nor a session, and does not enrol the face in its search index. The
 * default is `true`. No `vendor_data` is sent — Didit has no need to know
 * which member a face belongs to.
 */

export type DiditFaceConfig = {
  apiKey: string;
  baseUrl: string;
  timeoutMs: number;
};

export type DiditLivenessSummary = {
  /** Didit's verdict word, exactly as sent. Only "Approved" means live. */
  status: string;
  risks: string[];
};

export type DiditFaceMatchSummary = {
  status: string;
  risks: string[];
  /** Faces Didit found in the reference image, when it says. */
  referenceFaceCount: number | null;
};

/**
 * Didit could not process the image at all: unreadable, wrong format, too
 * large, or no face to work with. A statement about the image, not an outage.
 */
export class DiditImageRejectedError extends Error {
  constructor() {
    super("didit-image-rejected");
    this.name = "DiditImageRejectedError";
  }
}

const RISK_CODE = /^[A-Z][A-Z0-9_]{2,63}$/;

/** A 2xx whose body MEVORA cannot read a verdict from. */
const UNUSABLE_ANSWER = 422;

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

/** The `risk` codes of a warnings list — the codes only, never their descriptions. */
function riskCodes(warnings: unknown): string[] {
  if (!Array.isArray(warnings)) {
    return [];
  }
  const out: string[] = [];
  for (const warning of warnings) {
    const risk = asRecord(warning)?.risk;
    if (typeof risk === "string" && RISK_CODE.test(risk)) {
      out.push(risk);
    }
  }
  return out;
}

/** Exported for tests: what MEVORA keeps of a liveness response. */
export function summarizeLiveness(data: unknown): DiditLivenessSummary {
  const liveness = asRecord(asRecord(data)?.liveness);
  const status = liveness?.status;
  if (typeof status !== "string" || !status) {
    // No verdict word where one must be: not a decline, not an approval. Didit
    // answered (and billed) — asking again would not change the answer, so the
    // status used here is one DiditApiError does not treat as retryable.
    throw new DiditApiError(UNUSABLE_ANSWER, "didit-liveness-malformed");
  }
  return {status, risks: riskCodes(liveness?.warnings)};
}

/** Exported for tests: what MEVORA keeps of a face-match response. */
export function summarizeFaceMatch(data: unknown): DiditFaceMatchSummary {
  const match = asRecord(asRecord(data)?.face_match);
  const status = match?.status;
  if (typeof status !== "string" || !status) {
    throw new DiditApiError(UNUSABLE_ANSWER, "didit-face-match-malformed");
  }
  const entities = asRecord(match?.ref_image)?.entities;
  return {
    status,
    risks: riskCodes(match?.warnings),
    referenceFaceCount: Array.isArray(entities) ? entities.length : null,
  };
}

export class DiditFaceClient {
  constructor(private readonly config: DiditFaceConfig) {}

  async passiveLiveness(input: {image: Buffer; declineThreshold: number}): Promise<DiditLivenessSummary> {
    const form = new FormData();
    form.append("user_image", jpegPart(input.image), "selfie.jpg");
    form.append("face_liveness_score_decline_threshold", String(input.declineThreshold));
    form.append("save_api_request", "false");
    return summarizeLiveness(await this.post("/v3/passive-liveness/", form, "didit-liveness-failed"));
  }

  async faceMatch(input: {
    userImage: Buffer;
    referenceImage: Buffer;
    declineThreshold: number;
  }): Promise<DiditFaceMatchSummary> {
    const form = new FormData();
    form.append("user_image", jpegPart(input.userImage), "selfie.jpg");
    form.append("ref_image", jpegPart(input.referenceImage), "reference.jpg");
    form.append("face_match_score_decline_threshold", String(input.declineThreshold));
    form.append("save_api_request", "false");
    return summarizeFaceMatch(await this.post("/v3/face-match/", form, "didit-face-match-failed"));
  }

  private async post(path: string, form: FormData, failureCode: string): Promise<unknown> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.config.timeoutMs);
    let response: Response;
    try {
      response = await fetch(`${this.config.baseUrl}${path}`, {
        method: "POST",
        headers: {"x-api-key": this.config.apiKey, "Accept": "application/json"},
        body: form,
        signal: controller.signal,
      });
    } catch {
      // Network failure or our own timeout. Reported as a gateway timeout so it
      // is retryable; the underlying error text is not carried anywhere.
      throw new DiditApiError(504, "didit-face-unreachable");
    } finally {
      clearTimeout(timer);
    }
    if (response.status === 400) {
      throw new DiditImageRejectedError();
    }
    if (!response.ok) {
      throw new DiditApiError(response.status, failureCode);
    }
    try {
      return await response.json();
    } catch {
      throw new DiditApiError(UNUSABLE_ANSWER, `${failureCode}-unparseable`);
    }
  }
}

function jpegPart(bytes: Buffer): Blob {
  return new Blob([new Uint8Array(bytes)], {type: "image/jpeg"});
}
