import {randomBytes} from "node:crypto";
import {FieldValue, type DocumentReference, type Firestore} from "firebase-admin/firestore";
import {redactString} from "../../security/logHygiene.js";
import type {AuditEventInput} from "./auditTypes.js";

/**
 * Append-only admin audit log: `adminAuditLog/{eventId}`.
 *
 * - Written only with `create`, so an existing event can never be overwritten
 *   (a colliding id fails the write, and with it the transaction).
 * - There is no update or delete path anywhere in the admin platform, and the
 *   Firestore rules deny every client operation on the collection.
 * - Retention deletion is the scheduled sweep's job alone (retention.ts), and
 *   only past the documented horizon.
 *
 * Metadata is scrubbed before it is stored: secrets, message bodies, identity
 * documents and raw provider payloads have no business in an audit trail, and
 * free-text is reduced to its length.
 */
export const AUDIT_COLLECTION = "adminAuditLog";

/** Keys whose values are dropped outright. */
const FORBIDDEN_KEY =
  /(password|passcode|token|otp|secret|authorization|cookie|credential|private|ciphertext|plaintext|body|messageText|^text$|^message$|document|selfie|liveness|biometric|mrz|payload|raw|webhook|apiKey|note$|notes$|justification)/i;

const MAX_DEPTH = 3;
const MAX_STRING = 300;
const MAX_ARRAY = 20;

function scrubValue(value: unknown, depth: number): unknown {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string") {
    return redactString(value).slice(0, MAX_STRING);
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return value;
  }
  if (Array.isArray(value)) {
    return value.slice(0, MAX_ARRAY).map((item) => scrubValue(item, depth + 1));
  }
  if (typeof value === "object") {
    if (depth >= MAX_DEPTH) {
      return "[truncated]";
    }
    return scrubAuditMetadata(value as Record<string, unknown>, depth + 1);
  }
  return null;
}

export function scrubAuditMetadata(
  metadata: Record<string, unknown>,
  depth = 0,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(metadata)) {
    if (FORBIDDEN_KEY.test(key)) {
      // The fact that free text existed is useful; its content is not.
      if (typeof value === "string" && value.length > 0) {
        out[`${key}Length`] = value.length;
      }
      continue;
    }
    out[key] = scrubValue(value, depth);
  }
  return out;
}

export function newAuditEventId(nowMs: number): string {
  // Sortable prefix so the console can reason about order, random suffix so
  // two events in the same millisecond never collide.
  return `aud_${nowMs.toString(36).padStart(9, "0")}_${randomBytes(6).toString("hex")}`;
}

export function buildAuditEvent(input: AuditEventInput): Record<string, unknown> {
  return {
    actorAdminId: input.actorAdminId,
    actorRole: input.actorRole ?? null,
    action: input.action,
    targetType: input.targetType,
    targetId: input.targetId,
    caseId: input.caseId ?? null,
    actionId: input.actionId ?? null,
    requestId: input.requestId ?? null,
    metadata: scrubAuditMetadata(input.metadata ?? {}),
    createdAt: FieldValue.serverTimestamp(),
  };
}

interface CreateWriter {
  create(ref: DocumentReference, data: Record<string, unknown>): unknown;
}

/**
 * Appends one event through a transaction or batch, so it commits (or not)
 * together with the state change it records. Returns the event id.
 */
export function appendAuditEvent(
  writer: CreateWriter,
  db: Firestore,
  input: AuditEventInput,
  nowMs: number = Date.now(),
): string {
  const eventId = newAuditEventId(nowMs);
  writer.create(db.doc(`${AUDIT_COLLECTION}/${eventId}`), buildAuditEvent(input));
  return eventId;
}

/** Standalone append, for events that do not accompany a state change. */
export async function recordAuditEvent(
  db: Firestore,
  input: AuditEventInput,
  nowMs: number = Date.now(),
): Promise<string> {
  const eventId = newAuditEventId(nowMs);
  await db.doc(`${AUDIT_COLLECTION}/${eventId}`).create(buildAuditEvent(input));
  return eventId;
}
