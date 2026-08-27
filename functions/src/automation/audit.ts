import {FieldValue, getFirestore, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

const COLLECTION = "auditLogs";

export type AuditEntry = {
  adminUid: string;
  action: string;
  targetUid?: string | null;
  reason?: string | null;
  result: "success" | "failure" | "denied" | "dry_run";
  metadata?: Record<string, unknown>;
  jobId?: string | null;
};

/** Append-only admin / automation audit trail. Never log secrets. */
export async function writeAuditLog(
  entry: AuditEntry,
  db: Firestore = getFirestore(),
): Promise<string> {
  const safeMeta = sanitizeMetadata(entry.metadata ?? {});
  const ref = db.collection(COLLECTION).doc();
  await ref.set({
    adminUid: entry.adminUid,
    action: entry.action,
    targetUid: entry.targetUid ?? null,
    reason: entry.reason ?? null,
    result: entry.result,
    metadata: safeMeta,
    jobId: entry.jobId ?? null,
    timestamp: FieldValue.serverTimestamp(),
  });
  logger.info("audit", {
    id: ref.id,
    action: entry.action,
    adminUid: entry.adminUid,
    targetUid: entry.targetUid ?? null,
    result: entry.result,
  });
  return ref.id;
}

const SECRET_KEYS = /token|secret|password|apikey|api_key|authorization|credential|private/i;

function sanitizeMetadata(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(input)) {
    if (SECRET_KEYS.test(key)) {
      out[key] = "[redacted]";
      continue;
    }
    if (typeof value === "string" && value.length > 500) {
      out[key] = `${value.slice(0, 500)}…`;
      continue;
    }
    out[key] = value;
  }
  return out;
}

export function maskEmail(email: string | null | undefined): string | null {
  if (!email || !email.includes("@")) {
    return email ? "***" : null;
  }
  const [local, domain] = email.split("@");
  const visible = local.length <= 2 ? "*" : `${local[0]}***${local[local.length - 1]}`;
  return `${visible}@${domain}`;
}

export function maskPhone(phone: string | null | undefined): string | null {
  if (!phone) {
    return null;
  }
  const digits = phone.replace(/\D/g, "");
  if (digits.length < 4) {
    return "***";
  }
  return `***${digits.slice(-4)}`;
}
