import {createHash} from "node:crypto";
import {Timestamp} from "firebase-admin/firestore";
import {AdminError} from "./errors.js";

/**
 * Input parsing for admin commands.
 *
 * Every command parses its payload into a typed object before the handler
 * runs. Unknown keys are ignored, never spread into a Firestore write: a
 * command writes the fields it names and nothing a caller slipped in
 * (mass-assignment is structurally impossible).
 */

export type Raw = Record<string, unknown>;

export function asRecord(raw: unknown): Raw {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? (raw as Raw) : {};
}

/** Firebase uids are ≤ 128 chars and never contain "/". */
const UID_PATTERN = /^[^/\s]{1,128}$/;
/** Document ids we mint or accept from the admin web. */
const DOC_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;
const IDEMPOTENCY_PATTERN = /^[A-Za-z0-9_-]{8,128}$/;

export function uid(raw: unknown, field = "uid"): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!UID_PATTERN.test(value)) {
    throw new AdminError("invalid_argument", field);
  }
  return value;
}

export function optionalUid(raw: unknown, field = "uid"): string | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  return uid(raw, field);
}

export function docId(raw: unknown, field = "id"): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!DOC_ID_PATTERN.test(value)) {
    throw new AdminError("invalid_argument", field);
  }
  return value;
}

export function optionalDocId(raw: unknown, field = "id"): string | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  return docId(raw, field);
}

export function text(
  raw: unknown,
  field: string,
  options: {max: number; min?: number; required?: boolean},
): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  const min = options.min ?? (options.required ? 1 : 0);
  if (value.length < min || value.length > options.max) {
    throw new AdminError("invalid_argument", field, {field, max: options.max, min});
  }
  return value;
}

export function optionalText(raw: unknown, field: string, max: number): string | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  const value = text(raw, field, {max});
  return value.length ? value : null;
}

export function oneOf<T extends string>(
  raw: unknown,
  allowed: readonly T[],
  field: string,
): T {
  if (typeof raw === "string" && (allowed as readonly string[]).includes(raw)) {
    return raw as T;
  }
  throw new AdminError("invalid_argument", field, {field, allowed: [...allowed]});
}

export function optionalOneOf<T extends string>(
  raw: unknown,
  allowed: readonly T[],
  field: string,
): T | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  return oneOf(raw, allowed, field);
}

export function integer(
  raw: unknown,
  field: string,
  options: {min: number; max: number},
): number {
  const value = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isInteger(value) || value < options.min || value > options.max) {
    throw new AdminError("invalid_argument", field, {field, ...options});
  }
  return value;
}

export function bool(raw: unknown): boolean {
  return raw === true;
}

export function pageLimit(raw: unknown, fallback = 25, max = 50): number {
  if (raw === undefined || raw === null) {
    return fallback;
  }
  return integer(raw, "limit", {min: 1, max});
}

/**
 * High-impact commands require a caller-generated key per logical submission
 * (the admin web mints one per rendered form). A retried request carrying the
 * same key replays the first result instead of acting twice.
 */
export function idempotencyKey(raw: unknown): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  if (!IDEMPOTENCY_PATTERN.test(value)) {
    throw new AdminError("invalid_argument", "idempotencyKey");
  }
  return value;
}

/** Deterministic id for the record one logical command produces. */
export function deterministicId(prefix: string, ...parts: string[]): string {
  const digest = createHash("sha256").update(parts.join("|")).digest("hex").slice(0, 32);
  return `${prefix}_${digest}`;
}

// ---------------------------------------------------------------------------
// Cursors
// ---------------------------------------------------------------------------

/**
 * Opaque pagination cursor. It carries the ordering values of the last
 * document served, never a Firestore snapshot, so a caller cannot page into a
 * different query by editing it: the handler re-applies its own filters and
 * only uses the values for `startAfter`.
 */
export type CursorValue = string | number | null | {ts: number};

export function encodeCursor(values: CursorValue[]): string {
  return Buffer.from(JSON.stringify(values), "utf8").toString("base64url");
}

export function decodeCursor(raw: unknown, arity: number): unknown[] | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  if (typeof raw !== "string" || raw.length > 1024) {
    throw new AdminError("invalid_argument", "cursor");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(Buffer.from(raw, "base64url").toString("utf8"));
  } catch {
    throw new AdminError("invalid_argument", "cursor");
  }
  if (!Array.isArray(parsed) || parsed.length !== arity) {
    throw new AdminError("invalid_argument", "cursor");
  }
  return parsed.map((value) => {
    if (value && typeof value === "object" && typeof (value as {ts?: unknown}).ts === "number") {
      return Timestamp.fromMillis((value as {ts: number}).ts);
    }
    if (value === null || typeof value === "string" || typeof value === "number") {
      return value;
    }
    throw new AdminError("invalid_argument", "cursor");
  });
}

/** A Firestore value turned into something `encodeCursor` can carry. */
export function cursorPart(value: unknown): CursorValue {
  const millis = toMillis(value);
  if (millis !== null && typeof value === "object") {
    return {ts: millis};
  }
  if (typeof value === "string" || typeof value === "number") {
    return value;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

export function toMillis(value: unknown): number | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  const withMillis = value as {toMillis?: () => number};
  if (typeof withMillis.toMillis === "function") {
    return withMillis.toMillis();
  }
  if (typeof value === "number") {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  return null;
}

/** ISO string for the wire; the admin web never sees Firestore Timestamps. */
export function iso(value: unknown): string | null {
  const millis = toMillis(value);
  return millis === null ? null : new Date(millis).toISOString();
}
