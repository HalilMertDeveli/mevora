import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {requireAdmin, enqueueJob} from "./jobs.js";
import {writeAuditLog, maskEmail, maskPhone} from "./audit.js";
import {JobKind, ReviewQueueStatus} from "./types.js";
import {processJobById} from "./runner.js";
import {enqueueCloudTask} from "./tasksEnqueue.js";
import {
  cleanupDeletedAccountStorageRemnants,
  cleanupOrphanChatMedia,
  cleanupStalePendingUploads,
} from "./cleanup.js";
import {verifyAccountDeletion} from "./deletionVerify.js";
import {syncExpiredPremium} from "./premiumSync.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const adminCallable = {enforceAppCheck, region: "europe-west1" as const};

function clampLimit(n: unknown, fallback = 50, max = 100): number {
  const v = Number(n ?? fallback);
  if (!Number.isFinite(v)) {
    return fallback;
  }
  return Math.min(max, Math.max(1, Math.floor(v)));
}

export const adminGetDashboard = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const [
    openReports,
    failedJobs,
    manualJobs,
    openReviews,
  ] = await Promise.all([
    db.collection("reports").where("status", "==", "open").limit(200).get(),
    db.collection("automationJobs").where("status", "==", "failed").limit(100).get(),
    db.collection("automationJobs").where("status", "==", "manual_review").limit(100).get(),
    db.collection("adminReviewQueue").where("status", "==", "open").limit(100).get(),
  ]);

  // Lightweight counters — avoid full collection scans.
  const metrics = {
    openReports: openReports.size,
    failedJobs: failedJobs.size,
    manualReviewJobs: manualJobs.size,
    openReviewQueue: openReviews.size,
    windowHours: 24,
    generatedAt: new Date().toISOString(),
    note: "Counters are capped query sizes; use BigQuery/Analytics for exact volume.",
    since: since.toISOString(),
  };

  await writeAuditLog({
    adminUid,
    action: "dashboard.view",
    result: "success",
    metadata: {metrics},
  });

  return {metrics};
});

export const adminSearchUsers = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const uid = String(request.data?.uid ?? "").trim();
  const limit = clampLimit(request.data?.limit, 20, 50);
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid_required");
  }

  const [userSnap, profileSnap, prefsSnap, subSnap] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`users/${uid}/subscription/current`).get(),
  ]);

  let authRecord: {
    email: string | null;
    phone: string | null;
    disabled: boolean;
    providers: string[];
  } | null = null;
  try {
    const record = await getAuth().getUser(uid);
    authRecord = {
      email: maskEmail(record.email),
      phone: maskPhone(record.phoneNumber),
      disabled: record.disabled,
      providers: record.providerData.map((p) => p.providerId),
    };
  } catch {
    authRecord = null;
  }

  const user = userSnap.data() ?? null;
  const profile = profileSnap.data() ?? null;
  const result = {
    uid,
    auth: authRecord,
    account: user
      ? {
        accountStatus: user.accountStatus ?? null,
        isBanned: user.isBanned === true,
        isSuspended: user.isSuspended === true,
        isVerified: user.isVerified === true,
        phoneVerified: user.phoneVerified === true,
        lastActiveAt: user.lastActiveAt ?? null,
        createdAt: user.createdAt ?? null,
      }
      : null,
    profile: profile
      ? {
        displayName: profile.displayName ?? profile.name ?? null,
        onboardingCompleted: profile.onboardingCompleted === true,
        profileCompleted: profile.profileCompleted === true,
        isDiscoverable: profile.isDiscoverable === true,
        moderationStatus: profile.moderationStatus ?? profile.profileModerationStatus ?? null,
      }
      : null,
    preferences: prefsSnap.exists,
    premium: {
      isPremium: subSnap.data()?.isPremium === true,
      expiresAt: subSnap.data()?.expiresAt ?? null,
    },
  };

  await writeAuditLog({
    adminUid,
    action: "user.search",
    targetUid: uid,
    result: "success",
    metadata: {limit},
  });

  return {user: result};
});

export const adminListReports = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const status = String(request.data?.status ?? "open");
  const limit = clampLimit(request.data?.limit, 50, 100);
  const snap = await db.collection("reports").where("status", "==", status).limit(limit).get();
  const items = snap.docs.map((d) => ({
    id: d.id,
    reporterId: d.data().reporterId ?? null,
    reportedUserId: d.data().reportedUserId ?? null,
    reason: d.data().reason ?? null,
    status: d.data().status ?? null,
    createdAt: d.data().createdAt ?? null,
    // Never return raw message ciphertext; only reporter-supplied description.
    description: d.data().description ?? null,
    hasMessageEvidence: Boolean(d.data().messageId),
  }));
  await writeAuditLog({
    adminUid,
    action: "reports.list",
    result: "success",
    metadata: {status, count: items.length},
  });
  return {items};
});

