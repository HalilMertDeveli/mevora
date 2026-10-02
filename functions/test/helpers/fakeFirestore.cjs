/**
 * In-memory Firestore double for behavioural backend tests that must run in
 * plain `npm test` (no emulator).
 *
 * It implements the subset the humor and deletion code paths use, with the
 * semantics that matter for them:
 * - document / collection paths are validated like the real SDK, so a `/`
 *   smuggled into an id fails the same way it would in production;
 * - `set(..., {merge: true})` deep-merges maps, `update` requires the document;
 * - FieldValue.serverTimestamp / increment / delete / arrayUnion / arrayRemove
 *   are applied, not stubbed;
 * - a transaction must read before it writes, and its writes land atomically
 *   only when the callback resolves (a throw leaves the store untouched);
 * - a JS Date is stored as a Timestamp, as the real SDK does;
 * - a write carrying undefined anywhere in its data (a map field, an array
 *   element) is refused, as the real SDK does without
 *   ignoreUndefinedProperties; seeds passed to the factory / reset() are not
 *   writes and are not checked;
 * - queries support ==, !=, in, array-contains and the range operators,
 *   filters on the document id (FieldPath.documentId() / "__name__": ids for
 *   a collection, full paths for a collection group, or references);
 *   several orderBy clauses (including "__name__"), startAfter by values or
 *   by a document snapshot (with the implicit document-name tie-break), and
 *   count() aggregation;
 * - transactions are optimistic like the real service: a transaction whose
 *   read documents changed before it commits is re-run (up to 5 attempts),
 *   so concurrent callers see each other's writes the way they would live.
 * - reads and writes are metered the way Firestore bills them: one read per
 *   document fetched (a missing one included), one per document a query
 *   returns and at least one per query; `stats()` / `resetStats()`.
 *
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */
const {Timestamp} = require("firebase-admin/firestore");

let tick = 0;
function serverNow() {
  tick += 1;
  return Timestamp.fromMillis(Date.now() + tick);
}

function isPlainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null)
  );
}

function transformName(value) {
  if (value === null || typeof value !== "object") return null;
  const name = value.methodName;
  return typeof name === "string" && name.startsWith("FieldValue.") ? name : null;
}

function clone(value) {
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (Array.isArray(value)) return value.map(clone);
  if (isPlainObject(value)) {
    const out = {};
    for (const [k, v] of Object.entries(value)) out[k] = clone(v);
    return out;
  }
  return value; // Timestamps and other immutable values are shared.
}

function resolveTransform(value, previous) {
  switch (transformName(value)) {
    case "FieldValue.serverTimestamp":
      return serverNow();
    case "FieldValue.increment":
      return (typeof previous === "number" ? previous : 0) + value.operand;
    case "FieldValue.arrayUnion": {
      const base = Array.isArray(previous) ? [...previous] : [];
      for (const el of value.elements) if (!base.includes(el)) base.push(el);
      return base;
    }
    case "FieldValue.arrayRemove": {
      const base = Array.isArray(previous) ? previous : [];
      return base.filter((el) => !value.elements.includes(el));
    }
    default:
      throw new Error(`fakeFirestore: unsupported transform ${transformName(value)}`);
  }
}

/**
 * The real SDK refuses undefined anywhere in the data of a write (no suite
 * turns on ignoreUndefinedProperties, and neither does functions/src), naming
 * the field the way this does.
 */
function assertNoUndefined(value, fieldPath = "") {
  if (value === undefined) {
    throw new Error(
      "Value for argument \"data\" is not a valid Firestore document. " +
        `Cannot use "undefined" as a Firestore value (found in field "${fieldPath}").`,
    );
  }
  if (Array.isArray(value)) {
    value.forEach((element, index) => {
      assertNoUndefined(element, fieldPath ? `${fieldPath}.\`${index}\`` : `\`${index}\``);
    });
  } else if (isPlainObject(value)) {
    for (const [key, child] of Object.entries(value)) {
      assertNoUndefined(child, fieldPath ? `${fieldPath}.${key}` : key);
    }
  }
}

/** Applies a (possibly nested) patch onto `target`, honouring transforms. */
function applyPatch(target, patch, deep) {
  const out = {...target};
  for (const [key, value] of Object.entries(patch)) {
    const name = transformName(value);
    if (name === "FieldValue.delete") {
      delete out[key];
    } else if (name) {
      out[key] = resolveTransform(value, out[key]);
    } else if (deep && isPlainObject(value) && isPlainObject(out[key])) {
      out[key] = applyPatch(out[key], value, true);
    } else if (isPlainObject(value)) {
      out[key] = applyPatch({}, value, true);
    } else {
      out[key] = clone(value);
    }
  }
  return out;
}

