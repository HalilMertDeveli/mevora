/**
 * Redacts common PII patterns before writing Cloud Function logs.
 * Does not claim perfect scrubbing — avoid logging message bodies / tokens at call sites.
 */

const SENSITIVE_KEY = /^(password|token|accessToken|refreshToken|idToken|otp|phone|phoneNumber|email|latitude|longitude|text|ciphertext|privateKey|authorization)$/i;

export function redactString(value: string): string {
  return value
    .replace(/\+?\d[\d\s\-()]{7,}\d/g, "[redacted-phone]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[redacted-email]")
    .replace(/\b-?\d{1,3}\.\d{3,}\b/g, "[redacted-coord]");
}

export function safeLogMeta(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (SENSITIVE_KEY.test(key)) {
      out[key] = "[redacted]";
      continue;
    }
    if (typeof value === "string") {
      out[key] = redactString(value);
      continue;
    }
    if (value && typeof value === "object" && !Array.isArray(value)) {
      out[key] = safeLogMeta(value as Record<string, unknown>);
      continue;
    }
    out[key] = value;
  }
  return out;
}

const URL_IN_TEXT = /https?:\/\/[^\s"'<>)]+/gi;
const MAX_ERROR_MESSAGE = 200;

export type SafeErrorMeta = {
  name: string;
  code: string | number | null;
  status: number | null;
  message: string;
};

/**
 * What may be logged about a failed outbound request.
 *
 * A raw error is not safe to log. An HTTP client's error can carry the request
 * it failed on, and a store lookup URL embeds the purchase token or the
 * transaction id; even the message alone can quote the URL. This keeps what an
 * operator needs — the kind of failure, its code, its HTTP status — and a
 * short message with every URL, and every value named in [secrets] (as sent
 * and URL-encoded), taken out.
 */
export function safeErrorMeta(
  error: unknown,
  secrets: readonly (string | null | undefined)[] = [],
): SafeErrorMeta {
  const asRecord = (value: unknown): Record<string, unknown> =>
    value !== null && typeof value === "object" ? (value as Record<string, unknown>) : {};
  const codeOf = (value: unknown): string | number | null =>
    typeof value === "string" || typeof value === "number" ? value : null;
  const record = asRecord(error);
  const cause = asRecord(record.cause);
  const status = [record.status, asRecord(record.response).status].find(
    (value): value is number => typeof value === "number",
  );

  let message = typeof record.message === "string" ? record.message : String(error);
  for (const secret of secrets) {
    if (!secret) continue;
    for (const form of new Set([secret, encodeURIComponent(secret)])) {
      message = message.split(form).join("[redacted]");
    }
  }
  message = redactString(message.replace(URL_IN_TEXT, "[redacted-url]")).slice(0, MAX_ERROR_MESSAGE);

  return {
    name: error instanceof Error ? error.name : typeof error,
    // `fetch failed` says nothing by itself; the network reason is on the cause.
    code: codeOf(record.code) ?? codeOf(cause.code),
    status: status ?? null,
    message,
  };
}
