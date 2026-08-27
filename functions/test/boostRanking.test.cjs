const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  loadActiveBoostedUserIds,
  hasActiveBoostForUser,
  emitBoostLikeAnalytics,
  emitBoostMatchAnalytics,
} = require("../lib/boost/ranking.js");

function activeBoostDoc(expiresAt) {
  return {
    data() {
      return {
        status: "active",
        expiresAt: {toDate: () => expiresAt},
      };
    },
  };
}

describe("loadActiveBoostedUserIds resilience", () => {
  it("returns empty set when collection-group query fails", async () => {
    const db = {
      collectionGroup() {
        return {
          where() {
            return {
              async get() {
                const err = new Error(
                  "The query requires a COLLECTION_GROUP_ASC index for collection boosts and field status",
                );
                err.code = 9;
                throw err;
              },
            };
          },
        };
      },
    };
    const ids = await loadActiveBoostedUserIds(db);
    assert.equal(ids.size, 0);
  });
});

describe("hasActiveBoostForUser", () => {
  it("returns true for non-expired active boost", async () => {
    const db = {
      collection(path) {
        assert.match(path, /^users\/u1\/boosts$/);
        return {
          where(field, op, value) {
            assert.equal(field, "status");
            assert.equal(op, "==");
            assert.equal(value, "active");
            return {
              async get() {
                return {docs: [activeBoostDoc(new Date(Date.now() + 60_000))]};
              },
            };
          },
        };
      },
    };
    assert.equal(await hasActiveBoostForUser(db, "u1"), true);
  });

  it("returns false when boost already expired", async () => {
    const db = {
      collection() {
        return {
          where() {
            return {
              async get() {
                return {docs: [activeBoostDoc(new Date(Date.now() - 1_000))]};
              },
            };
          },
        };
      },
    };
    assert.equal(await hasActiveBoostForUser(db, "u1"), false);
  });

  it("returns false when query fails", async () => {
    const db = {
      collection() {
        return {
          where() {
            return {
              async get() {
                throw new Error("permission-denied");
              },
            };
          },
        };
      },
    };
    assert.equal(await hasActiveBoostForUser(db, "u1"), false);
  });
});

describe("boost analytics emits", () => {
  it("emitBoostLikeAnalytics no-ops without active boost", async () => {
    const db = {
      collection() {
        return {
          where() {
            return {
              async get() {
                return {docs: []};
              },
            };
          },
        };
      },
    };
    await emitBoostLikeAnalytics(db, {
      actorUid: "a",
      targetUid: "b",
      action: "like",
    });
  });

  it("emitBoostMatchAnalytics no-ops when neither user is boosted", async () => {
    const db = {
      collection() {
        return {
          where() {
            return {
              async get() {
                return {docs: []};
              },
            };
          },
        };
      },
    };
    await emitBoostMatchAnalytics(db, {
      matchId: "a_b",
      userIds: ["a", "b"],
    });
  });
});
