import {Timestamp, type Query} from "firebase-admin/firestore";
import {ACTION_COLLECTION} from "./actions/actionTypes.js";
import {AUDIT_COLLECTION} from "./audit/auditService.js";
import type {AdminActor} from "./auth/adminAuthorization.js";
import type {Permission} from "./auth/permissions.js";
import {STAFF_COLLECTION} from "./auth/adminAuthorization.js";
import {ACTIVE_CASE_STATUSES, CASE_COLLECTION} from "./cases/caseTypes.js";
import type {AdminDeps} from "./deps.js";
import {AdminError} from "./errors.js";
import {cursorPart, decodeCursor, encodeCursor, iso} from "./validation.js";

/**
 * Dashboard counters. Each is a count() aggregation over an indexed filter —
 * billed per 1,000 index entries, never a document download — and each is
 * only computed when the caller holds the permission for that queue.
 */

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;

async function count(query: Query): Promise<number | null> {
  try {
    const snap = await query.count().get();
    return snap.data().count;
  } catch {
    // A missing index must not take the whole dashboard down.
    return null;
  }
}

export async function getDashboard(deps: AdminDeps, actor: AdminActor) {
  const {db} = deps;
  const has = (p: Permission) => actor.permissions.has(p);
  const cases = db.collection(CASE_COLLECTION);
  const active = [...ACTIVE_CASE_STATUSES];
  const tasks: Record<string, Promise<number | null>> = {};
  if (has("case.read")) {
    tasks.openCases = count(cases.where("status", "in", active));
    tasks.criticalCases = count(cases.where("priority", "==", "critical").where("status", "in", active));
    tasks.highPriorityCases = count(cases.where("priority", "==", "high").where("status", "in", active));
    tasks.myCases = count(cases.where("assignedTo", "==", actor.uid).where("status", "in", active));
    tasks.verificationReviewCases = count(cases.where("type", "==", "VERIFICATION_REVIEW").where("status", "in", active));
  }
  if (has("report.read")) {
    tasks.openReports = count(db.collection("reports").where("status", "==", "open"));
  }
  if (has("photo.read")) {
    tasks.photoManualReview = count(db.collectionGroup("photoModeration").where("status", "==", "manual_review"));
  }
  if (has("humor.read")) {
    tasks.humorReview = count(db.collection("humorModerationQueue").where("status", "==", "needs_review"));
  }
  if (has("verification.read")) {
    tasks.verificationInReview = count(db.collectionGroup("verification").where("status", "==", "in_review"));
  }
  if (has("automation.read") || has("automation.review")) {
    tasks.automationManualReview = count(db.collection("automationJobs").where("status", "==", "manual_review"));
  }
  if (has("appeal.read")) {
    tasks.openAppeals = count(db.collection("appeals").where("status", "in", ["open", "in_review"]));
  }
  if (has("support.read")) {
    const tickets = db.collection("supportTickets");
    tasks.openSupportTickets = count(tickets.where("status", "in", ["open", "Open", "in_progress", "InProgress"]));
    tasks.urgentSupportTickets = Promise.all([
      count(tickets.where("priority", "==", "urgent").where("status", "in", ["open", "Open", "in_progress", "InProgress"])),
      count(tickets.where("priority", "==", "Urgent").where("status", "in", ["open", "Open", "in_progress", "InProgress"])),
    ]).then(([a, b]) => (a === null && b === null ? null : (a ?? 0) + (b ?? 0)));
  }
  if (has("user.read")) {
    // Platform size. count() over the users collection costs one read per
    // 1,000 index entries, not a document download.
    const users = db.collection("users");
    tasks.totalUsers = count(users);
    tasks.newUsers7d = count(users.where("createdAt", ">=", Timestamp.fromMillis(deps.now() - WEEK_MS)));
    tasks.activeUsers7d = count(users.where("lastActiveAt", ">=", Timestamp.fromMillis(deps.now() - WEEK_MS)));
    tasks.suspendedAccounts = count(users.where("accountStatus", "==", "suspended"));
    tasks.bannedAccounts = count(users.where("accountStatus", "==", "banned"));
  }
  if (has("admin.manage_staff")) {
    const staff = db.collection(STAFF_COLLECTION);
    tasks.activeStaff = count(staff.where("status", "==", "active"));
    tasks.disabledStaff = count(staff.where("status", "==", "disabled"));
  }
  const keys = Object.keys(tasks);
  const values = await Promise.all(keys.map((k) => tasks[k]));
  const counters = Object.fromEntries(keys.map((k, i) => [k, values[i]]));

  let recentActions: Array<Record<string, unknown>> = [];
  if (has("user.read")) {
    const snap = await db.collection(ACTION_COLLECTION).orderBy("createdAt", "desc").limit(10).get();
    recentActions = snap.docs.map((doc) => ({
      actionId: doc.id,
      type: doc.get("type") ?? null,
      targetUserId: doc.get("targetUserId") ?? null,
      reasonCode: doc.get("reasonCode") ?? null,
      actorAdminId: doc.get("actorAdminId") ?? null,
      createdAt: iso(doc.get("createdAt")),
    }));
  }
  let recentAdminActions: Array<Record<string, unknown>> = [];
  if (has("audit.read")) {
    // Staff actions, not sign-ins: over-fetch a little and drop ADMIN_LOGIN.
    const snap = await db.collection(AUDIT_COLLECTION).orderBy("createdAt", "desc").limit(25).get();
    recentAdminActions = snap.docs
      .filter((doc) => doc.get("action") !== "ADMIN_LOGIN")
      .slice(0, 10)
      .map((doc) => ({
        eventId: doc.id,
        action: doc.get("action") ?? null,
        actorAdminId: doc.get("actorAdminId") ?? null,
        actorRole: doc.get("actorRole") ?? null,
        targetType: doc.get("targetType") ?? null,
        targetId: doc.get("targetId") ?? null,
        createdAt: iso(doc.get("createdAt")),
      }));
  }
  return {counters, recentActions, recentAdminActions, generatedAt: new Date(deps.now()).toISOString()};
}

