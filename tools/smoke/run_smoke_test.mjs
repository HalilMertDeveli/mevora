import {initializeApp, applicationDefault, cert} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {SmokeReporter, STEP_NAMES} from "./lib/report.mjs";
import {
  cleanupSmokeUsers,
  completeOnboardingViaAdmin,
  createActiveMatch,
  seedSmokeUser,
  uploadPendingPhoto,
  waitForApprovedPhotos,
} from "./lib/helpers.mjs";

const PROJECT_ID = process.env.SMOKE_FIREBASE_PROJECT ?? "mevora-production";
const EMAIL_A = "smoke-a@mevora.test";
const EMAIL_B = "smoke-b@mevora.test";

function initAdmin() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS || process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    const options = process.env.FIREBASE_SERVICE_ACCOUNT_JSON
      ? {credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)), projectId: PROJECT_ID}
      : {credential: applicationDefault(), projectId: PROJECT_ID};
    initializeApp(options);
    return;
  }
  initializeApp({projectId: PROJECT_ID});
}

async function main() {
  initAdmin();
  const db = getFirestore();
  const auth = getAuth();
  const reporter = new SmokeReporter({
    environment: process.env.SMOKE_USE_EMULATOR === "true" ? "emulator" : "production",
    firebaseProject: PROJECT_ID,
  });

  let uidA = null;
  let uidB = null;
  let matchId = null;

  try {
    await cleanupSmokeUsers(db, auth, [EMAIL_A, EMAIL_B]);

    uidA = await seedSmokeUser(db, auth, EMAIL_A, "A");
    uidB = await seedSmokeUser(db, auth, EMAIL_B, "B");
    reporter.pass(0, `users ${uidA}, ${uidB}`);
    reporter.pass(1, "adult birthDate seeded");
    reporter.pass(2, "profiles + preferences seeded");

    await uploadPendingPhoto(db, uidA, 0);
    reporter.pass(3);
    await uploadPendingPhoto(db, uidA, 1);
    reporter.pass(4);
    await uploadPendingPhoto(db, uidA, 2);
    reporter.pass(5);
    await uploadPendingPhoto(db, uidB, 0);
    await uploadPendingPhoto(db, uidB, 1);
    await uploadPendingPhoto(db, uidB, 2);

    if (process.env.SMOKE_USE_EMULATOR === "true") {
      reporter.block(6, "Start Functions emulator so pending uploads are processed");
    } else {
      try {
        await waitForApprovedPhotos(db, uidA, 3, 90_000);
        await waitForApprovedPhotos(db, uidB, 3, 90_000);
        reporter.pass(6, "6 photos approved by moderation pipeline");
      } catch (error) {
        reporter.fail(6, "approved>=3", "timeout", error.message);
        throw error;
      }
    }

    await completeOnboardingViaAdmin(db, uidA);
    await completeOnboardingViaAdmin(db, uidB);

    const discoverableB = await db.doc(`profiles/${uidB}`).get();
    if (discoverableB.data()?.isDiscoverable === true) {
      reporter.pass(7, `User B discoverable (${uidB})`);
    } else {
      reporter.fail(7, "isDiscoverable=true", String(discoverableB.data()?.isDiscoverable), "profile not discoverable");
    }

    await db.collection("likes").doc(`${uidA}_${uidB}`).set({
      fromUserId: uidA,
      toUserId: uidB,
      action: "like",
      createdAt: new Date(),
    });
    reporter.pass(8, "like A→B");

    matchId = await createActiveMatch(db, uidA, uidB);
    reporter.pass(9, matchId);

    await db.collection(`matches/${matchId}/messages`).add({
      senderId: uidA,
      receiverId: uidB,
      text: "smoke-test-message",
      type: "text",
      createdAt: new Date(),
      isRead: false,
      deleted: false,
      status: "sent",
    });
    reporter.pass(10, "message written");

    await db.doc(`blocks/${uidA}_${uidB}`).set({
      blockerId: uidA,
      blockedUserId: uidB,
      createdAt: new Date(),
    });
    reporter.pass(11);

    await db.collection("reports").add({
      reporterId: uidA,
      reportedUserId: uidB,
      reason: "other",
      description: "smoke test report",
      status: "open",
      createdAt: new Date(),
    });
    reporter.pass(12);

    await cleanupSmokeUsers(db, auth, [EMAIL_A, EMAIL_B]);
    reporter.pass(13, "users removed");
    reporter.cleanupStatus = "PASS";
  } catch (error) {
    if (reporter.failedStep == null) {
      reporter.fail(0, "smoke run complete", "exception", error.message);
    }
    reporter.cleanupStatus = "FAIL";
    try {
      await cleanupSmokeUsers(db, auth, [EMAIL_A, EMAIL_B]);
      reporter.cleanupStatus = "PASS";
    } catch (cleanupError) {
      reporter.cleanupStatus = `FAIL (${cleanupError.message})`;
    }
  }

  const output = reporter.render();
  console.log(output);
  if (reporter.failedStep) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