/** `update()` takes dotted field paths. */
function applyUpdate(target, patch) {
  let out = clone(target);
  for (const [fieldPath, value] of Object.entries(patch)) {
    const parts = fieldPath.split(".");
    const last = parts.pop();
    let cursor = out;
    for (const part of parts) {
      if (!isPlainObject(cursor[part])) cursor[part] = {};
      cursor = cursor[part];
    }
    const name = transformName(value);
    if (name === "FieldValue.delete") delete cursor[last];
    else if (name) cursor[last] = resolveTransform(value, cursor[last]);
    else cursor[last] = clone(value);
  }
  return out;
}

function segments(path) {
  if (typeof path !== "string" || path.length === 0) {
    throw new Error(`fakeFirestore: invalid path ${String(path)}`);
  }
  const parts = path.split("/");
  if (parts.some((part) => part.length === 0)) {
    throw new Error(`fakeFirestore: invalid path ${path}`);
  }
  return parts;
}

function fieldOf(data, fieldPath) {
  return fieldPath.split(".").reduce((acc, key) => (acc == null ? undefined : acc[key]), data);
}

/** Firestore-ish ordering: null < numbers < strings < timestamps. */
function sortKey(value) {
  if (value === null || value === undefined) return [0, 0];
  if (typeof value === "boolean") return [1, value ? 1 : 0];
  if (typeof value === "number") return [2, value];
  if (value instanceof Timestamp) return [4, value.toMillis()];
  if (value instanceof Date) return [4, value.getTime()];
  if (typeof value === "string") return [3, value];
  return [5, String(value)];
}

function compareValues(a, b) {
  const [ta, va] = sortKey(a);
  const [tb, vb] = sortKey(b);
  if (ta !== tb) return ta < tb ? -1 : 1;
  return va < vb ? -1 : va > vb ? 1 : 0;
}

function equalValues(a, b) {
  if (a instanceof Timestamp || b instanceof Timestamp) {
    return a != null && b != null && compareValues(a, b) === 0;
  }
  return a === b;
}

