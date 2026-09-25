const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const {
  isDiditConfigured,
  isDiditWebhookConfigured,
  resolveDiditConfig,
  resolveDiditWebhookSecret,
  parseDiditEnvironment,
  DiditProvider,
  ProviderNotConfiguredError,
} = require("../lib/identity/index.js");

const KEYS = [
  "DIDIT_API_KEY",
  "DIDIT_WEBHOOK_SECRET",
  "DIDIT_WORKFLOW_ID",
  "DIDIT_ENVIRONMENT",
  "DIDIT_BASE_URL",
  "DIDIT_CALLBACK_URL",
];

let saved;
beforeEach(() => {
  saved = Object.fromEntries(KEYS.map((k) => [k, process.env[k]]));
  for (const k of KEYS) delete process.env[k];
});
afterEach(() => {
  for (const k of KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
});

describe("configuration fails closed", () => {
  it("reports unconfigured rather than throwing when nothing is set", () => {
    assert.equal(resolveDiditConfig(), null);
    assert.equal(isDiditConfigured(), false);
    assert.equal(resolveDiditWebhookSecret(), null);
    assert.equal(isDiditWebhookConfigured(), false);
  });

  it("refuses a partial configuration instead of guessing the rest", () => {
    process.env.DIDIT_API_KEY = "k";
    assert.equal(isDiditConfigured(), false, "api key alone is not enough");

    delete process.env.DIDIT_API_KEY;
    process.env.DIDIT_WORKFLOW_ID = "wf";
    assert.equal(isDiditConfigured(), false, "workflow alone is not enough");
  });

  it("is configured only once both the key and the workflow exist", () => {
    process.env.DIDIT_API_KEY = "k";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    const config = resolveDiditConfig();
    assert.ok(config);
    assert.equal(config.apiKey, "k");
    assert.equal(config.workflowId, "wf");
  });

  it("defaults to sandbox so an unconfigured deployment is never treated as live", () => {
    process.env.DIDIT_API_KEY = "k";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    assert.equal(resolveDiditConfig().environment, "sandbox");

    assert.equal(parseDiditEnvironment(undefined), "sandbox");
    assert.equal(parseDiditEnvironment(""), "sandbox");
    assert.equal(parseDiditEnvironment("production"), "sandbox");
    assert.equal(parseDiditEnvironment("LIVE"), "sandbox");
    // Only the exact string promotes it.
    assert.equal(parseDiditEnvironment("live"), "live");
  });

  it("defaults to the official host and the app's return deep link", () => {
    process.env.DIDIT_API_KEY = "k";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    const config = resolveDiditConfig();
    assert.equal(config.baseUrl, "https://verification.didit.me");
    assert.equal(config.callbackUrl, "mevora://verify/identity");
  });

  it("treats the API key and the webhook secret as separate values", () => {
    process.env.DIDIT_API_KEY = "api_key_value";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    // An API key alone must not make the webhook appear configured: signing
    // webhook checks with the API key would accept every forgery.
    assert.equal(isDiditWebhookConfigured(), false);

    process.env.DIDIT_WEBHOOK_SECRET = "whsec_value";
    assert.equal(resolveDiditWebhookSecret(), "whsec_value");
    assert.notEqual(resolveDiditWebhookSecret(), resolveDiditConfig().apiKey);
  });

  it("builds no provider without credentials, and says so explicitly", () => {
    assert.equal(DiditProvider.fromEnvironment(), null);
    assert.throws(
      () => DiditProvider.requireFromEnvironment(),
      (e) => e instanceof ProviderNotConfiguredError && e.provider === "didit",
    );
  });

  it("will not parse a webhook while unconfigured", () => {
    process.env.DIDIT_API_KEY = "k";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    const provider = DiditProvider.requireFromEnvironment();
    assert.throws(
      () => provider.parseWebhookEvent({rawBody: "{}", headers: {}}),
      (e) => e instanceof ProviderNotConfiguredError,
    );
  });

  it("keeps whitespace-only values out of the configuration", () => {
    process.env.DIDIT_API_KEY = "   ";
    process.env.DIDIT_WORKFLOW_ID = "wf";
    assert.equal(isDiditConfigured(), false);
  });
});
