import {FieldValue, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../../security/logHygiene.js";
import {openOrAttachCase} from "../cases/caseService.js";
import {reportCorrelationKey, reportPriority} from "./reportPriority.js";

/**
 * Routes a newly written user report into the case system.
 *
 * The report document stays where reportUser wrote it and keeps its shape;
 * intake only adds server-owned fields (`caseId`) and opens or joins the
 * USER_REPORT case for (reported user, reason). Called by reportUser after
 * the report is stored — a failure here is logged and never fails the
 * member's report: the report queue lists reports without a case too, and
 * staff can open one from there.
 */
export async function intakeUserReport(
  db: Firestore,
  report: {
    reportId: string;
    reporterId: string;
    reportedUserId: string;
    reason: string;
  },
  nowMs: number = Date.now(),
): Promise<{caseId: string | null}> {
  try {
    const {priority} = reportPriority(report.reason);
    const {caseId} = await openOrAttachCase(db, {
      type: "USER_REPORT",
      correlationKey: reportCorrelationKey(report.reportedUserId, report.reason),
      subjectUserId: report.reportedUserId,
      sourceRef: `reports/${report.reportId}`,
      reasonCode: report.reason,
      priority,
      reporterId: report.reporterId,
      summary: `User report: ${report.reason}`,
      createdBy: "system",
    }, nowMs);
    await db.doc(`reports/${report.reportId}`).set({caseId, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {caseId};
  } catch (error) {
    logger.error("report_case_intake_failed", safeLogMeta({reportId: report.reportId, error: String(error)}));
    return {caseId: null};
  }
}
