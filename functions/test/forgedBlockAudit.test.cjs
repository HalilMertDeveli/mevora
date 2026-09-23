const {describe, it} = require("node:test");
const assert = require("node:assert/strict");
const {
  BlockAnomaly,
  DEFAULT_PAGE_SIZE,
  auditForgedBlocks,
  canonicalBlockId,
  classifyBlockDocument,
  reviewDocId,
} = require("../lib/automation/forgedBlockAudit.js");

const A = "user-a";
const B = "user-b";
const C = "user-c";

/**
 * In-memory Firestore stand-in covering exactly what the audit uses:
 * collection().orderBy("__name__").limit().startAfter().get() plus
 * collection().doc().set(). Every write is recorded so a test can prove the
 * scan never touched `blocks`.
 */
function fakeDb(blocks) {
  const writes = [];
  const docs = Object.entries(blocks)
    .map(([id, data]) => ({id, data: () => data}))
    .sort((x, y) => (x.id < y.id ? -1 : x.id > y.id ? 1 : 0));

  function makeQuery(collectionId, state) {
    return {
      orderBy() {
        return makeQuery(collectionId, {...state});
      },
      limit(n) {
        return makeQuery(collectionId, {...state, limit: n});
      },
      startAfter(cursor) {
        return makeQuery(collectionId, {...state, after: cursor});
      },
      async get() {
        let rows = docs;
        if (state.after) {
          rows = rows.filter((d) => d.id > state.after);
        }
        const limited = rows.slice(0, state.limit ?? rows.length);
        state.pagesServed.count += 1;
        return {docs: limited, empty: limited.length === 0, size: limited.length};
      },
    };
  }

  const pagesServed = {count: 0};
  return {
    writes,
    pagesServed,
    collection(id) {
      if (id === "blocks") {
        return makeQuery(id, {pagesServed});
      }
      return {
        doc(docId) {
          return {
            async set(data, opts) {
              writes.push({collection: id, docId, data, opts});
            },
          };
        },
      };
    },
    doc(path) {
      return {
        async set(data, opts) {
          writes.push({collection: path.split("/")[0], docId: path, data, opts});
        },
      };
    },
  };
}

const blockWrites = (db) => db.writes.filter((w) => w.collection === "blocks");
const reviewWrites = (db) => db.writes.filter((w) => w.collection === "adminReviewQueue");

describe("forged block audit — classification", () => {
  it("ignores a valid canonical block", () => {
    const finding = classifyBlockDocument(canonicalBlockId(A, B), {
      blockerId: A,
      blockedUserId: B,
      createdAt: new Date(),
    });
    assert.equal(finding, null);
  });

  it("flags the B-01 third-party forgery: blocks/A_B carrying blockerId C", () => {
    const finding = classifyBlockDocument(canonicalBlockId(A, B), {
      blockerId: C,
      blockedUserId: B,
    });
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.idMismatch));
    assert.equal(finding.expectedId, canonicalBlockId(C, B));
    assert.equal(finding.blockId, canonicalBlockId(A, B));
  });

  it("flags an arbitrary document id", () => {
    const finding = classifyBlockDocument("random-id", {blockerId: A, blockedUserId: B});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.idMismatch));
    assert.equal(finding.expectedId, canonicalBlockId(A, B));
  });

  it("flags a self block", () => {
    const finding = classifyBlockDocument(canonicalBlockId(A, A), {
      blockerId: A,
      blockedUserId: A,
    });
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.selfBlock));
  });

  it("flags a missing blockerId", () => {
    const finding = classifyBlockDocument(canonicalBlockId(A, B), {blockedUserId: B});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.missingBlockerId));
  });

  it("flags a missing blockedUserId", () => {
    const finding = classifyBlockDocument(canonicalBlockId(A, B), {blockerId: A});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.missingBlockedUserId));
  });

  it("flags an empty uid", () => {
    const finding = classifyBlockDocument("_", {blockerId: "", blockedUserId: ""});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.emptyBlockerId));
    assert.ok(finding.anomalies.includes(BlockAnomaly.emptyBlockedUserId));
  });

  it("flags an invalid field type", () => {
    const finding = classifyBlockDocument("x", {blockerId: 42, blockedUserId: {nested: true}});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.invalidFieldType));
    // Unusable fields mean no canonical id can be computed, so no false
    // id_mismatch is reported on top of the type error.
    assert.equal(finding.expectedId, null);
  });

  it("flags a completely empty document", () => {
    const finding = classifyBlockDocument("orphan", {});
    assert.ok(finding);
    assert.ok(finding.anomalies.includes(BlockAnomaly.missingBlockerId));
    assert.ok(finding.anomalies.includes(BlockAnomaly.missingBlockedUserId));
  });
});

