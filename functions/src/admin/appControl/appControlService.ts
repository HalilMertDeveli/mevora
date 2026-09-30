import {createHash} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  APP_OPERATIONS_COLLECTION,
  APP_OPERATIONS_CURRENT,
  APP_OPERATIONS_PUBLIC,
  APP_OPERATIONS_SCHEMA_VERSION,
  parseAppOperationsState,
  type AnnouncementSeverity,
  type AppFeature,
  type AppOperationsState,
  type AppPlatform,
} from "../../appOperations/appOperationsConfig.js";
import {appendAuditEvent} from "../audit/auditService.js";
import type {AuditAction} from "../audit/auditTypes.js";
import type {AdminActor} from "../auth/adminAuthorization.js";
import type {AdminDeps} from "../deps.js";
import {AdminError} from "../errors.js";
import {deterministicId, iso} from "../validation.js";

/**
 * App Control: the owner's controlled switches for the mobile app. Not a
 * database editor — four named changes, each validated, revision-checked,
 * idempotent and audited, each writing the server-only record and the public
 * projection the app reads in one transaction.
 *
 * Staleness: every change names the revision it was made against
 * (`expectedRevision`); if someone else changed the config since, the change
 * is refused (`conflict`) instead of silently overwriting theirs.
 * Replay: the same idempotency key returns the first result without writing.
 */

/** Idempotency markers; server-only like everything admin. */
export const APP_OPERATIONS_WRITES = "appOperationsConfigWrites";

export const TITLE_MAX = 80;
export const MESSAGE_MAX = 280;
const VERSION_PATTERN = /^\d{1,4}(\.\d{1,4}){0,3}$/;
const STORE_HOSTS = new Set(["play.google.com", "apps.apple.com", "itunes.apple.com"]);
const MAX_ANNOUNCEMENT_DAYS = 31;
const DAY_MS = 24 * 60 * 60 * 1000;

interface CurrentRecord {
  state: AppOperationsState;
  revision: number;
  updatedAt: string | null;
  updatedBy: string | null;
}

function readCurrent(data: Record<string, unknown> | undefined): CurrentRecord {
  return {
    state: parseAppOperationsState(data),
    revision: typeof data?.revision === "number" ? data.revision : 0,
    updatedAt: iso(data?.updatedAt),
    updatedBy: typeof data?.updatedBy === "string" ? data.updatedBy : null,
  };
}

/** The document the app reads. Only what the app needs; no actor or reason. */
function publicProjection(state: AppOperationsState, revision: number) {
  const a = state.announcement;
  return {
    schemaVersion: APP_OPERATIONS_SCHEMA_VERSION,
    revision,
    updatedAt: FieldValue.serverTimestamp(),
    maintenance: {enabled: state.maintenance.enabled, message: state.maintenance.message},
    minimumVersion: state.minimumVersion,
    recommendedVersion: state.recommendedVersion,
    updateUrl: state.updateUrl,
    features: state.features,
    announcement: a
      ? {
        enabled: a.enabled,
        id: a.id,
        title: a.title,
        message: a.message,
        severity: a.severity,
        startsAt: a.startsAtMs === null ? null : Timestamp.fromMillis(a.startsAtMs),
        expiresAt: a.expiresAtMs === null ? null : Timestamp.fromMillis(a.expiresAtMs),
      }
      : null,
  };
}

function stateView(record: CurrentRecord) {
  const a = record.state.announcement;
  return {
    revision: record.revision,
    updatedAt: record.updatedAt,
    updatedBy: record.updatedBy,
    maintenance: record.state.maintenance,
    minimumVersion: record.state.minimumVersion,
    recommendedVersion: record.state.recommendedVersion,
    updateUrl: record.state.updateUrl,
    features: record.state.features,
    announcement: a
      ? {
        ...a,
        startsAt: a.startsAtMs === null ? null : new Date(a.startsAtMs).toISOString(),
        expiresAt: a.expiresAtMs === null ? null : new Date(a.expiresAtMs).toISOString(),
      }
      : null,
  };
}

// --- Validation --------------------------------------------------------------

/**
 * Plain text only. The app renders text, never markup, but the console refuses
 * anything that looks like HTML so nobody is tempted to rely on it; control
 * characters (except line breaks) are removed.
 */
export function plainText(raw: unknown, field: string, max: number, required: boolean): string | null {
  if (raw === undefined || raw === null || (typeof raw === "string" && raw.trim() === "")) {
    if (required) {
      throw new AdminError("invalid_argument", field);
    }
    return null;
  }
  if (typeof raw !== "string") {
    throw new AdminError("invalid_argument", field);
  }
  // eslint-disable-next-line no-control-regex
  const value = raw.replace(/\r\n?/g, "\n").replace(/[\u0000-\u0009\u000B-\u001F\u007F​-‏‪-‮⁦-⁩]/g, "").trim();
  if (value.length === 0 && required) {
    throw new AdminError("invalid_argument", field);
  }
  if (value.length > max) {
    throw new AdminError("invalid_argument", `${field}_too_long`);
  }
  if (/[<>]/.test(value)) {
    throw new AdminError("invalid_argument", `${field}_plain_text_only`);
  }
  return value.length ? value : null;
}

