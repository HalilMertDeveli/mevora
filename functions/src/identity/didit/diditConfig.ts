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

/**
 * Lets a deployed SANDBOX application grant the verified badge.
 *
 * A sandbox application mocks its analysis — the document, liveness and face
 * match are answered from a script — so by default a deployment that is not
 * declared live verifies nobody. Set to exactly `true`, this accepts that for
 * one project: a non-production project that runs the hosted flow against the
 * Didit sandbox for QA. Production never sets it; production sets
 * `DIDIT_ENVIRONMENT=live`.
 *
 * The default is empty rather than "false" because the Functions emulator
 * copies a param's default into the environment, where it would be
 * indistinguishable from someone having asked for it.
 */
export const diditAllowSandboxVerification = defineString(
  "DIDIT_ALLOW_SANDBOX_VERIFICATION",
  {default: ""},
);

/**
 * Where Didit sends the user when the hosted flow finishes.
 *
 * A deep link back into MEVORA. It carries no verdict and is not trusted —
 * it only tells the app to go and re-read MEVORA's own state.
 */
export const diditCallbackUrl = defineString("DIDIT_CALLBACK_URL", {
  default: "mevora://verify/identity",
});

export type DiditEnvironment = "sandbox" | "live";

export type DiditRuntimeConfig = {
  apiKey: string;
  workflowId: string;
  baseUrl: string;
  environment: DiditEnvironment;
  callbackUrl?: string;
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

  const callbackUrl = readStringValue(
    "DIDIT_CALLBACK_URL",
    diditCallbackUrl,
    "mevora://verify/identity",
  );

  if (!apiKey || !workflowId || !baseUrl) {
    return null;
  }
  return {apiKey, workflowId, baseUrl, environment, callbackUrl};
}

/**
 * Config for the standalone biometric APIs (diditFaceClient.ts).
 *
 * Those calls need the API key and nothing else — no workflow, no callback, no
 * webhook secret — so they are resolved on their own rather than through
 * resolveDiditConfig, which is null without a workflow id. The environment is
 * returned for the caller to judge: a sandbox key answers these two APIs with
 * a canned approval, so it must never be mistaken for a working integration.
 */
export function resolveDiditFaceConfig(): {
  apiKey: string;
  baseUrl: string;
  environment: DiditEnvironment;
} | null {
  const apiKey = readSecretValue("DIDIT_API_KEY", diditApiKey);
  const baseUrl = readStringValue("DIDIT_BASE_URL", diditBaseUrl, DEFAULT_DIDIT_BASE_URL);
  if (!apiKey || !baseUrl) {
    return null;
  }
  return {
    apiKey,
    baseUrl,
    environment: parseDiditEnvironment(
      readStringValue("DIDIT_ENVIRONMENT", diditEnvironment, "sandbox"),
    ),
  };
}

export function isDiditConfigured(): boolean {
  return resolveDiditConfig() !== null;
}

/**
 * Whether a decision from the configured Didit application may grant the
 * verified badge. Decided from the server's own environment and nothing else.
 *
 * - Emulator: yes, as before — nothing there is a real member.
 * - Deployed and declared live: yes.
 * - Deployed on sandbox (declared, or never declared — the default): no,
 *   unless `DIDIT_ALLOW_SANDBOX_VERIFICATION` is exactly `true`.
 *
 * False means "cannot verify". Session creation refuses and the webhook
 * withholds the badge; neither falls back to trusting a mocked approval.
 * Erasure is deliberately not gated on this — a sandbox session still has to
 * be deletable.
 */
export function canDiditGrantVerification(): boolean {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    return true;
  }
  const environment = parseDiditEnvironment(
    readStringValue("DIDIT_ENVIRONMENT", diditEnvironment, "sandbox"),
  );
  if (environment === "live") {
    return true;
  }
  return (
    readStringValue("DIDIT_ALLOW_SANDBOX_VERIFICATION", diditAllowSandboxVerification) === "true"
  );
}

/** The webhook signing secret, or null. Distinct from the API key. */
export function resolveDiditWebhookSecret(): string | null {
  return readSecretValue("DIDIT_WEBHOOK_SECRET", diditWebhookSecret) ?? null;
}

export function isDiditWebhookConfigured(): boolean {
  return resolveDiditWebhookSecret() !== null;
}
