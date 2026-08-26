const {describe, it, beforeEach, afterEach} = require("node:test");
const assert = require("node:assert/strict");
const {
  parseSumsubEnvironment,
  isSumsubConfigured,
  isSumsubWebhookConfigured,
  DEFAULT_SUMSUB_BASE_URL,
} = require("../lib/sumsub/sumsubConfig.js");

describe("sumsub config", () => {
  const originalEnv = {...process.env};

  beforeEach(() => {
    delete process.env.SUMSUB_APP_TOKEN;
    delete process.env.SUMSUB_SECRET_KEY;
    delete process.env.SUMSUB_WEBHOOK_SECRET;
    delete process.env.SUMSUB_LEVEL_NAME;
    delete process.env.SUMSUB_ENVIRONMENT;
    delete process.env.SUMSUB_BASE_URL;
  });

  afterEach(() => {
    process.env = {...originalEnv};
  });

  it("parses sandbox and production environments", () => {
    assert.equal(parseSumsubEnvironment("sandbox"), "sandbox");
    assert.equal(parseSumsubEnvironment("production"), "production");
    assert.equal(parseSumsubEnvironment(undefined), "sandbox");
  });

  it("is not configured without secrets", () => {
    assert.equal(isSumsubConfigured(), false);
    assert.equal(isSumsubWebhookConfigured(), false);
  });

  it("is configured when required env vars are present", () => {
    process.env.SUMSUB_APP_TOKEN = "token";
    process.env.SUMSUB_SECRET_KEY = "secret";
    process.env.SUMSUB_LEVEL_NAME = "mevora-profile-verification";
    process.env.SUMSUB_WEBHOOK_SECRET = "wh-secret";
    process.env.SUMSUB_ENVIRONMENT = "sandbox";
    process.env.SUMSUB_BASE_URL = DEFAULT_SUMSUB_BASE_URL;
    assert.equal(isSumsubConfigured(), true);
    assert.equal(isSumsubWebhookConfigured(), true);
  });
});
