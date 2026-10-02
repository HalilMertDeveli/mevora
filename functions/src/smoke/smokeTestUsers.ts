import {createHash, randomBytes, timingSafeEqual} from "node:crypto";
import {getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {logger} from "firebase-functions";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const smokeTestSecret = defineSecret("SMOKE_TEST_SECRET");
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
  secrets: [smokeTestSecret],
};

export const SMOKE_USER_A_EMAIL = "smoke-a@mevora.test";
export const SMOKE_USER_B_EMAIL = "smoke-b@mevora.test";

export function isSmokeTestUser(data: Record<string, unknown> | undefined): boolean {
  return data?.isSmokeTestUser === true;
}

function sha256(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}

/**
 * Whether `provided` is the configured smoke secret.
 *
 * Both sides are hashed first, so timingSafeEqual always sees two buffers of
 * the same length and the time taken says nothing about how much of the
 * secret a guess got right, or how long the secret is. An empty value on
 * either side never matches: an unset secret must not be satisfiable by
 * sending nothing.
 */
export function smokeSecretMatches(provided: unknown, expected: string): boolean {
  if (typeof provided !== "string" || provided.length === 0 || expected.length === 0) {
    return false;
  }
  return timingSafeEqual(sha256(provided), sha256(expected));
}

function requireSmokeSecret(provided: unknown): void {
  const expected = smokeTestSecret.value();
  if (!expected) {
    // No default and no fallback: without a configured secret the smoke
    // surface is closed to everyone, whatever they send.
    logger.warn("Smoke callable refused: SMOKE_TEST_SECRET is not configured");
    throw new HttpsError("failed-precondition", "smoke-secret-not-configured");
  }
  if (!smokeSecretMatches(provided, expected)) {
    throw new HttpsError("permission-denied", "smoke-secret-invalid");
  }
}

/**
 * A fresh password for one smoke user: 32 bytes from the system CSPRNG.
 *
 * It is not derived from anything in this repository, from the user or from
 * the smoke secret, so reading the source gives no way to sign in. The fixed
 * suffix carries no secrecy; it only keeps the value valid if the project
 * turns on a character-class password policy.
 */
function generateSmokePassword(): string {
  return `${randomBytes(32).toString("base64url")}aA1!`;
}

async function deleteAuthUserIfExists(uid: string): Promise<void> {
  try {
    await getAuth().deleteUser(uid);
  } catch (error) {
    logger.info("Smoke cleanup auth user missing", {uid, error});
  }
}

async function deleteSmokeUserData(uid: string): Promise<void> {
  const batchDeletes = [
    db.doc(`users/${uid}`),
    db.doc(`profiles/${uid}`),
    db.doc(`userPreferences/${uid}`),
    db.doc(`userSettings/${uid}`),
    db.doc(`userPrivacy/${uid}`),
    db.doc(`userLocation/${uid}`),
  ];
  await Promise.all(batchDeletes.map((ref) => ref.delete().catch(() => undefined)));
  try {
    await getStorage().bucket().deleteFiles({prefix: `users/${uid}/`});
  } catch (error) {
    logger.warn("Smoke storage cleanup skipped", {uid, error});
  }
}

/**
 * Creates (or resets) the two smoke users and hands their credentials to the
 * caller who presented the smoke secret.
 *
 * Every call issues new passwords, for existing users too, and ends their
 * open sessions: a password from an earlier run, or the template an earlier
 * deploy used, stops working the moment this runs. The passwords exist only
 * in Firebase Auth and in this response; they are never stored or logged.
 */
export const prepareSmokeTestUsers = onCall(callableOptions, async (request) => {
  requireSmokeSecret(request.data?.secret);
  const auth = getAuth();

  const pair = [
    {email: SMOKE_USER_A_EMAIL, label: "A"},
    {email: SMOKE_USER_B_EMAIL, label: "B"},
  ] as const;

  const result: Record<string, string> = {};
  const passwords: Record<string, string> = {};
  for (const item of pair) {
    const password = generateSmokePassword();
    let user = await auth.getUserByEmail(item.email).catch(() => null);
    if (user) {
      await auth.updateUser(user.uid, {emailVerified: true, password});
      await auth.revokeRefreshTokens(user.uid);
    } else {
      user = await auth.createUser({
        email: item.email,
        emailVerified: true,
        password,
        displayName: `Smoke User ${item.label}`,
      });
    }
    passwords[item.label] = password;
    await deleteSmokeUserData(user.uid);
    await db.doc(`users/${user.uid}`).set(
      {
        uid: user.uid,
        email: item.email,
        accountStatus: "active",
        isActive: true,
        isBanned: false,
        isSmokeTestUser: true,
        profileCompleted: false,
        onboardingCompleted: false,
        lastActiveAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    result[item.label] = user.uid;
  }

  return {
    ok: true,
    smokeUserA: result.A,
    smokeUserB: result.B,
    emails: {
      a: SMOKE_USER_A_EMAIL,
      b: SMOKE_USER_B_EMAIL,
    },
    passwords: {
      a: passwords.A,
      b: passwords.B,
    },
  };
});

export const cleanupSmokeTestUsers = onCall(callableOptions, async (request) => {
  requireSmokeSecret(request.data?.secret);
  const auth = getAuth();
  const emails = [SMOKE_USER_A_EMAIL, SMOKE_USER_B_EMAIL];
  const deleted: string[] = [];
  for (const email of emails) {
    const user = await auth.getUserByEmail(email).catch(() => null);
    if (!user) {
      continue;
    }
    await deleteSmokeUserData(user.uid);
    await deleteAuthUserIfExists(user.uid);
    deleted.push(user.uid);
  }
  return {ok: true, deleted};
});

export function passesSmokeDiscoveryIsolation(
  viewerAccount: Record<string, unknown> | undefined,
  candidateAccount: Record<string, unknown> | undefined,
): boolean {
  const viewerSmoke = isSmokeTestUser(viewerAccount);
  const candidateSmoke = isSmokeTestUser(candidateAccount);
  if (!viewerSmoke && !candidateSmoke) {
    return true;
  }
  return viewerSmoke && candidateSmoke;
}
