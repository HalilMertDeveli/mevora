import {createHmac, timingSafeEqual} from "node:crypto";

/**
 * Didit webhook signature verification.
 *
 * Didit signs with HMAC-SHA256 over a canonical JSON rendering of the body
 * (docs.didit.me/integration/webhooks): keys sorted recursively, compact
 * separators, non-ASCII left unescaped, and whole-valued floats written as
 * integers. The timestamp is NOT part of the signed string — it is checked
 * separately for freshness.
 *
 * `X-Signature-V2` is the preferred header because a canonical rendering
 * survives middleware that re-serializes the body. `X-Signature` over the raw
 * transmitted bytes is accepted as a fallback for the same reason in reverse.
 * `X-Signature-Simple` is deprecated and deliberately NOT accepted here: it
 * authenticates only `{timestamp}:{session_id}:{status}:{webhook_type}`, so a
 * caller that trusted it would be trusting an unauthenticated decision body.
 */

export const DIDIT_TIMESTAMP_TOLERANCE_SECONDS = 300;

/**
 * Renders a parsed body the way Didit does before signing.
 *
 * `JSON.stringify` already emits compact separators and leaves non-ASCII
 * unescaped, so only key ordering and the float rule need implementing.
 */
export function canonicalizeDiditPayload(value: unknown): string {
  return JSON.stringify(normalize(value));
}

function normalize(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(normalize);
  }
  if (value !== null && typeof value === "object") {
    const source = value as Record<string, unknown>;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) {
      sorted[key] = normalize(source[key]);
    }
    return sorted;
  }
  // Python renders 100.0 as 100 under this canonicalization; JavaScript has
  // no separate float type, so a whole-valued number already stringifies that
  // way and nothing needs doing.
  return value;
}

export type DiditSignatureHeaders = {
  signatureV2?: string;
  signature?: string;
  timestamp?: string;
};

export function readDiditSignatureHeaders(
  headers: Record<string, string | string[] | undefined>,
): DiditSignatureHeaders {
  const read = (name: string): string | undefined => {
    const raw = headers[name] ?? headers[name.toLowerCase()];
    const value = Array.isArray(raw) ? raw[0] : raw;
    const trimmed = typeof value === "string" ? value.trim() : "";
    return trimmed.length > 0 ? trimmed : undefined;
  };
  return {
    signatureV2: read("x-signature-v2"),
    signature: read("x-signature"),
    timestamp: read("x-timestamp"),
  };
}

/**
 * Whether the delivery is fresh enough to act on.
 *
 * A replayed webhook is a real attack here: re-sending an old "Approved" body
 * would otherwise re-verify a user whose verification was since revoked.
 */
export function isTimestampFresh(
  rawTimestamp: string | undefined,
  nowMs: number,
  toleranceSeconds = DIDIT_TIMESTAMP_TOLERANCE_SECONDS,
): boolean {
  if (!rawTimestamp) {
    return false;
  }
  const seconds = Number(rawTimestamp);
  if (!Number.isFinite(seconds)) {
    return false;
  }
  const skew = Math.abs(Math.floor(nowMs / 1000) - seconds);
  return skew <= toleranceSeconds;
}

function hmacHex(secret: string, message: string): string {
  return createHmac("sha256", secret).update(message, "utf8").digest("hex");
}

function constantTimeEquals(a: string, b: string): boolean {
  const left = Buffer.from(a, "utf8");
  const right = Buffer.from(b, "utf8");
  if (left.length !== right.length) {
    return false;
  }
  return timingSafeEqual(left, right);
}

export type DiditSignatureResult =
  | {valid: true; via: "v2" | "raw"}
  | {valid: false; reason: "missing_signature" | "invalid_signature" | "malformed_body"};

/**
 * Verifies a webhook body against the destination's `secret_shared_key`.
 *
 * Both accepted variants authenticate the whole decision payload. Freshness
 * is the caller's job — see [isTimestampFresh] — because a stale but
 * correctly signed delivery is a different failure with a different response.
 */
export function verifyDiditSignature(input: {
  secret: string;
  rawBody: Buffer | string;
  headers: Record<string, string | string[] | undefined>;
}): DiditSignatureResult {
  const {signatureV2, signature} = readDiditSignatureHeaders(input.headers);
  if (!signatureV2 && !signature) {
    return {valid: false, reason: "missing_signature"};
  }

  const raw = typeof input.rawBody === "string"
    ? input.rawBody
    : input.rawBody.toString("utf8");

  if (signatureV2) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return {valid: false, reason: "malformed_body"};
    }
    const canonical = canonicalizeDiditPayload(parsed);
    if (constantTimeEquals(hmacHex(input.secret, canonical), signatureV2)) {
      return {valid: true, via: "v2"};
    }
  }

  if (signature && constantTimeEquals(hmacHex(input.secret, raw), signature)) {
    return {valid: true, via: "raw"};
  }

  return {valid: false, reason: "invalid_signature"};
}
