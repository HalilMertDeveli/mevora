import {defineSecret, defineString} from "firebase-functions/params";

/**
 * Didit credentials. Server-side only — never a dart-define, never Remote
 * Config, never a client-readable document, never the app bundle.
 *
 * `DIDIT_API_KEY` authenticates MEVORA to Didit. `DIDIT_WEBHOOK_SECRET` is the
 * per-destination `secret_shared_key` returned once by
 * `POST /v3/webhook/destinations/`. They are different values and must never
 * be substituted for one another: signing a webhook check with the API key
 * would accept every forgery.
 */
export const diditApiKey = defineSecret("DIDIT_API_KEY");
export const diditWebhookSecret = defineSecret("DIDIT_WEBHOOK_SECRET");

/**
 * The workflow configured in the Didit console: ID Verification + Passive
 * Liveness + Face Match 1:1 (+ Device & IP Analysis). Not a secret, but not
 * hard-coded either — it differs between the sandbox and live applications.
 */
export const diditWorkflowId = defineString("DIDIT_WORKFLOW_ID", {default: ""});

export const DEFAULT_DIDIT_BASE_URL = "https://verification.didit.me";

export const diditBaseUrl = defineString("DIDIT_BASE_URL", {
  default: DEFAULT_DIDIT_BASE_URL,
});

/**
 * Which Didit application the key belongs to.
 *
 * Sandbox is the default, and deliberately so: an unconfigured deployment
 * must never silently behave as if it were live. Promotion to "live" is an
 * explicit act.
 */
export const diditEnvironment = defineString("DIDIT_ENVIRONMENT", {
  default: "sandbox",
});

export type DiditEnvironment = "sandbox" | "live";

export type DiditRuntimeConfig = {
  apiKey: string;
  workflowId: string;
  baseUrl: string;
  environment: DiditEnvironment;
};

export const diditSecrets = [diditApiKey, diditWebhookSecret] as const;

export function parseDiditEnvironment(raw: string | undefined): DiditEnvironment {
  return raw === "live" ? "live" : "sandbox";
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

function readStringValue(
  envKey: string,
  param: ReturnType<typeof defineString>,
  fallback = "",
): string {
  const fromEnv = process.env[envKey]?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    return (param.value() || fallback).trim();
  } catch {
    return fallback;
  }
}

/**
 * Resolves session-creation config, or null when it is incomplete.
 *
 * Never throws and never guesses. A caller that gets null must fail closed —
 * report "not configured" and create nothing — rather than proceed with a
 * partial configuration.
 */
export function resolveDiditConfig(): DiditRuntimeConfig | null {
  const apiKey = readSecretValue("DIDIT_API_KEY", diditApiKey);
  const workflowId = readStringValue("DIDIT_WORKFLOW_ID", diditWorkflowId);
  const baseUrl = readStringValue("DIDIT_BASE_URL", diditBaseUrl, DEFAULT_DIDIT_BASE_URL);
  const environment = parseDiditEnvironment(
    readStringValue("DIDIT_ENVIRONMENT", diditEnvironment, "sandbox"),
  );

  if (!apiKey || !workflowId || !baseUrl) {
    return null;
  }
  return {apiKey, workflowId, baseUrl, environment};
}

export function isDiditConfigured(): boolean {
  return resolveDiditConfig() !== null;
}

/** The webhook signing secret, or null. Distinct from the API key. */
export function resolveDiditWebhookSecret(): string | null {
  return readSecretValue("DIDIT_WEBHOOK_SECRET", diditWebhookSecret) ?? null;
}

export function isDiditWebhookConfigured(): boolean {
  return resolveDiditWebhookSecret() !== null;
}
