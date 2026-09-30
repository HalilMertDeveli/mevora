import {Timestamp, type Query} from "firebase-admin/firestore";
import {ACTION_COLLECTION} from "../actions/actionTypes.js";
import {CASE_COLLECTION} from "../cases/caseTypes.js";
import type {AdminDeps} from "../deps.js";
import {toMillis} from "../validation.js";

/**
 * Chronological safety history for one member, projected server-side.
 *
 * Sources: reports received, moderation cases, moderation actions, photo
 * moderation ledger, identity verification, support escalations, appeals and
 * account creation. Each source is read with a bounded, indexed query older
 * than `before`, merged, and cut to `limit`; the oldest event served becomes
 * the next `before`, so the timeline pages backwards without a full scan.
 *
 * Private moderator context: served only to staff with user.read, never to a
 * client. Report descriptions, notes and message content are not included —
 * an event says what happened, the detail screens say why.
 */

export interface TimelineEvent {
  at: string;
  atMs: number;
  kind: string;
  title: string;
  detail: Record<string, unknown>;
  ref: string | null;
}

const PER_SOURCE = 25;

function beforeFilter(q: Query, field: string, beforeMs: number | null): Query {
  return beforeMs === null ? q : q.where(field, "<", Timestamp.fromMillis(beforeMs));
}

