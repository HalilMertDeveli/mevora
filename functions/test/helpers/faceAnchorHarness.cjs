/**
 * Fixtures for the Face Anchor suites: the in-memory Firestore double, an
 * in-memory bucket, a scriptable verification provider and a clock.
 *
 * Drives the real service functions (lib/faceAnchor/faceAnchorService.js).
 * Nothing here can reach a network or a real project.
 *
 * Not a test file (no `.test.cjs` suffix), so the runner ignores it.
 */
const {Timestamp} = require("firebase-admin/firestore");
const {createFakeFirestore} = require("./fakeFirestore.cjs");
const {FaceProviderError} = require("../../lib/faceAnchor/provider.js");
const {FACE_ANCHOR_CONSENT_VERSION} = require("../../lib/faceAnchor/faceAnchorRecord.js");

const T0 = Date.parse("2026-10-01T09:00:00Z");

// Smallest byte strings the service accepts as "an image": a JPEG and a PNG
// signature followed by filler. The provider is a double, so no pixels needed.
const JPEG = (tag = "a") => Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from(`jpeg-${tag}-padding`)]);

function createFakeBucket() {
  const files = new Map();
  let generation = 0;
  let clock = () => T0;
  const bucket = {
    name: "test-bucket",
    files,
    /** How many times each path was deleted. */
    deletes: [],
    useClock(fn) {
      clock = fn;
    },
    put(path, bytes, {timeCreated} = {}) {
      generation += 1;
      const buffer = Buffer.from(bytes);
      files.set(path, {
        bytes: buffer,
        metadata: {
          contentType: "image/jpeg",
          size: String(buffer.length),
          generation: String(generation),
          timeCreated: new Date(timeCreated ?? clock()).toISOString(),
        },
      });
    },
    has: (path) => files.has(path),
    file(path) {
      return {
        name: path,
        async exists() {
          return [files.has(path)];
        },
        async download() {
          if (!files.has(path)) throw Object.assign(new Error("not found"), {code: 404});
          return [files.get(path).bytes];
        },
        async getMetadata() {
          if (!files.has(path)) throw Object.assign(new Error("not found"), {code: 404});
          return [files.get(path).metadata];
        },
        async delete() {
          bucket.deletes.push(path);
          files.delete(path);
        },
        async copy(dest) {
          if (!files.has(path)) throw Object.assign(new Error("not found"), {code: 404});
          bucket.put(dest.name, files.get(path).bytes);
        },
        async setMetadata(meta) {
          if (files.has(path)) Object.assign(files.get(path).metadata, meta);
        },
        async save(data) {
          bucket.put(path, data);
        },
      };
    },
    /**
     * Honours maxResults and pageToken so pagination is exercised. Like Cloud
     * Storage, a page token is a position in name order — not an offset — so
     * deleting what a page returned does not make the next page skip objects.
     */
    async getFiles({prefix, maxResults, pageToken}) {
      const names = [...files.keys()]
        .filter((k) => k.startsWith(prefix) && (!pageToken || k > pageToken))
        .sort();
      const page = names.slice(0, maxResults ?? names.length);
      const more = page.length < names.length;
      return [page.map((name) => ({name})), more ? {pageToken: page[page.length - 1]} : null];
    },
  };
  return bucket;
}

/**
 * A provider whose answers are set by the test. Records every call so a test
 * can assert the provider was — or was not — paid.
 */
function createScriptedProvider() {
  const provider = {
    id: "test-provider",
    calls: [],
    liveness: "live",
    match: "match",
    /** Thrown once per entry, in order, from the named call. */
    failures: {liveness: [], match: []},
    /** Awaited inside checkLiveness; lets a test hold a verification open. */
    gate: null,
    async checkLiveness(selfie) {
      provider.calls.push({call: "liveness", selfie});
      if (provider.gate) await provider.gate;
      const failure = provider.failures.liveness.shift();
      if (failure) throw failure;
      return provider.liveness;
    },
    async matchFaces(selfie, reference) {
      provider.calls.push({call: "match", selfie, reference});
      const failure = provider.failures.match.shift();
      if (failure) throw failure;
      return provider.match;
    },
  };
  return provider;
}