export interface AuditFilters {
  actorAdminId: string | null;
  actorRole: string | null;
  action: string | null;
  targetType: string | null;
  targetId: string | null;
  caseId: string | null;
  /** Inclusive lower bound, epoch ms. */
  fromMs: number | null;
  /** Exclusive upper bound, epoch ms. */
  toMs: number | null;
}

/** Most selective first: the first present filter runs in Firestore. */
const PRIMARY_ORDER = ["targetId", "caseId", "actorAdminId", "action", "targetType", "actorRole"] as const;
const SCAN_BATCH = 100;
/** Hard ceiling on audit documents read by one list request. */
export const AUDIT_SCAN_CAP = 500;

/**
 * The audit log, newest first, filtered by any combination of staff member,
 * role, action, target type, target, case and date range.
 *
 * The most selective equality filter plus the date range run in Firestore
 * (field + createdAt composite indexes); the remaining filters are applied to
 * that ordered stream in memory. A request reads at most AUDIT_SCAN_CAP
 * documents: when it stops early the page is marked `partial` and the cursor
 * continues exactly where the scan ended, so nothing is skipped or repeated.
 */
export async function listAuditEvents(
  deps: AdminDeps,
  input: AuditFilters & {cursor: unknown; limit: number},
) {
  if (input.fromMs !== null && input.toMs !== null && input.fromMs >= input.toMs) {
    throw new AdminError("invalid_argument", "date_range");
  }
  const primary = PRIMARY_ORDER.find((field) => input[field] !== null) ?? null;
  const secondary = PRIMARY_ORDER.filter((field) => field !== primary && input[field] !== null);

  let base: Query = deps.db.collection(AUDIT_COLLECTION);
  if (primary) {
    base = base.where(primary, "==", input[primary]);
  }
  if (input.fromMs !== null) {
    base = base.where("createdAt", ">=", Timestamp.fromMillis(input.fromMs));
  }
  if (input.toMs !== null) {
    base = base.where("createdAt", "<", Timestamp.fromMillis(input.toMs));
  }
  base = base.orderBy("createdAt", "desc").orderBy("__name__", "desc");

  const matches = (doc: FirebaseFirestore.QueryDocumentSnapshot) =>
    secondary.every((field) => doc.get(field) === input[field]);

  const items: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  let after = decodeCursor(input.cursor, 2);
  let scanned = 0;
  let exhausted = false;
  let lastScanned: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  while (items.length < input.limit && scanned < AUDIT_SCAN_CAP) {
    // Without secondary filters every read is a hit: read exactly the page.
    const size = secondary.length ? Math.min(SCAN_BATCH, AUDIT_SCAN_CAP - scanned) : input.limit - items.length;
    const snap = await (after ? base.startAfter(...after) : base).limit(size).get();
    scanned += snap.size;
    for (const doc of snap.docs) {
      lastScanned = doc;
      if (matches(doc)) {
        items.push(doc);
        if (items.length === input.limit) {
          break;
        }
      }
    }
    if (snap.size < size) {
      exhausted = true;
      break;
    }
    if (lastScanned) {
      after = [cursorPart(lastScanned.get("createdAt")), lastScanned.id];
    }
  }
  const resumeFrom = items.length === input.limit ? items[items.length - 1] : lastScanned;
  const more = !exhausted && resumeFrom !== null;
  return {
    items: items.map((doc) => ({
      eventId: doc.id,
      action: doc.get("action") ?? null,
      actorAdminId: doc.get("actorAdminId") ?? null,
      actorRole: doc.get("actorRole") ?? null,
      targetType: doc.get("targetType") ?? null,
      targetId: doc.get("targetId") ?? null,
      caseId: doc.get("caseId") ?? null,
      actionId: doc.get("actionId") ?? null,
      requestId: doc.get("requestId") ?? null,
      metadata: doc.get("metadata") ?? {},
      createdAt: iso(doc.get("createdAt")),
    })),
    nextCursor: more && resumeFrom ? encodeCursor([cursorPart(resumeFrom.get("createdAt")), resumeFrom.id]) : null,
    partial: more && items.length < input.limit,
    scanned,
  };
}