describe("forged block audit — scan behaviour", () => {
  it("is a dry run: it never writes to the blocks collection", async () => {
    const db = fakeDb({
      [canonicalBlockId(A, B)]: {blockerId: C, blockedUserId: B},
      [canonicalBlockId(B, C)]: {blockerId: B, blockedUserId: C},
      "random-id": {blockerId: A, blockedUserId: C},
    });
    const result = await auditForgedBlocks({db});
    assert.equal(result.dryRun, true);
    assert.equal(result.blockWrites, 0);
    assert.deepEqual(blockWrites(db), [], "the audit must not modify blocks");
  });

  it("separates well-formed from malformed records", async () => {
    const db = fakeDb({
      [canonicalBlockId(A, B)]: {blockerId: A, blockedUserId: B},
      [canonicalBlockId(B, C)]: {blockerId: B, blockedUserId: C},
      [canonicalBlockId(A, C)]: {blockerId: C, blockedUserId: A},
      "legacy-weird": {blockerId: A, blockedUserId: C},
      [canonicalBlockId(C, C)]: {blockerId: C, blockedUserId: C},
    });
    const result = await auditForgedBlocks({db});
    assert.equal(result.scanned, 5);
    assert.equal(result.flagged, 3);
    assert.equal(result.complete, true);
    assert.equal(result.nextCursor, null);
    assert.equal(result.anomalyCounts[BlockAnomaly.idMismatch], 2);
    assert.equal(result.anomalyCounts[BlockAnomaly.selfBlock], 1);
  });

  it("records only the minimum review metadata — no profile data", async () => {
    const db = fakeDb({[canonicalBlockId(A, B)]: {blockerId: C, blockedUserId: B}});
    await auditForgedBlocks({db, jobId: "job-1"});
    const rows = reviewWrites(db);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].docId, reviewDocId(canonicalBlockId(A, B)));
    assert.deepEqual(
      Object.keys(rows[0].data).sort(),
      [
        "anomalies",
        "auditedAt",
        "blockId",
        "blockedUserId",
        "blockerId",
        "expectedId",
        "jobId",
        "remediation",
        "status",
        "type",
      ],
      "review rows must carry audit metadata only",
    );
    assert.equal(rows[0].data.remediation, "manual_review_required");
    assert.equal(rows[0].data.status, "open");
  });

  it("is idempotent: a second pass reuses the same review document id", async () => {
    const blocks = {[canonicalBlockId(A, B)]: {blockerId: C, blockedUserId: B}};
    const first = fakeDb(blocks);
    await auditForgedBlocks({db: first});
    const second = fakeDb(blocks);
    await auditForgedBlocks({db: second});

    const id1 = reviewWrites(first)[0].docId;
    const id2 = reviewWrites(second)[0].docId;
    assert.equal(id1, id2, "deterministic id prevents duplicate review rows");
    assert.equal(reviewWrites(second).length, 1);
    // Merge keeps an in-progress human review from being clobbered.
    assert.deepEqual(reviewWrites(second)[0].opts, {merge: true});
  });

  it("paginates across a batch boundary and inspects every document once", async () => {
    const blocks = {};
    for (let i = 0; i < 25; i += 1) {
      const id = `pair-${String(i).padStart(3, "0")}`;
      // Every third record is malformed.
      blocks[id] = i % 3 === 0 ? {blockerId: A, blockedUserId: B} : {blockerId: id, blockedUserId: B};
    }
    // Canonical ids for the well-formed ones so only the intended rows flag.
    for (let i = 0; i < 25; i += 1) {
      if (i % 3 !== 0) {
        const id = `pair-${String(i).padStart(3, "0")}`;
        delete blocks[id];
        blocks[canonicalBlockId(id, B)] = {blockerId: id, blockedUserId: B};
      }
    }
    const db = fakeDb(blocks);
    const result = await auditForgedBlocks({db, pageSize: 4});
    assert.equal(result.scanned, 25);
    assert.equal(result.complete, true);
    assert.ok(result.pages > 1, "expected more than one page");
    assert.equal(result.flagged, 9, "the nine malformed records should flag");
    assert.deepEqual(blockWrites(db), []);
  });

  it("stops at maxPages and hands back a resume cursor", async () => {
    const blocks = {};
    for (let i = 0; i < 20; i += 1) {
      blocks[`b-${String(i).padStart(3, "0")}`] = {blockerId: A, blockedUserId: B};
    }
    const db = fakeDb(blocks);
    const result = await auditForgedBlocks({db, pageSize: 5, maxPages: 2});
    assert.equal(result.complete, false);
    assert.equal(result.scanned, 10);
    assert.ok(result.nextCursor, "an incomplete scan must return a cursor");

    // Resuming from the cursor covers the remainder without rescanning.
    const db2 = fakeDb(blocks);
    const rest = await auditForgedBlocks({db: db2, pageSize: 5, startAfterId: result.nextCursor});
    assert.equal(rest.scanned, 10);
    assert.equal(rest.complete, true);
  });

  it("handles an empty blocks collection", async () => {
    const db = fakeDb({});
    const result = await auditForgedBlocks({db});
    assert.equal(result.scanned, 0);
    assert.equal(result.flagged, 0);
    assert.equal(result.complete, true);
    assert.deepEqual(db.writes, []);
  });

  it("defaults to a bounded page size", () => {
    assert.ok(DEFAULT_PAGE_SIZE > 0 && DEFAULT_PAGE_SIZE <= 1000);
  });
});

