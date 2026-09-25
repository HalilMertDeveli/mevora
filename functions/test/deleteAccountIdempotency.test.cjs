const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {deleteAuthUserIfPresent} = require("../lib/deleteAccount.js");

/**
 * Deletion has to survive being asked twice.
 *
 * `deleteUserAccount` used to end with a bare `auth.deleteUser(uid)`. On a
 * retry — a double tap, a network retry, an app resume — the Auth record was
 * already gone, `auth/user-not-found` went unhandled, and the client got
 * 500 INTERNAL *after* the account had in fact been deleted. Every Firestore
 * step in that function is idempotent; the Auth step now is too.
 */
function authThatThrows(code) {
  return {
    calls: 0,
    async deleteUser() {
      this.calls += 1;
      const error = new Error("auth failure");
      error.code = code;
      throw error;
    },
  };
}

describe("account deletion is idempotent", () => {
  it("deletes the Auth record on the first attempt", async () => {
    const deleted = [];
    const client = {deleteUser: async (uid) => void deleted.push(uid)};

    await deleteAuthUserIfPresent(client, "uid-a");

    assert.deepEqual(deleted, ["uid-a"]);
  });

  it("treats an already-deleted Auth record as success", async () => {
    // The regression: this used to surface as 500 INTERNAL on a retry.
    const client = authThatThrows("auth/user-not-found");

    await assert.doesNotReject(() => deleteAuthUserIfPresent(client, "uid-a"));
    assert.equal(client.calls, 1);
  });

  it("still fails loudly on any other Auth error", async () => {
    // Swallowing everything would hide a real failure and leave a live account
    // behind while reporting success.
    for (const code of [
      "auth/internal-error",
      "auth/insufficient-permission",
      "auth/network-error",
      undefined,
    ]) {
      const client = authThatThrows(code);
      await assert.rejects(
        () => deleteAuthUserIfPresent(client, "uid-a"),
        (error) => error.message === "auth failure",
        `expected ${String(code)} to propagate`,
      );
    }
  });

  it("can be called repeatedly without throwing", async () => {
    let live = true;
    const client = {
      async deleteUser() {
        if (!live) {
          const error = new Error("gone");
          error.code = "auth/user-not-found";
          throw error;
        }
        live = false;
      },
    };

    await deleteAuthUserIfPresent(client, "uid-a");
    await deleteAuthUserIfPresent(client, "uid-a");
    await deleteAuthUserIfPresent(client, "uid-a");

    assert.equal(live, false);
  });
});
