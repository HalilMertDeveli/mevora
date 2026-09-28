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
 *   only when the callback resolves (a throw leaves the store untouched).
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

function codedError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

function createFakeFirestore(seed = {}) {
  const store = new Map();

  const reset = (next = {}) => {
    store.clear();
    for (const [path, data] of Object.entries(next)) {
      store.set(path, applyPatch({}, data, true));
    }
  };
  reset(seed);

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
  };
  const writeUpdate = (ref, data) => {
    if (!store.has(ref.path)) {
      throw codedError(5, `NOT_FOUND: No document to update: ${ref.path}`);
    }
    store.set(ref.path, applyUpdate(store.get(ref.path), data));
  };
  const writeCreate = (ref, data) => {
    if (store.has(ref.path)) {
      throw codedError(6, `ALREADY_EXISTS: ${ref.path}`);
    }
    store.set(ref.path, applyPatch({}, data, false));
  };
  const writeDelete = (ref) => {
    store.delete(ref.path);
  };

  function docRef(path) {
    const parts = segments(path);
    if (parts.length % 2 !== 0) {
      throw new Error(`fakeFirestore: document path must have an even number of segments: ${path}`);
    }
    const ref = {
      path,
      id: parts[parts.length - 1],
      get: async () => snapshotOf(ref),
      set: async (data, options) => writeSet(ref, data, options),
      update: async (data) => writeUpdate(ref, data),
      create: async (data) => writeCreate(ref, data),
      delete: async () => writeDelete(ref),
      collection: (sub) => collectionRef(`${path}/${sub}`),
    };
    return ref;
  }

  function collectionRef(path) {
    const parts = segments(path);
    if (parts.length % 2 !== 1) {
      throw new Error(`fakeFirestore: collection path must have an odd number of segments: ${path}`);
    }
    const build = (filters, max, order) => ({
      path,
      where: (field, op, value) => build([...filters, [field, op, value]], max, order),
      select: () => build(filters, max, order),
      limit: (n) => build(filters, n, order),
      orderBy: (field, direction = "asc") => build(filters, max, [field, direction]),
      doc: (id) => docRef(`${path}/${id}`),
      get: async () => {
        const prefix = `${path}/`;
        let docs = [];
        for (const [docPath, data] of store.entries()) {
          if (!docPath.startsWith(prefix)) continue;
          if (docPath.slice(prefix.length).includes("/")) continue;
          const matches = filters.every(([field, op, value]) => {
            const actual = fieldOf(data, field);
            if (op === "==") return actual === value;
            if (op === "array-contains") return Array.isArray(actual) && actual.includes(value);
            if (op === "in") return Array.isArray(value) && value.includes(actual);
            throw new Error(`fakeFirestore: unsupported operator ${op}`);
          });
          if (matches) docs.push(snapshotOf(docRef(docPath)));
        }
        docs.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
        if (order) {
          const [field, direction] = order;
          const sign = direction === "desc" ? -1 : 1;
          docs.sort((a, b) => {
            const av = a.get(field);
            const bv = b.get(field);
            return av < bv ? -sign : av > bv ? sign : 0;
          });
        }
        if (typeof max === "number") docs = docs.slice(0, max);
        return {docs, empty: docs.length === 0, size: docs.length};
      },
    });
    return build([], undefined, null);
  }

  function batch() {
    const ops = [];
    return {
      set(ref, data, options) {
        ops.push(() => writeSet(ref, data, options));
        return this;
      },
      update(ref, data) {
        ops.push(() => writeUpdate(ref, data));
        return this;
      },
      create(ref, data) {
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

  async function runTransaction(fn) {
    const writes = [];
    const tx = {
      async get(refOrQuery) {
        if (writes.length > 0) {
          throw new Error("fakeFirestore: transactions require all reads before all writes");
        }
        return typeof refOrQuery.where === "function"
          ? refOrQuery.get()
          : snapshotOf(refOrQuery);
      },
      async getAll(...refs) {
        return Promise.all(refs.map((ref) => tx.get(ref)));
      },
      set(ref, data, options) {
        writes.push(() => writeSet(ref, data, options));
        return tx;
      },
      update(ref, data) {
        writes.push(() => writeUpdate(ref, data));
        return tx;
      },
      create(ref, data) {
        writes.push(() => writeCreate(ref, data));
        return tx;
      },
      delete(ref) {
        writes.push(() => writeDelete(ref));
        return tx;
      },
    };
    const result = await fn(tx);
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
    batch,
    runTransaction,
    getAll: async (...refs) => refs.map((ref) => snapshotOf(ref)),
  };
}

module.exports = {createFakeFirestore};
