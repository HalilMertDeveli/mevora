/**
 * Points the Firebase Admin SDK entry points at in-memory doubles so a test
 * can load a compiled callable module and invoke it with `.run(request)`.
 *
 * Must be called BEFORE the module under test is required: the callables read
 * `getFirestore()` / `getAuth()` once, at module load.
 *
 * Only the members the humor and deletion paths touch are provided. Nothing
 * here can reach a network or a real project.
 */
function installFirebaseAdminStubs({db}) {
  const auth = {
    users: new Map(),
    deleted: [],
    addUser(uid, {admin = false} = {}) {
      this.users.set(uid, {uid, customClaims: admin ? {admin: true} : {}});
    },
  };
  const notFound = (uid) => {
    const error = new Error(`no user record for ${uid}`);
    error.code = "auth/user-not-found";
    return error;
  };
  const authClient = {
    async getUser(uid) {
      if (!auth.users.has(uid)) throw notFound(uid);
      return auth.users.get(uid);
    },
    async deleteUser(uid) {
      if (!auth.users.has(uid)) throw notFound(uid);
      auth.users.delete(uid);
      auth.deleted.push(uid);
    },
  };
  const bucket = {
    async deleteFiles() {},
    async getFiles() {
      return [[]];
    },
  };

  require("firebase-admin/firestore").getFirestore = () => db;
  require("firebase-admin/auth").getAuth = () => authClient;
  require("firebase-admin/storage").getStorage = () => ({bucket: () => bucket});
  require("firebase-admin/functions").getFunctions = () => ({
    taskQueue: () => ({enqueue: async () => {}}),
  });
  return {auth};
}

/** Invokes a v2 callable's handler and resolves to its result or HttpsError. */
async function callAs(callable, uid, data = {}) {
  return callable.run({
    data,
    auth: uid ? {uid, token: {}} : undefined,
    rawRequest: {},
  });
}

module.exports = {installFirebaseAdminStubs, callAs};
