import {describe, it} from "node:test";
import assert from "node:assert/strict";
import {moderatePhotoBuffer} from "../../functions/lib/moderation/manualModerationProvider.js";
import {passesSmokeDiscoveryIsolation} from "../../functions/lib/smoke/smokeTestUsers.js";

describe("moderation pipeline integration", () => {
  it("rejects corrupt buffers even when content type claims image/png", async () => {
    const result = await moderatePhotoBuffer({
      contentType: "image/png",
      sizeBytes: 32,
      buffer: Buffer.from("not-a-real-png-file-contents"),
    });
    assert.equal(result.status, "rejected");
  });
});

describe("smoke user isolation", () => {
  it("allows real users to discover each other", () => {
    assert.equal(
      passesSmokeDiscoveryIsolation({accountStatus: "active"}, {accountStatus: "active"}),
      true,
    );
  });

  it("isolates smoke test users from production users", () => {
    assert.equal(
      passesSmokeDiscoveryIsolation({isSmokeTestUser: true}, {isSmokeTestUser: false}),
      false,
    );
    assert.equal(
      passesSmokeDiscoveryIsolation({isSmokeTestUser: true}, {isSmokeTestUser: true}),
      true,
    );
  });
});
