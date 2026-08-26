const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {signSumsubRequest, verifyWebhookDigest} = require("../lib/sumsub/sumsubAuth.js");

describe("sumsub auth", () => {
  it("signs requests with HMAC SHA256 lowercase hex", () => {
    const secret = "test-secret";
    const body = JSON.stringify({userId: "uid-1", levelName: "basic-kyc-level", ttlInSecs: 600});
    const {timestamp, signature} = signSumsubRequest({
      secretKey: secret,
      method: "POST",
      pathWithQuery: "/resources/accessTokens/sdk",
      body,
      timestampSeconds: 1607551635,
    });
    assert.equal(timestamp, "1607551635");
    assert.match(signature, /^[0-9a-f]{64}$/);
    assert.equal(
      signature,
      signSumsubRequest({
        secretKey: secret,
        method: "POST",
        pathWithQuery: "/resources/accessTokens/sdk",
        body,
        timestampSeconds: 1607551635,
      }).signature,
    );
  });

  it("verifies webhook digest for raw body", () => {
    const secret = "webhook-secret";
    const body = '{"type":"applicantReviewed","externalUserId":"uid-1"}';
    const digest = verifyWebhookDigest({
      secretKey: secret,
      rawBody: body,
      digest: require("node:crypto")
        .createHmac("sha256", secret)
        .update(body)
        .digest("hex"),
      algorithm: "HMAC_SHA256_HEX",
    });
    assert.equal(digest, true);
  });

  it("rejects invalid webhook digest", () => {
    const valid = verifyWebhookDigest({
      secretKey: "secret",
      rawBody: "{}",
      digest: "deadbeef",
      algorithm: "HMAC_SHA256_HEX",
    });
    assert.equal(valid, false);
  });
});