export async function getUserSafetyTimeline(
  deps: AdminDeps,
  input: {uid: string; beforeMs: number | null; limit: number},
): Promise<{events: TimelineEvent[]; nextBeforeMs: number | null}> {
  const {db} = deps;
  const {uid, beforeMs} = input;
  const events: TimelineEvent[] = [];
  const push = (atRaw: unknown, kind: string, title: string, detail: Record<string, unknown>, ref: string | null) => {
    const atMs = toMillis(atRaw);
    if (atMs === null || (beforeMs !== null && atMs >= beforeMs)) {
      return;
    }
    events.push({at: new Date(atMs).toISOString(), atMs, kind, title, detail, ref});
  };

  const [reports, cases, actions, ledger, verification, tickets, appeals, account] = await Promise.all([
    beforeFilter(db.collection("reports").where("reportedUserId", "==", uid), "createdAt", beforeMs)
      .orderBy("createdAt", "desc").limit(PER_SOURCE).get(),
    beforeFilter(db.collection(CASE_COLLECTION).where("subjectUserId", "==", uid), "createdAt", beforeMs)
      .orderBy("createdAt", "desc").limit(PER_SOURCE).get(),
    beforeFilter(db.collection(ACTION_COLLECTION).where("targetUserId", "==", uid), "createdAt", beforeMs)
      .orderBy("createdAt", "desc").limit(PER_SOURCE).get(),
    // Per-user subcollection, at most a handful of documents (max 6 photos).
    db.collection(`users/${uid}/photoModeration`).limit(PER_SOURCE).get(),
    db.doc(`users/${uid}/verification/identity`).get(),
    beforeFilter(db.collection("supportTickets").where("userId", "==", uid), "createdAt", beforeMs)
      .orderBy("createdAt", "desc").limit(PER_SOURCE).get(),
    beforeFilter(db.collection("appeals").where("userId", "==", uid), "createdAt", beforeMs)
      .orderBy("createdAt", "desc").limit(PER_SOURCE).get(),
    db.doc(`users/${uid}`).get(),
  ]);

  for (const doc of reports.docs) {
    const reason = String(doc.get("reason") ?? "other");
    push(doc.get("createdAt"), "report_received", `Report received — ${reason}`, {
      reason,
      priority: doc.get("priority") ?? null,
      status: doc.get("status") ?? null,
      caseId: doc.get("caseId") ?? null,
    }, `reports/${doc.id}`);
  }
  for (const doc of cases.docs) {
    push(doc.get("createdAt"), "case_opened", `Case opened — ${doc.get("type")}`, {
      caseId: doc.id,
      status: doc.get("status") ?? null,
      priority: doc.get("priority") ?? null,
    }, `${CASE_COLLECTION}/${doc.id}`);
    if (doc.get("resolvedAt")) {
      push(doc.get("resolvedAt"), "case_closed", `Case ${doc.get("status")} — ${doc.get("resolution")?.code ?? ""}`.trim(), {
        caseId: doc.id,
      }, `${CASE_COLLECTION}/${doc.id}`);
    }
  }
  for (const doc of actions.docs) {
    const type = String(doc.get("type") ?? "");
    push(doc.get("createdAt") ?? doc.get("effectiveAt"), "moderation_action", ACTION_TITLES[type] ?? type, {
      actionId: doc.id,
      type,
      reasonCode: doc.get("reasonCode") ?? null,
      expiresAt: toMillis(doc.get("expiresAt")) ? new Date(toMillis(doc.get("expiresAt")) as number).toISOString() : null,
      overturned: Boolean(doc.get("overturnedByActionId")),
    }, `${ACTION_COLLECTION}/${doc.id}`);
  }
  for (const doc of ledger.docs) {
    const status = String(doc.get("status") ?? "pending");
    push(doc.get("moderatedAt") ?? doc.get("updatedAt"), "photo_moderation", `Photo ${status.replace("_", " ")}`, {
      imageId: doc.id,
      status,
      reason: doc.get("reason") ?? null,
    }, `users/${uid}/photoModeration/${doc.id}`);
  }
  const v = verification.data();
  if (v) {
    if (v.createdAt) {
      push(v.createdAt, "verification_started", "Identity verification started", {provider: v.provider ?? null}, null);
    }
    if (v.verifiedAt) {
      push(v.verifiedAt, "verification_verified", "Identity verification — verified", {provider: v.provider ?? null}, null);
    }
    if (v.reverificationRequiredAt) {
      push(v.reverificationRequiredAt, "verification_reverification", "Re-verification required", {}, null);
    }
    if (v.updatedAt && !["verified", "pending"].includes(String(v.status))) {
      push(v.updatedAt, "verification_status", `Identity verification — ${v.status}`, {status: v.status, reason: v.reason ?? null}, null);
    }
  }
  for (const doc of tickets.docs) {
    push(doc.get("createdAt"), "support_ticket", `Support ticket — ${doc.get("category") ?? "general"}`, {
      ticketId: doc.id,
      status: doc.get("status") ?? null,
    }, `supportTickets/${doc.id}`);
    if (doc.get("escalatedAt")) {
      push(doc.get("escalatedAt"), "support_escalation", "Support ticket escalated", {ticketId: doc.id, caseId: doc.get("caseId") ?? null}, `supportTickets/${doc.id}`);
    }
  }
  for (const doc of appeals.docs) {
    push(doc.get("createdAt"), "appeal_submitted", "Appeal submitted", {
      appealId: doc.id,
      actionType: doc.get("actionType") ?? null,
    }, `appeals/${doc.id}`);
    if (doc.get("resolvedAt")) {
      push(doc.get("resolvedAt"), "appeal_resolved", `Appeal ${doc.get("decision") ?? "resolved"}`, {appealId: doc.id}, `appeals/${doc.id}`);
    }
  }
  const a = account.data();
  if (a?.createdAt) {
    push(a.createdAt, "account_created", "Account created", {}, null);
  }

  events.sort((x, y) => y.atMs - x.atMs);
  const page = events.slice(0, input.limit);
  // Correct as long as limit ≤ PER_SOURCE: every source's events newer than
  // the page's oldest event are within that source's first PER_SOURCE rows.
  const nextBeforeMs = page.length === input.limit ? page[page.length - 1].atMs : null;
  return {events: page, nextBeforeMs};
}

const ACTION_TITLES: Record<string, string> = {
  WARNING: "Warning issued",
  TEMPORARY_SUSPENSION: "Account suspended",
  PERMANENT_BAN: "Account banned",
  RESTORE_ACCOUNT: "Account restored",
  SUSPENSION_EXPIRED: "Suspension expired",
  PHOTO_APPROVED: "Photo approved by moderator",
  PHOTO_REJECTED: "Photo rejected by moderator",
  PHOTO_REMOVED: "Published photo removed",
  REQUIRE_REVERIFICATION: "Re-verification required",
  SUPPORT_ESCALATION: "Support escalation",
  APPEAL_ACCEPTED: "Appeal accepted",
  APPEAL_REJECTED: "Appeal rejected",
};
