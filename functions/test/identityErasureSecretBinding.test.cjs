/**
 * Provider-side erasure needs the Didit API key at runtime.
 *
 * Declaring a secret with `defineSecret` does not mount it: a function only
 * sees a secret listed in its own `secrets` option. Without the binding,
 * `requestIdentityProviderErasure` finds no key, answers `not_configured`, and
 * every departed member's identity documents wait for a human — in a
 * deployment whose key is set and working for everything else.
 *
 * Three functions can reach the erasure call:
 *   deleteUserAccount      the first attempt, during account deletion
 *   processAutomationTask  the retry job, dispatched by Cloud Tasks
 *   automationJobDrain     the same job, picked up by the scheduled drain
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {createFakeFirestore} = require("./helpers/fakeFirestore.cjs");
const {installFirebaseAdminStubs} = require("./helpers/adminStubs.cjs");

process.env.FIREBASE_CONFIG = JSON.stringify({
  projectId: "demo-erasure-binding",
  storageBucket: "demo-erasure-binding.appspot.com",
});
process.env.GCLOUD_PROJECT = "demo-erasure-binding";

// The modules bind getFirestore()/getAuth() at load.
installFirebaseAdminStubs({db: createFakeFirestore()});

const {deleteUserAccount} = require("../lib/deleteAccount.js");
const {processAutomationTask, automationJobDrain} = require("../lib/automation/schedules.js");
const {runForgedBlockAudit} = require("../lib/automation/forgedBlockAuditCallable.js");
const {createIdentityVerificationSession} = require("../lib/identity/createIdentityVerificationSession.js");
const {identityVerificationWebhook} = require("../lib/identity/identityVerificationWebhook.js");

/** The secrets a deployed function is actually given, from its manifest. */
const boundSecrets = (fn) =>
  (fn.__endpoint.secretEnvironmentVariables ?? []).map((entry) => entry.key).sort();

describe("the Didit API key reaches every function that can erase", () => {
  for (const [name, fn] of [
    ["deleteUserAccount", deleteUserAccount],
    ["processAutomationTask", processAutomationTask],
    ["automationJobDrain", automationJobDrain],
  ]) {
    it(`${name} binds DIDIT_API_KEY`, () => {
      assert.ok(
        boundSecrets(fn).includes("DIDIT_API_KEY"),
        `${name} can reach requestIdentityProviderErasure but is not given DIDIT_API_KEY, ` +
          "so erasure would report not_configured in a deployment",
      );
    });

    it(`${name} is not handed the webhook signing secret`, () => {
      // Erasure authenticates with the API key alone. The signing secret
      // belongs to the two functions that verify or create a session.
      assert.equal(boundSecrets(fn).includes("DIDIT_WEBHOOK_SECRET"), false);
    });
  }

  it("the binding did not cost the retry path its queue or schedule", () => {
    assert.ok(processAutomationTask.__endpoint.taskQueueTrigger, "still a task queue function");
    assert.equal(processAutomationTask.__endpoint.taskQueueTrigger.retryConfig.maxAttempts, 5);
    assert.equal(automationJobDrain.__endpoint.scheduleTrigger.schedule, "every 15 minutes");
    assert.equal(processAutomationTask.__endpoint.region[0], "europe-west1");
    assert.equal(automationJobDrain.__endpoint.region[0], "europe-west1");
    assert.equal(deleteUserAccount.__endpoint.region[0], "europe-west1");
  });

  it("the admin audit callable, which cannot run an erasure job, gets no key", () => {
    // It calls the job runner, but only ever for the forged-block audit job it
    // has just enqueued under its own id.
    assert.deepEqual(boundSecrets(runForgedBlockAudit), []);
  });

  it("the session and webhook entry points keep both of theirs", () => {
    for (const fn of [createIdentityVerificationSession, identityVerificationWebhook]) {
      assert.deepEqual(boundSecrets(fn), ["DIDIT_API_KEY", "DIDIT_WEBHOOK_SECRET"]);
    }
  });
});
