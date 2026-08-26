import {defineSecret, defineString} from "firebase-functions/params";

/** Sumsub App Token — sandbox or production. Never expose to clients. */
export const sumsubAppToken = defineSecret("SUMSUB_APP_TOKEN");

/** Sumsub Secret Key for API request signing. Never expose to clients. */
export const sumsubSecretKey = defineSecret("SUMSUB_SECRET_KEY");

/** Webhook secret for x-payload-digest verification. */
export const sumsubWebhookSecret = defineSecret("SUMSUB_WEBHOOK_SECRET");

/** Verification level name configured in Sumsub Dashboard. */
export const sumsubLevelName = defineString("SUMSUB_LEVEL_NAME", {
  default: "mevora-profile-verification",
});

/**
 * Sumsub environment selector. The API host is the same for sandbox and
 * production — the app token determines which mode is used.
 */
export const sumsubEnvironment = defineString("SUMSUB_ENVIRONMENT", {
  default: "sandbox",
});

export const DEFAULT_SUMSUB_BASE_URL = "https://api.sumsub.com";

/** Sumsub API base URL. Default is official host for both sandbox and prod. */
export const sumsubBaseUrl = defineString("SUMSUB_BASE_URL", {
  default: DEFAULT_SUMSUB_BASE_URL,
});

export type SumsubEnvironment = "sandbox" | "production";

export type SumsubRuntimeConfig = {
  appToken: string;
  secretKey: string;
  levelName: string;
  webhookSecret: string;
  environment: SumsubEnvironment;
  baseUrl: string;
};

export const sumsubSecrets = [
  sumsubAppToken,
  sumsubSecretKey,
  sumsubWebhookSecret,
] as const;

export function parseSumsubEnvironment(raw: string | undefined): SumsubEnvironment {
  return raw === "production" ? "production" : "sandbox";
}

function readSecretValue(
  envKey: string,
  secret: ReturnType<typeof defineSecret>,
): string | undefined {
  const fromEnv = process.env[envKey]?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    const value = secret.value()?.trim();
    return value || undefined;
  } catch {
    return undefined;
  }
}

/** True when token API credentials and level name are present. */
export function isSumsubConfigured(): boolean {
  return resolveSumsubConfig() !== null;
}

/** True when webhook secret is also configured (full activation). */
export function isSumsubWebhookConfigured(): boolean {
  return resolveSumsubWebhookSecret() !== null;
}

/** Webhook digest secret. Returns null when not configured. */
export function resolveSumsubWebhookSecret(): string | null {
  return readSecretValue("SUMSUB_WEBHOOK_SECRET", sumsubWebhookSecret) ?? null;
}

/**
 * Resolves runtime Sumsub config from Firebase secrets / env vars.
 * Returns null when required credentials are missing — never throws.
 */
export function resolveSumsubConfig(): SumsubRuntimeConfig | null {
  const appToken = readSecretValue("SUMSUB_APP_TOKEN", sumsubAppToken);
  const secretKey = readSecretValue("SUMSUB_SECRET_KEY", sumsubSecretKey);
  const webhookSecret = readSecretValue("SUMSUB_WEBHOOK_SECRET", sumsubWebhookSecret);
  const levelName = (process.env.SUMSUB_LEVEL_NAME || sumsubLevelName.value()).trim();
  const environment = parseSumsubEnvironment(
    process.env.SUMSUB_ENVIRONMENT || sumsubEnvironment.value(),
  );
  const baseUrl = (process.env.SUMSUB_BASE_URL || sumsubBaseUrl.value()).trim();

  if (!appToken || !secretKey || !levelName || !baseUrl) {
    return null;
  }

  return {
    appToken,
    secretKey,
    levelName,
    webhookSecret: webhookSecret ?? "",
    environment,
    baseUrl,
  };
}
