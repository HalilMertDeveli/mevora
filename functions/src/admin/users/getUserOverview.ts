import type {DocumentData, Query} from "firebase-admin/firestore";
import {approvedPhotos, effectiveAccountStatus} from "../../profileSafety.js";
import {ACTION_COLLECTION} from "../actions/actionTypes.js";
import {recordAuditEvent} from "../audit/auditService.js";
import {STAFF_COLLECTION, parseStaffRecord, requirePermission, type AdminActor} from "../auth/adminAuthorization.js";
import {ACTIVE_CASE_STATUSES, CASE_COLLECTION} from "../cases/caseTypes.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {iso, toMillis} from "../validation.js";
import {maskEmail, maskPhone} from "./userCards.js";

/**
 * The user operations screen, aggregated server-side in one call.
 *
 * Every section is bounded (small limits, count aggregations) and every
 * section is a projection: raw documents never cross to the admin web.
 * Contact identifiers are masked unless the caller holds user.read_sensitive
 * AND asks for them with a justification — and that reveal is audited.
 *
 * Never included: message content or ciphertext, E2EE keys, exact location,
 * identity documents, purchase tokens / order ids, Spotify tokens.
 */

export interface OverviewInput {
  uid: string;
  includeSensitive: boolean;
  justification: string | null;
}

function actionRow(id: string, data: DocumentData) {
  return {
    actionId: id,
    type: data.type ?? null,
    reasonCode: data.reasonCode ?? null,
    actorAdminId: data.actorAdminId ?? null,
    actorRole: data.actorRole ?? null,
    caseId: data.caseId ?? null,
    createdAt: iso(data.createdAt ?? data.effectiveAt),
    expiresAt: iso(data.expiresAt),
    overturnedByActionId: data.overturnedByActionId ?? null,
    appealId: data.appealId ?? null,
    authSync: data.authSync?.status ?? null,
  };
}

async function safeCount(query: Query): Promise<number | null> {
  try {
    const snap = await query.count().get();
    return snap.data().count;
  } catch {
    return null;
  }
}