export const adminResolveReport = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const reportId = String(request.data?.reportId ?? "").trim();
  const decision = String(request.data?.decision ?? "").trim();
  const reason = String(request.data?.reason ?? "").trim();
  if (!reportId || !["dismiss", "warn", "escalate_ban_review"].includes(decision)) {
    throw new HttpsError("invalid-argument", "invalid_decision");
  }
  if (!reason || reason.length < 3) {
    throw new HttpsError("invalid-argument", "reason_required");
  }
  const ref = db.doc(`reports/${reportId}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "report_not_found");
  }
  const newStatus = decision === "dismiss" ? "dismissed" : "resolved";
  await ref.set(
    {
      status: newStatus,
      resolution: decision,
      resolvedBy: adminUid,
      resolvedAt: FieldValue.serverTimestamp(),
      resolutionReason: reason.slice(0, 500),
    },
    {merge: true},
  );
  await db.doc(`adminReviewQueue/${reportId}`).set(
    {
      status: decision === "dismiss" ? ReviewQueueStatus.dismissed : ReviewQueueStatus.resolved,
      resolvedBy: adminUid,
      decision,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  if (decision === "escalate_ban_review") {
    await enqueueJob({
      kind: JobKind.adminManualAction,
      idempotencyKey: `ban_review_${reportId}`,
      payload: {
        action: "account_ban",
        reportId,
        targetUid: snap.data()?.reportedUserId ?? null,
      },
      createdBy: adminUid,
      requiresHumanReview: true,
    });
  }
  await writeAuditLog({
    adminUid,
    action: "reports.resolve",
    targetUid: String(snap.data()?.reportedUserId ?? ""),
    reason,
    result: "success",
    metadata: {reportId, decision},
  });
  return {ok: true, status: newStatus};
});

export const adminListJobs = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const status = String(request.data?.status ?? "failed");
  const limit = clampLimit(request.data?.limit, 50, 100);
  const snap = await db.collection("automationJobs").where("status", "==", status).limit(limit).get();
  const items = snap.docs.map((d) => ({id: d.id, ...d.data()}));
  await writeAuditLog({
    adminUid,
    action: "jobs.list",
    result: "success",
    metadata: {status, count: items.length},
  });
  return {items};
});

export const adminRetryJob = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const jobId = String(request.data?.jobId ?? "").trim();
  if (!jobId) {
    throw new HttpsError("invalid-argument", "jobId_required");
  }
  await db.doc(`automationJobs/${jobId}`).set(
    {
      status: "queued",
      requiresHumanReview: false,
      updatedAt: FieldValue.serverTimestamp(),
      retriedBy: adminUid,
    },
    {merge: true},
  );
  await enqueueCloudTask(jobId);
  const outcome = await processJobById(jobId);
  await writeAuditLog({
    adminUid,
    action: "jobs.retry",
    reason: String(request.data?.reason ?? "manual_retry"),
    result: outcome.status === "succeeded" ? "success" : "failure",
    jobId,
    metadata: outcome,
  });
  return outcome;
});

export const adminRunCleanup = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const kind = String(request.data?.kind ?? "").trim();
  const dryRun = request.data?.dryRun !== false; // default true
  const limit = clampLimit(request.data?.limit, 50, 200);
  const reason = String(request.data?.reason ?? "admin_cleanup").slice(0, 500);
  if (!dryRun && !reason) {
    throw new HttpsError("invalid-argument", "reason_required_for_delete");
  }
  const opts = {
    dryRun,
    limit,
    requireAdminApproval: !dryRun,
    adminUid,
    reason,
  };
  let result;
  switch (kind) {
  case "orphan_chat":
    result = await cleanupOrphanChatMedia(opts);
    break;
  case "stale_pending":
    result = await cleanupStalePendingUploads(opts);
    break;
  case "deleted_remnant":
    result = await cleanupDeletedAccountStorageRemnants(opts);
    break;
  case "premium_sync":
    result = await syncExpiredPremium(opts);
    break;
  default:
    throw new HttpsError("invalid-argument", "unknown_cleanup_kind");
  }
  await writeAuditLog({
    adminUid,
    action: "cleanup.run",
    reason,
    result: dryRun ? "dry_run" : "success",
    metadata: {kind, ...result, candidates: result.candidates.slice(0, 20)},
  });
  return result;
});

export const adminVerifyDeletion = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const uid = String(request.data?.uid ?? "").trim();
  if (!uid) {
    throw new HttpsError("invalid-argument", "uid_required");
  }
  const result = await verifyAccountDeletion(uid);
  await writeAuditLog({
    adminUid,
    action: "deletion.verify",
    targetUid: uid,
    result: result.complete ? "success" : "failure",
    metadata: result,
  });
  return result;
});

/**
 * Suspend / restore — human-approved only. Never permanent Auth delete here.
 */
export const adminSetUserSuspension = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const targetUid = String(request.data?.uid ?? "").trim();
  const suspend = request.data?.suspend === true;
  const reason = String(request.data?.reason ?? "").trim();
  if (!targetUid || targetUid === adminUid) {
    throw new HttpsError("invalid-argument", "invalid_target");
  }
  if (reason.length < 5) {
    throw new HttpsError("invalid-argument", "reason_required");
  }
  // Permanent ban uses adminExecutePermanentBan (explicit confirmPhrase).
  if (request.data?.permanentDelete === true || request.data?.ban === true) {
    throw new HttpsError(
      "failed-precondition",
      "use_adminExecutePermanentBan",
    );
  }

  await db.doc(`users/${targetUid}`).set(
    {
      isSuspended: suspend,
      accountStatus: suspend ? "suspended" : "active",
      suspensionReason: suspend ? reason : FieldValue.delete(),
      suspensionUpdatedAt: FieldValue.serverTimestamp(),
      suspensionUpdatedBy: adminUid,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  if (suspend) {
    await db.doc(`profiles/${targetUid}`).set(
      {isDiscoverable: false, updatedAt: FieldValue.serverTimestamp()},
      {merge: true},
    );
  }

  await writeAuditLog({
    adminUid,
    action: suspend ? "user.suspend" : "user.restore",
    targetUid,
    reason,
    result: "success",
  });
  return {ok: true, suspended: suspend};
});

export const adminListAuditLogs = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const limit = clampLimit(request.data?.limit, 50, 100);
  const targetUid = String(request.data?.targetUid ?? "").trim();
  let query = db.collection("auditLogs").orderBy("timestamp", "desc").limit(limit);
  if (targetUid) {
    query = db
      .collection("auditLogs")
      .where("targetUid", "==", targetUid)
      .orderBy("timestamp", "desc")
      .limit(limit);
  }
  const snap = await query.get();
  await writeAuditLog({
    adminUid,
    action: "audit.list",
    result: "success",
    metadata: {count: snap.size, targetUid: targetUid || null},
  });
  return {
    items: snap.docs.map((d) => ({id: d.id, ...d.data()})),
  };
});

export const adminListReviewQueue = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const limit = clampLimit(request.data?.limit, 50, 100);
  const snap = await db
    .collection("adminReviewQueue")
    .where("status", "==", ReviewQueueStatus.open)
    .limit(limit)
    .get();
  await writeAuditLog({
    adminUid,
    action: "review_queue.list",
    result: "success",
    metadata: {count: snap.size},
  });
  return {items: snap.docs.map((d) => ({id: d.id, ...d.data()}))};
});

/**
 * Grant/revoke admin claim — only callable by an existing admin.
 * First admin must be bootstrapped via scripts/setAdminClaim.mjs offline.
 */
export const adminSetAdminClaim = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const targetUid = String(request.data?.uid ?? "").trim();
  const grant = request.data?.grant === true;
  const reason = String(request.data?.reason ?? "").trim();
  if (!targetUid || reason.length < 5) {
    throw new HttpsError("invalid-argument", "uid_and_reason_required");
  }
  const user = await getAuth().getUser(targetUid);
  const claims = {...(user.customClaims ?? {})};
  if (grant) {
    claims.admin = true;
  } else {
    delete claims.admin;
  }
  await getAuth().setCustomUserClaims(targetUid, claims);
  await writeAuditLog({
    adminUid,
    action: grant ? "admin.grant" : "admin.revoke",
    targetUid,
    reason,
    result: "success",
  });
  return {ok: true, admin: grant};
});

/**
 * Permanent ban — human-approved only.
 * Requires confirmPhrase === "BAN" and a reason. Disables Auth + sets isBanned.
 * Does NOT delete the Auth user or wipe data (use user self-delete or separate legal process).
 */
export const adminExecutePermanentBan = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const targetUid = String(request.data?.uid ?? "").trim();
  const reason = String(request.data?.reason ?? "").trim();
  const confirmPhrase = String(request.data?.confirmPhrase ?? "").trim();
  if (!targetUid || targetUid === adminUid) {
    throw new HttpsError("invalid-argument", "invalid_target");
  }
  if (reason.length < 8) {
    throw new HttpsError("invalid-argument", "reason_required");
  }
  if (confirmPhrase !== "BAN") {
    throw new HttpsError("failed-precondition", "confirm_phrase_BAN_required");
  }

  await db.doc(`users/${targetUid}`).set(
    {
      isBanned: true,
      isSuspended: true,
      accountStatus: "banned",
      banReason: reason.slice(0, 500),
      bannedAt: FieldValue.serverTimestamp(),
      bannedBy: adminUid,
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await db.doc(`profiles/${targetUid}`).set(
    {
      isDiscoverable: false,
      profileModerationStatus: "suspended",
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );

  try {
    await getAuth().updateUser(targetUid, {disabled: true});
  } catch (error) {
    await writeAuditLog({
      adminUid,
      action: "user.ban",
      targetUid,
      reason,
      result: "failure",
      metadata: {authDisableError: String(error).slice(0, 200)},
    });
    throw new HttpsError("internal", "auth_disable_failed");
  }

  await writeAuditLog({
    adminUid,
    action: "user.ban",
    targetUid,
    reason,
    result: "success",
    metadata: {authDisabled: true},
  });
  return {ok: true, banned: true};
});

/** List profiles with photos awaiting manual review. */
export const adminListPhotoReviews = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const limit = clampLimit(request.data?.limit, 30, 50);
  const snap = await db
    .collection("profiles")
    .where("profileModerationStatus", "==", "manual_review")
    .limit(limit)
    .get();
  const items = snap.docs.map((d) => {
    const data = d.data();
    const photos = Array.isArray(data.photos) ? data.photos : [];
    const pending = photos
      .filter((p: Record<string, unknown>) => String(p.moderationStatus ?? "") === "manual_review")
      .map((p: Record<string, unknown>) => ({
        imageId: p.imageId ?? p.id ?? null,
        downloadUrl: p.downloadUrl ?? null,
        moderationReason: p.moderationReason ?? null,
      }));
    return {
      uid: d.id,
      displayName: data.displayName ?? data.name ?? null,
      pendingPhotos: pending,
      updatedAt: data.updatedAt ?? null,
    };
  });
  await writeAuditLog({
    adminUid,
    action: "photo_reviews.list",
    result: "success",
    metadata: {count: items.length},
  });
  return {items};
});

/**
 * Resolve a photo manual review. Does not read chat media.
 * decision: approve | reject
 */
export const adminResolvePhotoReview = onCall(adminCallable, async (request) => {
  const adminUid = requireAdmin(request);
  const targetUid = String(request.data?.uid ?? "").trim();
  const imageId = String(request.data?.imageId ?? "").trim();
  const decision = String(request.data?.decision ?? "").trim();
  const reason = String(request.data?.reason ?? "").trim();
  if (!targetUid || !imageId || !["approve", "reject"].includes(decision)) {
    throw new HttpsError("invalid-argument", "uid_imageId_decision_required");
  }
  if (reason.length < 3) {
    throw new HttpsError("invalid-argument", "reason_required");
  }
  const profileRef = db.doc(`profiles/${targetUid}`);
  const snap = await profileRef.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "profile_not_found");
  }
  const data = snap.data() ?? {};
  const photos = Array.isArray(data.photos) ? [...data.photos] : [];
  let found = false;
  const nextPhotos = photos.map((p: Record<string, unknown>) => {
    const id = String(p.imageId ?? p.id ?? "");
    if (id !== imageId) {
      return p;
    }
    found = true;
    return {
      ...p,
      moderationStatus: decision === "approve" ? "approved" : "rejected",
      moderationReason: reason.slice(0, 300),
      reviewedBy: adminUid,
      reviewedAt: new Date().toISOString(),
    };
  });
  if (!found) {
    throw new HttpsError("not-found", "photo_not_found");
  }
  const stillPending = nextPhotos.some(
    (p: Record<string, unknown>) => String(p.moderationStatus ?? "") === "manual_review",
  );
  await profileRef.set(
    {
      photos: nextPhotos,
      profileModerationStatus: stillPending ? "manual_review" : "approved",
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  await writeAuditLog({
    adminUid,
    action: "photo_reviews.resolve",
    targetUid,
    reason,
    result: "success",
    metadata: {imageId, decision},
  });
  return {ok: true, decision, stillPending};
});
