const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {loadActiveBoostedUserIds} = require("../lib/boost/ranking.js");

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
