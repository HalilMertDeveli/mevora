const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  requestSumsubApplicantDeletion,
} = require("../lib/sumsub/sumsubApplicantLifecycle.js");
const {SumsubApiError} = require("../lib/sumsub/sumsubClient.js");

const APPLICANT_ID = "5f9a2b1c3d4e5f6a7b8c9d0e";

/** Records calls and replays scripted outcomes at the HTTP client boundary. */
function stubClient(outcomes = {}) {
  const calls = [];
  return {
    calls,
    async request(method, path) {
      calls.push({method, path});
      const key = path.includes("/reset") ? "reset" : "deactivate";
      const outcome = outcomes[key];
      if (outcome instanceof Error) {
        throw outcome;
      }
      return outcome ?? {ok: 1};
    },
  };
}

describe("sumsub applicant lifecycle", () => {
  it("does nothing when the account has no applicant id", async () => {
    const client = stubClient();
    const result = await requestSumsubApplicantDeletion({uid: "uid-1", client});
    assert.equal(result, "no-applicant");
    assert.equal(client.calls.length, 0);
  });

  it("refuses an applicant id that is not a Sumsub id", async () => {
    const client = stubClient();
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: "../../resources/applicants/other",
      client,
    });
    assert.equal(result, "invalid-applicant-id");
    assert.equal(client.calls.length, 0);
  });

  it("resets then deactivates the applicant", async () => {
    const client = stubClient();
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    assert.equal(result, "reset-and-deactivated");
    assert.deepEqual(client.calls, [
      {method: "POST", path: `/resources/applicants/${APPLICANT_ID}/reset`},
      {
        method: "PATCH",
        path: `/resources/applicants/${APPLICANT_ID}/presence/deactivated`,
      },
    ]);
  });

  it("treats an unknown applicant as already gone", async () => {
    for (const status of [400, 404]) {
      const client = stubClient({reset: new SumsubApiError(status, "sumsub-api-failed")});
      const result = await requestSumsubApplicantDeletion({
        uid: "uid-1",
        applicantId: APPLICANT_ID,
        client,
      });
      assert.equal(result, "already-absent", `status ${status}`);
      assert.equal(client.calls.length, 1, "must not try to deactivate");
    }
  });

  it("keeps the reset when deactivation is refused mid-review", async () => {
    // Sumsub rejects deactivation while a review is pending/queued/prechecked.
    const client = stubClient({
      deactivate: new SumsubApiError(409, "sumsub-api-failed"),
    });
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    assert.equal(result, "reset-only");
    assert.equal(client.calls.length, 2);
  });

  it("reports a remote failure without throwing", async () => {
    const client = stubClient({reset: new SumsubApiError(500, "sumsub-api-failed")});
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    assert.equal(result, "remote-failure");
  });

  it("never rejects when the transport itself fails", async () => {
    const client = stubClient({reset: new TypeError("fetch failed")});
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    assert.equal(result, "remote-failure");
  });

  it("is idempotent: a second run on a missing applicant still succeeds", async () => {
    const client = stubClient({reset: new SumsubApiError(404, "sumsub-api-failed")});
    const first = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    const second = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
      client,
    });
    assert.equal(first, "already-absent");
    assert.equal(second, "already-absent");
  });

  it("skips silently when Sumsub credentials are not configured", async () => {
    // No client injected and no secrets in the environment.
    const result = await requestSumsubApplicantDeletion({
      uid: "uid-1",
      applicantId: APPLICANT_ID,
    });
    assert.equal(result, "not-configured");
  });
});
