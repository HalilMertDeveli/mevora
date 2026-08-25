/**
 * Redacts common PII patterns before writing Cloud Function logs.
 * Does not claim perfect scrubbing — avoid logging message bodies / tokens at call sites.
 */

const SENSITIVE_KEY = /^(password|token|accessToken|refreshToken|idToken|otp|phone|phoneNumber|email|latitude|longitude|text|ciphertext|privateKey|authorization)$/i;

function redactString(value: string): string {
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
