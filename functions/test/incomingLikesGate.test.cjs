const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {shapeIncomingLikesResponse} = require("../lib/incomingLikesShape.js");

describe("incoming likes premium gate", () => {
  it("free users never receive identity items", () => {
    const shaped = shapeIncomingLikesResponse({
      isPremium: false,
      rows: [
        {fromUserId: "a", action: "like", createdAtMs: 1},
        {fromUserId: "b", action: "superLike", createdAtMs: 2},
      ],
      profiles: new Map([
        [
          "a",
          {
            uid: "a",
            displayName: "Ada",
            age: 28,
            photoUrl: "https://example.com/a.jpg",
            city: "Istanbul",
            action: "like",
            createdAtMs: 1,
          },
        ],
      ]),
    });
    assert.equal(shaped.locked, true);
    assert.equal(shaped.isPremium, false);
    assert.equal(shaped.premiumRequired, true);
    assert.equal(shaped.count, 2);
    assert.equal(shaped.incomingLikeCount, 2);
    assert.deepEqual(shaped.items, []);
  });

  it("premium users receive real liker previews", () => {
    const shaped = shapeIncomingLikesResponse({
      isPremium: true,
      rows: [{fromUserId: "a", action: "like", createdAtMs: 1}],
      profiles: new Map([
        [
          "a",
          {
            uid: "a",
            displayName: "Ada",
            age: 28,
            photoUrl: "https://example.com/a.jpg",
            city: "Istanbul",
            action: "like",
            createdAtMs: 1,
          },
        ],
      ]),
    });
    assert.equal(shaped.locked, false);
    assert.equal(shaped.isPremium, true);
    assert.equal(shaped.premiumRequired, false);
    assert.equal(shaped.count, 1);
    assert.equal(shaped.items[0].displayName, "Ada");
    assert.equal(shaped.items[0].photoUrl, "https://example.com/a.jpg");
  });
});
