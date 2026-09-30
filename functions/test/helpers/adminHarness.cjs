/**
 * Shared fixtures for the admin / Trust & Safety suites.
 *
 * Drives the exact production path — runAdminCommand(spec, request, deps,
 * env) — against the in-memory Firestore double, an in-memory Auth port and
 * an in-memory bucket. Nothing here can reach a real project.
 *
 * Not a test file (no `.test.cjs` suffix), so testSuiteCoverage ignores it.
 */
const {createFakeFirestore} = require("./fakeFirestore.cjs");
const {runAdminCommand} = require("../../lib/admin/command.js");

const BFF_SECRET = "test-bff-secret-value";
const T0 = Date.parse("2026-09-29T10:00:00Z");

function createFakeAuth() {
  const users = new Map();
  const calls = [];
  const notFound = () => Object.assign(new Error("user-not-found"), {code: "auth/user-not-found"});
  return {
    users,
    calls,
    addUser(uid, props = {}) {
      users.set(uid, {
        uid,
        email: props.email,
        phoneNumber: props.phoneNumber,
        disabled: props.disabled === true,
        customClaims: props.customClaims ?? {},
        metadata: {creationTime: "2026-01-01T00:00:00Z", lastSignInTime: "2026-09-28T00:00:00Z"},
        providerData: [{providerId: "phone"}],
        multiFactor: {enrolledFactors: []},
      });
    },
    async getUser(uid) {
      if (!users.has(uid)) throw notFound();
      return users.get(uid);
    },
    async getUserByEmail(email) {
      for (const u of users.values()) if (u.email === email) return u;
      throw notFound();
    },
    async createUser(props) {
      const uid = `auth-created-${users.size + 1}`;
      // The password is recorded only as "was one set", never its value.
      calls.push(["createUser", uid, {email: props.email, emailVerified: props.emailVerified, passwordSet: typeof props.password === "string" && props.password.length >= 32}]);
      users.set(uid, {
        uid,
        email: props.email,
        displayName: props.displayName,
        disabled: props.disabled === true,
        emailVerified: props.emailVerified === true,
        customClaims: {},
        metadata: {creationTime: new Date(T0).toUTCString(), lastSignInTime: null},
        providerData: [{providerId: "password"}],
        multiFactor: {enrolledFactors: []},
      });
      return {uid};
    },
    async getUserByPhoneNumber(phone) {
      for (const u of users.values()) if (u.phoneNumber === phone) return u;
      throw notFound();
    },
    async updateUser(uid, props) {
      if (!users.has(uid)) throw notFound();
      calls.push(["updateUser", uid, props]);
      Object.assign(users.get(uid), props);
    },
    async revokeRefreshTokens(uid) {
      calls.push(["revokeRefreshTokens", uid]);
    },
    async setCustomUserClaims(uid, claims) {
      if (!users.has(uid)) throw notFound();
      calls.push(["setCustomUserClaims", uid, claims]);
      users.get(uid).customClaims = claims ?? {};
    },
  };
}

function createFakeBucket() {
  const files = new Map();
  const bucket = {
    name: "test-bucket",
    files,
    put(path, bytes, contentType = "image/jpeg") {
      files.set(path, {bytes: Buffer.from(bytes), metadata: {contentType, size: String(bytes.length), timeCreated: new Date(T0).toISOString()}});
    },
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
        async copy(dest) {
          if (!files.has(path)) throw Object.assign(new Error("not found"), {code: 404});
          const source = files.get(path);
          files.set(dest.name, {bytes: source.bytes, metadata: {...source.metadata}});
        },
        async delete() {
          files.delete(path);
        },
        async setMetadata(meta) {
          if (files.has(path)) files.get(path).metadata = {...files.get(path).metadata, ...meta};
        },
      };
    },
    async getFiles({prefix}) {
      return [[...files.keys()].filter((k) => k.startsWith(prefix)).map((name) => ({name}))];
    },
  };
  return bucket;
}

function createAdminWorld(seed = {}) {
  const db = createFakeFirestore(seed);
  const auth = createFakeAuth();
  const bucket = createFakeBucket();
  let now = T0;
  const deps = {db, auth, bucket: () => bucket, now: () => now};
  const env = {bffSecret: BFF_SECRET, allowMissingMfa: false};

  async function addStaff(uid, role, {status = "active", sessionsValidAfter = null, isOwner = false} = {}) {
    auth.addUser(uid, {email: `${uid}@mevora.test`, customClaims: {admin: true, adminRole: role}});
    await db.doc(`adminStaff/${uid}`).set({
      uid,
      role,
      status,
      displayName: uid,
      email: `${uid}@mevora.test`,
      permissionsVersion: 1,
      ...(sessionsValidAfter ? {sessionsValidAfter} : {}),
      ...(isOwner ? {isOwner: true} : {}),
      createdAt: new Date(T0 - 1000),
    });
  }

  async function addMember(uid, {account = {}, profile = {}} = {}) {
    auth.addUser(uid, {email: `${uid}@example.com`, phoneNumber: account.phoneNumber});
    await db.doc(`users/${uid}`).set({
      uid,
      id: uid,
      isBanned: false,
      isSuspended: false,
      isVerified: false,
      accountStatus: "active",
      email: `${uid}@example.com`,
      createdAt: new Date(T0 - 86400000),
      ...account,
    });
    await db.doc(`profiles/${uid}`).set({
      uid,
      displayName: profile.displayName ?? uid,
      photos: [],
      ...profile,
    });
  }

  function request(uid, data = {}, opts = {}) {
    const token = {
      admin: opts.admin ?? true,
      auth_time: Math.floor((opts.authTimeMs ?? now) / 1000),
      ...(opts.mfa === false ? {} : {firebase: {sign_in_second_factor: "totp"}}),
      ...(opts.token ?? {}),
    };
    return {
      data,
      auth: uid ? {uid, token} : undefined,
      rawRequest: {headers: opts.bff === false ? {} : {"x-mevora-admin-bff": opts.bffValue ?? BFF_SECRET}},
    };
  }

  /** Runs a command as `uid`; resolves to the result or rejects with the HttpsError. */
  function run(spec, uid, data = {}, opts = {}) {
    return runAdminCommand(spec, request(uid, data, opts), deps, {...env, ...(opts.env ?? {})});
  }

  return {
    db,
    auth,
    bucket,
    deps,
    env,
    addStaff,
    addMember,
    request,
    run,
    advance(ms) {
      now += ms;
    },
    get now() {
      return now;
    },
  };
}

/** Asserts a promise rejects with the given admin domain code. */
async function rejectsWith(promise, code) {
  let error;
  try {
    await promise;
  } catch (e) {
    error = e;
  }
  if (!error) {
    throw new Error(`expected rejection with ${code}, but it resolved`);
  }
  const actual = error.details?.code ?? error.code ?? error.message;
  if (actual !== code) {
    throw new Error(`expected ${code}, got ${actual} (${error.message})`);
  }
  return error;
}

let keySeq = 0;
function key(label = "k") {
  keySeq += 1;
  return `${label}-idem-${keySeq.toString().padStart(4, "0")}`;
}

module.exports = {createAdminWorld, rejectsWith, key, BFF_SECRET, T0};
