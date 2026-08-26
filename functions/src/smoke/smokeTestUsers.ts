import {getApps, initializeApp} from "firebase-admin/app";
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

function requireSmokeSecret(provided: unknown): void {
  const expected = smokeTestSecret.value();
  if (!expected || String(provided ?? "") !== expected) {
    throw new HttpsError("permission-denied", "smoke-secret-invalid");
  }
}

async function deleteAuthUserIfExists(uid: string): Promise<void> {
  try {
    const {getAuth} = await import("firebase-admin/auth");
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

export const prepareSmokeTestUsers = onCall(callableOptions, async (request) => {
  requireSmokeSecret(request.data?.secret);
  const {getAuth} = await import("firebase-admin/auth");
  const auth = getAuth();

  const pair = [
    {email: SMOKE_USER_A_EMAIL, label: "A"},
    {email: SMOKE_USER_B_EMAIL, label: "B"},
  ] as const;

  const result: Record<string, string> = {};
  for (const item of pair) {
    let user = await auth.getUserByEmail(item.email).catch(() => null);
    if (!user) {
      user = await auth.createUser({
        email: item.email,
        emailVerified: true,
        password: `Smoke!${item.label}9Mevora`,
        displayName: `Smoke User ${item.label}`,
      });
    }
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
  };
});

export const cleanupSmokeTestUsers = onCall(callableOptions, async (request) => {
  requireSmokeSecret(request.data?.secret);
  const {getAuth} = await import("firebase-admin/auth");
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
