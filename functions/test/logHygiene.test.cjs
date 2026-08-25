const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {safeLogMeta} = require("../lib/security/logHygiene.js");

describe("logHygiene", () => {
  it("redacts sensitive keys and phone-like strings", () => {
    const out = safeLogMeta({
      uid: "abc",
      phone: "+905551112233",
      note: "call +90 555 111 22 33 later",
      nested: {token: "secret"},
    });
    assert.equal(out.phone, "[redacted]");
    assert.equal(out.nested.token, "[redacted]");
    assert.match(String(out.note), /redacted-phone/);
    assert.equal(out.uid, "abc");
  });
});