function codedError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function createFakeFirestore(seed = {}) {
  const store = new Map();
  const versions = new Map();
  const meter = {reads: 0, writes: 0, queries: [], byPath: new Map()};
  const noteDocRead = (path) => meter.byPath.set(path, (meter.byPath.get(path) ?? 0) + 1);
  const bump = (path) => {
    versions.set(path, (versions.get(path) ?? 0) + 1);
    meter.writes += 1;
  };
  const resetStats = () => {
    meter.reads = 0;
    meter.writes = 0;
    meter.queries = [];
    meter.byPath = new Map();
  };

  const reset = (next = {}) => {
    resetStats();
    store.clear();
    for (const [path, data] of Object.entries(next)) {
      store.set(path, applyPatch({}, data, true));
    }
  };
  reset(seed);
  resetStats();

  const snapshotOf = (ref) => {
    const data = store.get(ref.path);
    return {
      id: ref.id,
      ref,
      exists: data !== undefined,
      data: () => (data === undefined ? undefined : clone(data)),
      get: (field) => (data === undefined ? undefined : clone(fieldOf(data, field))),
    };
  };

  // --- write primitives (shared by refs, batches and transactions) -------
  const writeSet = (ref, data, options) => {
    const merge = Boolean(options && options.merge);
    const previous = merge ? store.get(ref.path) ?? {} : {};
    store.set(ref.path, applyPatch(previous, data, merge));
    bump(ref.path);
  };
  const writeUpdate = (ref, data) => {
    if (!store.has(ref.path)) {
      throw codedError(5, `NOT_FOUND: No document to update: ${ref.path}`);
    }
    store.set(ref.path, applyUpdate(store.get(ref.path), data));
    bump(ref.path);
  };
  const writeCreate = (ref, data) => {
    if (store.has(ref.path)) {
      throw codedError(6, `ALREADY_EXISTS: ${ref.path}`);
    }
    store.set(ref.path, applyPatch({}, data, false));
    bump(ref.path);
  };
  const writeDelete = (ref) => {
    store.delete(ref.path);
    bump(ref.path);
  };

  function docRef(path) {
    const parts = segments(path);
    if (parts.length % 2 !== 0) {
      throw new Error(`fakeFirestore: document path must have an even number of segments: ${path}`);
    }
    const ref = {
      path,
      id: parts[parts.length - 1],
      get: async () => {
        meter.reads += 1;
        noteDocRead(ref.path);
        return snapshotOf(ref);
      },
      set: async (data, options) => {
        assertNoUndefined(data);
        writeSet(ref, data, options);
      },
      update: async (data) => {
        assertNoUndefined(data);
        writeUpdate(ref, data);
      },
      create: async (data) => {
        assertNoUndefined(data);
        writeCreate(ref, data);
      },
      delete: async () => writeDelete(ref),
      collection: (sub) => collectionRef(`${path}/${sub}`),
      // The containing collection, as far as `ref.parent.parent?.id` needs it.
      get parent() {
        return {
          id: parts[parts.length - 2],
          path: parts.slice(0, -1).join("/"),
          parent: parts.length > 2 ? docRef(parts.slice(0, -2).join("/")) : null,
        };
      },
    };
    return ref;
  }

  function collectionRef(path) {
    const parts = segments(path);
    if (parts.length % 2 !== 1) {
      throw new Error(`fakeFirestore: collection path must have an odd number of segments: ${path}`);
    }
    const prefix = `${path}/`;
    return queryOver(
      path,
      (docPath) => docPath.startsWith(prefix) && !docPath.slice(prefix.length).includes("/"),
    );
  }

  /** Every document whose immediate parent collection is `collectionId`. */
  function collectionGroup(collectionId) {
    return queryOver(collectionId, (docPath) => {
      const parts = segments(docPath);
      return parts.length >= 2 && parts[parts.length - 2] === collectionId;
    }, true);
  }

  function queryOver(path, inScope, isGroup = false) {
    const valueFor = (snap, field) => {
      if (field === "__name__") return isGroup ? snap.ref.path : snap.id;
      return snap.get(field);
    };
    const run = (filters, max, orders, cursor) => {
      let docs = [];
      for (const [docPath, data] of store.entries()) {
        if (!inScope(docPath)) continue;
        const matches = filters.every(([rawField, op, rawValue]) => {
          // FieldPath.documentId() stringifies to "__name__".
          const field = typeof rawField === "string" ? rawField : String(rawField);
          const byId = field === "__name__";
          const idOf = (v) => (typeof v === "string" ? v : isGroup ? v.path : v.id);
          const actual = byId ? (isGroup ? docPath : segments(docPath).slice(-1)[0]) : fieldOf(data, field);
          const value = byId ? (Array.isArray(rawValue) ? rawValue.map(idOf) : idOf(rawValue)) : rawValue;
          switch (op) {
          case "==": return equalValues(actual, value);
          case "!=": return actual !== undefined && !equalValues(actual, value);
          case "array-contains": return Array.isArray(actual) && actual.includes(value);
          case "in": return Array.isArray(value) && value.some((v) => equalValues(actual, v));
          case "<": return actual !== undefined && actual !== null && compareValues(actual, value) < 0;
          case "<=": return actual !== undefined && actual !== null && compareValues(actual, value) <= 0;
          case ">": return actual !== undefined && actual !== null && compareValues(actual, value) > 0;
          case ">=": return actual !== undefined && actual !== null && compareValues(actual, value) >= 0;
          default: throw new Error(`fakeFirestore: unsupported operator ${op}`);
          }
        });
        if (matches) docs.push(snapshotOf(docRef(docPath)));
      }
      docs.sort((a, b) => (a.ref.path < b.ref.path ? -1 : a.ref.path > b.ref.path ? 1 : 0));
      if (orders.length) {
        // Like Firestore, ordering on a field excludes documents without it.
        docs = docs.filter((d) => orders.every(([field]) => field === "__name__" || d.get(field) !== undefined));
        docs.sort((a, b) => {
          for (const [field, direction] of orders) {
            const c = compareValues(valueFor(a, field), valueFor(b, field));
            if (c !== 0) return direction === "desc" ? -c : c;
          }
          return 0;
        });
      }
      if (cursor) {
        // A snapshot cursor positions on that document: its values for every
        // ordered field, then its name, in the last ordering's direction.
        const snapshotCursor = cursor.length === 1 && cursor[0] && typeof cursor[0].get === "function" &&
          cursor[0].ref ? cursor[0] : null;
        const values = snapshotCursor ? orders.map(([field]) => valueFor(snapshotCursor, field)) : cursor;
        const lastDirection = orders.length ? orders[orders.length - 1][1] : "asc";
        docs = docs.filter((d) => {
          for (let i = 0; i < orders.length && i < values.length; i++) {
            const [field, direction] = orders[i];
            const c = compareValues(valueFor(d, field), values[i]);
            if (c !== 0) return direction === "desc" ? c < 0 : c > 0;
          }
          if (!snapshotCursor) return false;
          const byName = compareValues(d.ref.path, snapshotCursor.ref.path);
          return lastDirection === "desc" ? byName < 0 : byName > 0;
        });
      }
      if (typeof max === "number") docs = docs.slice(0, max);
      return docs;
    };
    const build = (filters, max, orders, cursor) => ({
      path,
      where: (field, op, value) => build([...filters, [field, op, value]], max, orders, cursor),
      select: () => build(filters, max, orders, cursor),
      limit: (n) => build(filters, n, orders, cursor),
      orderBy: (field, direction = "asc") => build(filters, max, [...orders, [field, direction]], cursor),
      startAfter: (...values) => build(filters, max, orders, values),
      doc: (id) => docRef(`${path}/${id}`),
      count: () => ({get: async () => {
        const n = run(filters, max, orders, cursor).length;
        meter.reads += 1;
        return {data: () => ({count: n})};
      }}),
      get: async () => {
        const docs = run(filters, max, orders, cursor);
        meter.reads += Math.max(1, docs.length);
        meter.queries.push({
          path,
          group: isGroup,
          docs: docs.length,
          filters: filters.map(([field, op]) => `${String(field)} ${op}`),
        });
        docs.forEach((doc) => noteDocRead(doc.ref.path));
        return {docs, empty: docs.length === 0, size: docs.length};
      },
    });
    return build([], undefined, [], null);
  }

  function batch() {
    const ops = [];
    return {
      set(ref, data, options) {
        assertNoUndefined(data);
        ops.push(() => writeSet(ref, data, options));
        return this;
      },
      update(ref, data) {
        assertNoUndefined(data);
        ops.push(() => writeUpdate(ref, data));
        return this;
      },
      create(ref, data) {
        assertNoUndefined(data);
        ops.push(() => writeCreate(ref, data));
        return this;
      },
      delete(ref) {
        ops.push(() => writeDelete(ref));
        return this;
      },
      async commit() {
        const before = new Map(store);
        try {
          for (const op of ops) op();
        } catch (error) {
          store.clear();
          for (const [k, v] of before) store.set(k, v);
          throw error;
        }
      },
    };
  }

  async function runTransaction(fn, attempt = 1) {
    const writes = [];
    const readVersions = new Map();
    const noteRead = (path) => {
      if (!readVersions.has(path)) readVersions.set(path, versions.get(path) ?? 0);
    };
    const tx = {
      async get(refOrQuery) {
        if (writes.length > 0) {
          throw new Error("fakeFirestore: transactions require all reads before all writes");
        }
        if (typeof refOrQuery.where === "function") {
          const result = await refOrQuery.get();
          result.docs.forEach((d) => noteRead(d.ref.path));
          return result;
        }
        noteRead(refOrQuery.path);
        meter.reads += 1;
        noteDocRead(refOrQuery.path);
        // Yield like a network read, so concurrent transactions interleave.
        await Promise.resolve();
        return snapshotOf(refOrQuery);
      },
      async getAll(...refs) {
        return Promise.all(refs.map((ref) => tx.get(ref)));
      },
      set(ref, data, options) {
        assertNoUndefined(data);
        writes.push(() => writeSet(ref, data, options));
        return tx;
      },
      update(ref, data) {
        assertNoUndefined(data);
        writes.push(() => writeUpdate(ref, data));
        return tx;
      },
      create(ref, data) {
        assertNoUndefined(data);
        writes.push(() => writeCreate(ref, data));
        return tx;
      },
      delete(ref) {
        writes.push(() => writeDelete(ref));
        return tx;
      },
    };
    const result = await fn(tx);
    const conflicted = [...readVersions].some(([path, version]) => (versions.get(path) ?? 0) !== version);
    if (conflicted) {
      if (attempt >= 5) {
        throw codedError(10, "ABORTED: too much contention");
      }
      return runTransaction(fn, attempt + 1);
    }
    const before = new Map(store);
    try {
      for (const write of writes) write();
    } catch (error) {
      store.clear();
      for (const [k, v] of before) store.set(k, v);
      throw error;
    }
    return result;
  }

  return {
    _store: store,
    reset,
    /** Plain copy of one document, or undefined. */
    read: (path) => (store.has(path) ? clone(store.get(path)) : undefined),
    has: (path) => store.has(path),
    paths: () => [...store.keys()].sort(),
    doc: docRef,
    collection: collectionRef,
    collectionGroup,
    batch,
    runTransaction,
    getAll: async (...refs) => {
      meter.reads += refs.length;
      refs.forEach((ref) => noteDocRead(ref.path));
      return refs.map((ref) => snapshotOf(ref));
    },
    /** Billing-equivalent reads and writes since the last reset. */
    stats: () => ({
      reads: meter.reads,
      writes: meter.writes,
      queries: [...meter.queries],
      /** Document path → how many times it was read (fetched or returned by a query). */
      byPath: new Map(meter.byPath),
    }),
    resetStats,
  };
}

module.exports = {createFakeFirestore};