describe("forged block audit — no cleanup surface exists", () => {
  const {readFileSync} = require("node:fs");
  const {resolve} = require("node:path");
  const auditSource = readFileSync(
    resolve(__dirname, "../src/automation/forgedBlockAudit.ts"),
    "utf8",
  );
  const callableSource = readFileSync(
    resolve(__dirname, "../src/automation/forgedBlockAuditCallable.ts"),
    "utf8",
  );

  it("the audit module never deletes or updates a block", () => {
    assert.equal(/\.delete\(/.test(auditSource), false, "no delete() in the audit module");
    assert.equal(
      /collection\(BLOCKS_COLLECTION\)[\s\S]{0,200}\.(set|update|delete)\(/.test(auditSource),
      false,
      "no write path against the blocks collection",
    );
  });

  it("the callable exposes no destructive parameter", () => {
    for (const forbidden of ["delete", "repair", "fix", "cleanup", "migrate"]) {
      assert.equal(
        new RegExp(`data\\.${forbidden}`).test(callableSource),
        false,
        `callable must not accept a '${forbidden}' parameter`,
      );
    }
  });

  it("the callable is admin gated", () => {
    assert.match(callableSource, /requireAdmin\(request\)/);
  });
});

describe("forged block audit — admin gate is enforced", () => {
  process.env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "demo-block-audit",
    storageBucket: "demo-block-audit.appspot.com",
  });
  process.env.GCLOUD_PROJECT = "demo-block-audit";
  const {requireAdmin} = require("../lib/automation/jobs.js");

  const call = (request) => {
    try {
      return {uid: requireAdmin(request)};
    } catch (error) {
      return {code: error.code, message: error.message};
    }
  };

  it("rejects an unauthenticated caller", () => {
    assert.equal(call({}).code, "unauthenticated");
  });

  it("rejects an ordinary authenticated user", () => {
    assert.equal(call({auth: {uid: A, token: {}}}).code, "permission-denied");
  });

  it("rejects a user with a forged Firestore-style admin field", () => {
    // Admin authority is the Auth custom claim only; a token without it is
    // refused no matter what a user document claims.
    assert.equal(call({auth: {uid: A, token: {isAdmin: true, admin: false}}}).code, "permission-denied");
  });

  it("admits a caller holding the admin custom claim", () => {
    assert.equal(call({auth: {uid: A, token: {admin: true}}}).uid, A);
  });
});