export async function getUserOverview(deps: AdminDeps, actor: AdminActor, input: OverviewInput, requestId: string) {
  const {db} = deps;
  const nowMs = deps.now();
  if (input.includeSensitive) {
    requirePermission(actor, "user.read_sensitive");
    if (!input.justification) {
      throw new AdminError("invalid_argument", "justification");
    }
  }

  const uid = input.uid;
  const [account, profile, verification, subscription, staff] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`users/${uid}/verification/identity`).get(),
    db.doc(`users/${uid}/subscription/current`).get(),
    db.doc(`${STAFF_COLLECTION}/${uid}`).get(),
  ]);
  if (!account.exists && !profile.exists) {
    throw new AdminError("not_found", "user");
  }

  let authRecord: Awaited<ReturnType<AdminDeps["auth"]["getUser"]>> | null = null;
  try {
    authRecord = await deps.auth.getUser(uid);
  } catch {
    authRecord = null;
  }

  const reports = db.collection("reports");
  const [
    reportsReceivedCount,
    reportsSubmittedCount,
    recentReports,
    openCases,
    actions,
    openTickets,
    appeals,
    ledger,
  ] = await Promise.all([
    safeCount(reports.where("reportedUserId", "==", uid)),
    safeCount(reports.where("reporterId", "==", uid)),
    reports.where("reportedUserId", "==", uid).orderBy("createdAt", "desc").limit(5).get(),
    db.collection(CASE_COLLECTION)
      .where("subjectUserId", "==", uid)
      .where("status", "in", [...ACTIVE_CASE_STATUSES])
      .limit(10)
      .get(),
    db.collection(ACTION_COLLECTION).where("targetUserId", "==", uid).orderBy("createdAt", "desc").limit(20).get(),
    db.collection("supportTickets").where("userId", "==", uid).orderBy("createdAt", "desc").limit(10).get(),
    db.collection("appeals").where("userId", "==", uid).orderBy("createdAt", "desc").limit(10).get(),
    db.collection(`users/${uid}/photoModeration`).limit(12).get(),
  ]);

  const a = account.data() ?? {};
  const p = profile.data() ?? {};
  const v = verification.data();
  const s = subscription.data();
  const staffRecord = parseStaffRecord(uid, staff.data());
  const photos = Array.isArray(p.photos) ? (p.photos as Array<Record<string, unknown>>) : [];

  const sensitive = input.includeSensitive;
  if (sensitive) {
    await recordAuditEvent(db, {
      actorAdminId: actor.uid,
      actorRole: actor.role,
      action: "SENSITIVE_PROFILE_VIEWED",
      targetType: "user",
      targetId: uid,
      requestId,
      metadata: {fields: ["email", "phone", "authProviders"], justification: input.justification ?? ""},
    }, nowMs);
  }

  const suspendedUntilMs = toMillis(a.suspendedUntil);
  return {
    uid,
    sensitiveIncluded: sensitive,
    account: {
      exists: account.exists,
      displayName: p.displayName ?? a.displayName ?? null,
      accountStatus: effectiveAccountStatus(a, nowMs),
      storedAccountStatus: a.accountStatus ?? "active",
      suspendedUntil: suspendedUntilMs ? new Date(suspendedUntilMs).toISOString() : null,
      statusReasonCode: a.statusReasonCode ?? null,
      statusActionId: a.statusActionId ?? null,
      statusUpdatedAt: iso(a.statusUpdatedAt),
      legacyFlags: {isBanned: a.isBanned === true, isSuspended: a.isSuspended === true},
      warningCount: typeof a.warningCount === "number" ? a.warningCount : 0,
      createdAt: iso(a.createdAt) ?? authRecord?.metadata?.creationTime ?? null,
      lastActiveAt: iso(a.lastActiveAt),
      isStaff: staffRecord !== null,
      staffRole: staffRecord?.role ?? null,
    },
    auth: {
      exists: authRecord !== null,
      disabled: authRecord?.disabled ?? null,
      phoneVerified: a.phoneVerified === true,
      email: sensitive ? (authRecord?.email ?? a.email ?? null) : maskEmail(authRecord?.email ?? a.email),
      phone: sensitive ? (authRecord?.phoneNumber ?? a.phoneNumber ?? null) : maskPhone(authRecord?.phoneNumber ?? a.phoneNumber),
      providers: sensitive ? (authRecord?.providerData ?? []).map((pd) => pd.providerId) : null,
      mfaFactors: (authRecord?.multiFactor?.enrolledFactors ?? []).length,
      lastSignInAt: authRecord?.metadata?.lastSignInTime ?? null,
    },
    profile: {
      exists: profile.exists,
      profileCompleted: p.profileCompleted === true,
      isDiscoverable: p.isDiscoverable === true,
      profileModerationStatus: p.profileModerationStatus ?? null,
      city: p.city ?? null,
      gender: p.gender ?? null,
      relationshipGoal: p.relationshipGoal ?? null,
      bio: typeof p.bio === "string" ? p.bio.slice(0, 1000) : null,
      interests: Array.isArray(p.interests) ? p.interests.slice(0, 20) : [],
      photoCount: photos.length,
      approvedPhotoCount: approvedPhotos(photos).length,
    },
    photos: photos.slice(0, 12).map((photo) => {
      const imageId = String(photo.id ?? "");
      const entry = ledger.docs.find((doc) => doc.id === imageId)?.data();
      return {
        imageId,
        isPrimary: photo.isPrimary === true,
        // The ledger is the authority; the profile array is only its echo.
        status: entry?.status ?? "pending",
        reason: entry?.reason ?? null,
        moderatedAt: iso(entry?.moderatedAt),
        url: entry?.status === "approved" && typeof entry?.downloadUrl === "string" ? entry.downloadUrl : null,
      };
    }),
    verification: v
      ? {
        provider: v.provider ?? null,
        status: v.status ?? "not_started",
        reason: v.reason ?? null,
        createdAt: iso(v.createdAt),
        updatedAt: iso(v.updatedAt),
        verifiedAt: iso(v.verifiedAt),
        attemptCount: typeof v.attemptCount === "number" ? v.attemptCount : 0,
        reverificationRequired: v.reverificationRequired === true,
      }
      : {provider: null, status: "not_started", reason: null, createdAt: null, updatedAt: null, verifiedAt: null, attemptCount: 0, reverificationRequired: false},
    isVerified: a.isVerified === true,
    safety: {
      reportsReceivedCount,
      reportsSubmittedCount,
      recentReports: recentReports.docs.map((doc) => ({
        reportId: doc.id,
        reason: doc.get("reason") ?? null,
        status: doc.get("status") ?? null,
        priority: doc.get("priority") ?? null,
        createdAt: iso(doc.get("createdAt")),
        caseId: doc.get("caseId") ?? null,
      })),
      openCases: openCases.docs.map((doc) => ({
        caseId: doc.id,
        type: doc.get("type") ?? null,
        status: doc.get("status") ?? null,
        priority: doc.get("priority") ?? null,
        assignedTo: doc.get("assignedTo") ?? null,
        createdAt: iso(doc.get("createdAt")),
      })),
      actions: actions.docs.map((doc) => actionRow(doc.id, doc.data())),
    },
    support: openTickets.docs.map((doc) => ({
      ticketId: doc.id,
      subject: typeof doc.get("subject") === "string" ? String(doc.get("subject")).slice(0, 120) : null,
      status: doc.get("status") ?? null,
      createdAt: iso(doc.get("createdAt")),
    })),
    appeals: appeals.docs.map((doc) => ({
      appealId: doc.id,
      status: doc.get("status") ?? null,
      decision: doc.get("decision") ?? null,
      moderationActionId: doc.get("moderationActionId") ?? null,
      createdAt: iso(doc.get("createdAt")),
    })),
    subscription: s
      ? {
        // Entitlement only. Purchase tokens, order ids and billing account
        // identifiers never leave the backend.
        isPremium: s.isPremium === true,
        productId: s.productId ?? null,
        expiresAt: iso(s.expiresAt),
        platform: s.platform ?? null,
      }
      : {isPremium: false, productId: null, expiresAt: null, platform: null},
  };
}