export function versionOrNull(raw: unknown, field: string): string | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  if (typeof raw !== "string" || !VERSION_PATTERN.test(raw.trim())) {
    throw new AdminError("invalid_argument", field);
  }
  return raw.trim();
}

/** Numeric comparison of dotted versions ("1.10.0" > "1.9.3"). */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) {
      return d < 0 ? -1 : 1;
    }
  }
  return 0;
}

/** Store listings only: an update link can never point members somewhere else. */
export function storeUrlOrNull(raw: unknown, field: string): string | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  if (typeof raw !== "string" || raw.length > 300) {
    throw new AdminError("invalid_argument", field);
  }
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new AdminError("invalid_argument", field);
  }
  if (url.protocol !== "https:" || !STORE_HOSTS.has(url.hostname) || url.username || url.password) {
    throw new AdminError("invalid_argument", `${field}_store_only`);
  }
  return url.toString();
}

export function instantOrNull(raw: unknown, field: string): number | null {
  if (raw === undefined || raw === null || raw === "") {
    return null;
  }
  const ms = typeof raw === "string" ? Date.parse(raw) : NaN;
  if (Number.isNaN(ms)) {
    throw new AdminError("invalid_argument", field);
  }
  return ms;
}

// --- Reads -------------------------------------------------------------------

async function timed<T>(probe: () => Promise<T>): Promise<{ok: boolean; ms: number}> {
  const started = Date.now();
  try {
    await probe();
    return {ok: true, ms: Date.now() - started};
  } catch {
    return {ok: false, ms: Date.now() - started};
  }
}

/**
 * The current config plus what the backend can honestly say about its own
 * health: each probe is a real call made now. Nothing here is synthesised.
 */
export async function getAppControl(deps: AdminDeps, actor: AdminActor) {
  let data: Record<string, unknown> | undefined;
  const firestore = await timed(async () => {
    data = (await deps.db.doc(APP_OPERATIONS_CURRENT).get()).data();
  });
  const [auth, storage] = await Promise.all([
    timed(() => deps.auth.getUser(actor.uid)),
    timed(() => deps.bucket().file("healthcheck/app-control").exists()),
  ]);
  const record = readCurrent(data);
  return {
    config: stateView(record),
    health: {
      backend: {ok: true},
      firestore,
      auth,
      storage,
      environment: process.env.FUNCTIONS_EMULATOR === "true" ? "emulator" : "production",
      projectId: process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? null,
      checkedAt: new Date(deps.now()).toISOString(),
    },
  };
}

// --- Changes -----------------------------------------------------------------

interface ChangeEnvelope {
  expectedRevision: number;
  idempotencyKey: string;
}

interface Change {
  action: AuditAction;
  metadata: Record<string, unknown>;
}

async function applyChange(
  deps: AdminDeps,
  actor: AdminActor,
  requestId: string,
  command: string,
  envelope: ChangeEnvelope,
  mutate: (state: AppOperationsState) => Change,
) {
  const {db} = deps;
  const nowMs = deps.now();
  const currentRef = db.doc(APP_OPERATIONS_CURRENT);
  const publicRef = db.doc(APP_OPERATIONS_PUBLIC);
  const markerRef = db.doc(`${APP_OPERATIONS_WRITES}/${deterministicId("appctl", actor.uid, command, envelope.idempotencyKey)}`);
  return db.runTransaction(async (tx) => {
    const [currentSnap, marker] = await Promise.all([tx.get(currentRef), tx.get(markerRef)]);
    if (marker.exists) {
      return {replay: true, revision: marker.get("revision") as number, changed: marker.get("changed") === true};
    }
    const current = readCurrent(currentSnap.data());
    if (current.revision !== envelope.expectedRevision) {
      throw new AdminError("conflict", "stale_revision", {currentRevision: current.revision});
    }
    const next: AppOperationsState = structuredClone(current.state);
    const change = mutate(next);
    const changed = JSON.stringify(next) !== JSON.stringify(current.state);
    const revision = changed ? current.revision + 1 : current.revision;
    if (changed) {
      tx.set(currentRef, {
        ...publicProjection(next, revision),
        updatedBy: actor.uid,
        updatedByRole: actor.role,
      });
      tx.set(publicRef, publicProjection(next, revision));
      appendAuditEvent(tx, db, {
        actorAdminId: actor.uid,
        actorRole: actor.role,
        action: change.action,
        targetType: "app_config",
        targetId: APP_OPERATIONS_COLLECTION,
        requestId,
        metadata: {...change.metadata, revision},
      }, nowMs);
    }
    tx.create(markerRef, {command, revision, changed, actorAdminId: actor.uid, createdAt: FieldValue.serverTimestamp()});
    return {replay: false, revision, changed};
  });
}