const outage = () => new FaceProviderError("test-outage", true);
const refusal = () => new FaceProviderError("test-refusal", false, true);

function publishedPath(uid, imageId) {
  return `users/${uid}/profile/photos/${imageId}.jpg`;
}

/**
 * A world with one member. `photos` is a list of image ids, each approved and
 * published unless overridden through `ledger`.
 */
function createFaceAnchorWorld({uid = "member-1", photos = ["p1", "p2", "p3"], ledger = {}, profile = {}} = {}) {
  const seed = {};
  seed[`users/${uid}`] = {uid, accountStatus: "active", isBanned: false, isSuspended: false};
  const photoRecords = photos.map((id, index) => ({
    id,
    order: index,
    isPrimary: index === 0,
    moderationStatus: ledger[id]?.status ?? "approved",
    storagePath: publishedPath(uid, id),
    downloadUrl: `https://cdn.test/${id}.jpg`,
  }));
  seed[`profiles/${uid}`] = {uid, displayName: "Member", photos: photoRecords, ...profile};
  for (const id of photos) {
    seed[`users/${uid}/photoModeration/${id}`] = {
      imageId: id,
      status: "approved",
      storagePath: publishedPath(uid, id),
      downloadUrl: `https://cdn.test/${id}.jpg`,
      moderatedBy: "system",
      ...(ledger[id] ?? {}),
    };
  }
  const db = createFakeFirestore(seed);
  const bucket = createFakeBucket();
  for (const id of photos) {
    bucket.put(publishedPath(uid, id), JPEG(`photo-${id}`));
  }
  const provider = createScriptedProvider();
  let now = T0;
  bucket.useClock(() => now);
  let attemptSeq = 0;
  const world = {
    uid,
    db,
    bucket,
    provider,
    /** Set to null to simulate "no provider configured". */
    activeProvider: provider,
    moderated: [],
    cap: 1000,
    deps: {
      db,
      bucket: () => bucket,
      provider: () => world.activeProvider,
      now: () => now,
      newAttemptId: () => {
        attemptSeq += 1;
        return `attempt-${attemptSeq}`;
      },
      // Identity: the provider double does not look at pixels. A test that
      // needs undecodable bytes sets world.normalize.
      normalizeImage: async (bytes) => (world.normalize ? world.normalize(bytes) : bytes),
      dailyGlobalCap: () => world.cap,
      moderatePending: async (memberUid, imageId) => {
        world.moderated.push(imageId);
        if (world.onModeratePending) await world.onModeratePending(memberUid, imageId);
      },
    },
    advance(ms) {
      now += ms;
    },
    get now() {
      return now;
    },
    state: () => db.read(`users/${uid}/faceAnchor/state`),
    ledger: (id) => db.read(`users/${uid}/photoModeration/${id}`),
    profile: () => db.read(`profiles/${uid}`),
    selfiePath: (attemptId) => `face-anchor/pending/${uid}/${attemptId}`,
    /** The member "captures" a selfie: an object appears where start said. */
    uploadSelfie(attemptId, bytes = JPEG("selfie")) {
      bucket.put(world.selfiePath(attemptId), bytes);
    },
  };
  return world;
}

/** Asserts a promise rejects with an HttpsError carrying this message. */
async function rejectsWith(promise, message) {
  let error;
  try {
    await promise;
  } catch (e) {
    error = e;
  }
  if (!error) {
    throw new Error(`expected rejection with ${message}, but it resolved`);
  }
  if (error.message !== message) {
    throw new Error(`expected ${message}, got ${error.message}`);
  }
  return error;
}

function verdict(uid, imageId, {verifiedAtMs = T0, storagePath} = {}) {
  return {
    status: "verified",
    verifiedAt: Timestamp.fromMillis(verifiedAtMs),
    provider: "test-provider",
    attemptId: `seed-${imageId}`,
    storagePath: storagePath ?? publishedPath(uid, imageId),
  };
}

module.exports = {
  T0,
  JPEG,
  CONSENT: FACE_ANCHOR_CONSENT_VERSION,
  createFakeBucket,
  createScriptedProvider,
  createFaceAnchorWorld,
  publishedPath,
  rejectsWith,
  verdict,
  outage,
  refusal,
};
