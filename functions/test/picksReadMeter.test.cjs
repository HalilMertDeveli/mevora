/**
 * The Picks read meter against the real Firestore SDK classes. The network
 * sits below the entry points the meter wraps, so it is stubbed there: the
 * meter wraps whatever those prototypes hold when it is first used.
 */
const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {DocumentReference, Firestore, Query, Transaction} = require("firebase-admin/firestore");

Firestore.prototype.getAll = async function(...args) {
  return args.filter((arg) => arg instanceof DocumentReference).map((ref) => ({id: ref.id, exists: false}));
};
Query.prototype.get = async function() {
  if (this.__fakeFail) throw new Error("UNAVAILABLE: fake outage");
  return {size: this.__fakeSize ?? 0, docs: []};
};
Transaction.prototype.get = async function(refOrQuery) {
  return refOrQuery instanceof DocumentReference ? {exists: false} : {size: refOrQuery.__fakeSize ?? 0, docs: []};
};
Transaction.prototype.getAll = async function(...refs) {
  return refs.map(() => ({exists: false}));
};

const {meterReads} = require("../lib/picks/readMeter.js");

const db = new Firestore({projectId: "demo-read-meter"});
const sized = (query, size) => Object.assign(query, {__fakeSize: size});

describe("Picks read meter", () => {
  it("counts reads the way Firestore bills them", async () => {
    const {result, tally} = await meterReads(async () => {
      await db.doc("users/a").get(); // 1, even though it does not exist
      await db.getAll(db.doc("users/b"), db.doc("users/c"), {fieldMask: ["x"]}); // 2
      await sized(db.collection("likes").where("a", "==", 1), 0).get(); // empty query: 1
      await sized(db.collection("profiles").limit(40), 40).get(); // 40
      const tx = Object.create(Transaction.prototype);
      await tx.get(db.doc("users/d")); // 1
      await tx.get(sized(db.collection("matches").limit(5), 5)); // 5
      await tx.getAll(db.doc("users/e"), db.doc("users/f")); // 2
      return "done";
    });
    assert.equal(result, "done");
    assert.deepEqual(tally, {reads: 1 + 2 + 1 + 40 + 1 + 5 + 2, documents: 6, queries: 3, queryDocuments: 45});
  });

  it("keeps concurrent opens apart", async () => {
    const one = meterReads(async () => {
      await db.doc("users/x").get();
      await new Promise((resolve) => setTimeout(resolve, 5));
      await db.doc("users/y").get();
    });
    const two = meterReads(async () => {
      await sized(db.collection("profiles"), 7).get();
    });
    const [a, b] = await Promise.all([one, two]);
    assert.equal(a.tally.reads, 2);
    assert.equal(b.tally.reads, 7);
  });

  it("changes no result and counts nothing outside a metered call", async () => {
    const snap = await db.doc("users/z").get();
    assert.equal(snap.exists, false);
    const {tally} = await meterReads(async () => undefined);
    assert.equal(tally.reads, 0);
  });

  it("a failing read still fails, and is not swallowed", async () => {
    const original = Query.prototype.get;
    await assert.rejects(() => meterReads(async () => {
      await Object.assign(db.collection("broken").where("x", "==", 1), {__fakeFail: true}).get();
    }), /fake outage/);
    assert.equal(Query.prototype.get, original, "the wrapper stays installed once");
  });
});