export async function updateMaintenanceMode(
  deps: AdminDeps,
  actor: AdminActor,
  input: ChangeEnvelope & {enabled: boolean; message: string | null},
  requestId: string,
) {
  const result = await applyChange(deps, actor, requestId, "maintenance", input, (state) => {
    const before = state.maintenance;
    state.maintenance = {enabled: input.enabled, message: input.enabled ? input.message : null};
    return {
      action: input.enabled ? "APP_MAINTENANCE_ENABLED" : "APP_MAINTENANCE_DISABLED",
      metadata: {
        previousValue: {enabled: before.enabled, customMessage: before.message !== null},
        newValue: {enabled: state.maintenance.enabled, customMessage: state.maintenance.message !== null},
      },
    };
  });
  return {...result, maintenance: {enabled: input.enabled}};
}

export async function updateMinimumVersion(
  deps: AdminDeps,
  actor: AdminActor,
  input: ChangeEnvelope & {platform: AppPlatform; minimumVersion: string | null; recommendedVersion: string | null; updateUrl: string | null},
  requestId: string,
) {
  if (input.minimumVersion && input.recommendedVersion && compareVersions(input.recommendedVersion, input.minimumVersion) < 0) {
    throw new AdminError("invalid_argument", "recommended_below_minimum");
  }
  return applyChange(deps, actor, requestId, `version_${input.platform}`, input, (state) => {
    const previousValue = {
      minimumVersion: state.minimumVersion[input.platform],
      recommendedVersion: state.recommendedVersion[input.platform],
      updateUrl: state.updateUrl[input.platform],
    };
    state.minimumVersion[input.platform] = input.minimumVersion;
    state.recommendedVersion[input.platform] = input.recommendedVersion;
    state.updateUrl[input.platform] = input.updateUrl;
    return {
      action: "APP_MIN_VERSION_CHANGED",
      metadata: {
        platform: input.platform,
        previousValue,
        newValue: {minimumVersion: input.minimumVersion, recommendedVersion: input.recommendedVersion, updateUrl: input.updateUrl},
      },
    };
  });
}

export async function updateFeatureSwitch(
  deps: AdminDeps,
  actor: AdminActor,
  input: ChangeEnvelope & {feature: AppFeature; enabled: boolean; reason: string},
  requestId: string,
) {
  return applyChange(deps, actor, requestId, `feature_${input.feature}`, input, (state) => {
    const previous = state.features[input.feature];
    state.features[input.feature] = input.enabled;
    return {
      action: "APP_FEATURE_SWITCH_CHANGED",
      metadata: {feature: input.feature, previousValue: previous, newValue: input.enabled, reason: input.reason},
    };
  });
}

export async function updateAnnouncement(
  deps: AdminDeps,
  actor: AdminActor,
  input: ChangeEnvelope & {
    enabled: boolean;
    title: string | null;
    message: string | null;
    severity: AnnouncementSeverity;
    startsAtMs: number | null;
    expiresAtMs: number | null;
  },
  requestId: string,
) {
  const nowMs = deps.now();
  if (input.enabled) {
    if (!input.title || !input.message) {
      throw new AdminError("invalid_argument", "announcement_text");
    }
    // Announcements are short-lived by design: an end time is required and
    // bounded, so a forgotten banner cannot live forever.
    if (input.expiresAtMs === null || input.expiresAtMs <= nowMs) {
      throw new AdminError("invalid_argument", "expiresAt");
    }
    if (input.expiresAtMs - Math.max(nowMs, input.startsAtMs ?? nowMs) > MAX_ANNOUNCEMENT_DAYS * DAY_MS) {
      throw new AdminError("invalid_argument", "expiresAt_too_far");
    }
    if (input.startsAtMs !== null && input.startsAtMs >= input.expiresAtMs) {
      throw new AdminError("invalid_argument", "startsAt");
    }
  }
  return applyChange(deps, actor, requestId, "announcement", input, (state) => {
    const before = state.announcement;
    if (!input.enabled) {
      if (state.announcement) {
        state.announcement = {...state.announcement, enabled: false};
      }
    } else {
      const title = input.title as string;
      const message = input.message as string;
      state.announcement = {
        enabled: true,
        id: createHash("sha256").update(`${title}\n${message}`).digest("hex").slice(0, 16),
        title,
        message,
        severity: input.severity,
        startsAtMs: input.startsAtMs,
        expiresAtMs: input.expiresAtMs,
      };
    }
    const after = state.announcement;
    const summary = (a: typeof before) => (a
      ? {
        enabled: a.enabled,
        announcementId: a.id,
        severity: a.severity,
        titleChars: a.title.length,
        messageChars: a.message.length,
        startsAt: a.startsAtMs === null ? null : new Date(a.startsAtMs).toISOString(),
        expiresAt: a.expiresAtMs === null ? null : new Date(a.expiresAtMs).toISOString(),
      }
      : null);
    return {action: "APP_ANNOUNCEMENT_CHANGED", metadata: {previousValue: summary(before), newValue: summary(after)}};
  });
}
