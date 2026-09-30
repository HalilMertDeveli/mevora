/**
 * App Operations config: the owner's controlled, server-authoritative switches
 * for the mobile app (maintenance, minimum versions, feature kill switches,
 * a plain-text announcement).
 *
 *   appOperationsConfig/current   full record + revision + who changed it.
 *                                 Server-only (rules deny every client).
 *   appOperationsConfig/public    the projection the app reads, world-readable
 *                                 so the gate works before sign-in. Written
 *                                 only by the admin commands, in the same
 *                                 transaction as `current`.
 *
 * This is not a settings store: only the fields below exist, and each is
 * changed by its own named, audited admin command.
 */

export const APP_OPERATIONS_COLLECTION = "appOperationsConfig";
export const APP_OPERATIONS_CURRENT = `${APP_OPERATIONS_COLLECTION}/current`;
export const APP_OPERATIONS_PUBLIC = `${APP_OPERATIONS_COLLECTION}/public`;
export const APP_OPERATIONS_SCHEMA_VERSION = 1;

/** Features that exist in the app today and can be switched off in an emergency. */
export const APP_FEATURES = ["boost", "calls", "spotify", "humorLab", "picks"] as const;
export type AppFeature = (typeof APP_FEATURES)[number];

export const APP_PLATFORMS = ["android", "ios"] as const;
export type AppPlatform = (typeof APP_PLATFORMS)[number];

export const ANNOUNCEMENT_SEVERITIES = ["info", "warning"] as const;
export type AnnouncementSeverity = (typeof ANNOUNCEMENT_SEVERITIES)[number];

export interface AppAnnouncement {
  enabled: boolean;
  /** Changes whenever the text changes, so a dismissal does not hide a new message. */
  id: string;
  title: string;
  message: string;
  severity: AnnouncementSeverity;
  startsAtMs: number | null;
  expiresAtMs: number | null;
}

export interface AppOperationsState {
  maintenance: {enabled: boolean; message: string | null};
  minimumVersion: Record<AppPlatform, string | null>;
  recommendedVersion: Record<AppPlatform, string | null>;
  updateUrl: Record<AppPlatform, string | null>;
  features: Record<AppFeature, boolean>;
  announcement: AppAnnouncement | null;
}

export function defaultAppOperationsState(): AppOperationsState {
  return {
    maintenance: {enabled: false, message: null},
    minimumVersion: {android: null, ios: null},
    recommendedVersion: {android: null, ios: null},
    updateUrl: {android: null, ios: null},
    // Every switch defaults to enabled: a missing or unreadable config never
    // takes a feature away.
    features: {boost: true, calls: true, spotify: true, humorLab: true, picks: true},
    announcement: null,
  };
}

function millis(value: unknown): number | null {
  if (value && typeof value === "object" && typeof (value as {toMillis?: unknown}).toMillis === "function") {
    return (value as {toMillis: () => number}).toMillis();
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  return null;
}

const str = (value: unknown): string | null => (typeof value === "string" && value.length > 0 ? value : null);

/** Tolerant reader: anything missing or malformed falls back to the default. */
export function parseAppOperationsState(data: Record<string, unknown> | undefined): AppOperationsState {
  const state = defaultAppOperationsState();
  if (!data) {
    return state;
  }
  const maintenance = (data.maintenance ?? {}) as Record<string, unknown>;
  state.maintenance = {enabled: maintenance.enabled === true, message: str(maintenance.message)};
  for (const key of ["minimumVersion", "recommendedVersion", "updateUrl"] as const) {
    const map = (data[key] ?? {}) as Record<string, unknown>;
    for (const platform of APP_PLATFORMS) {
      state[key][platform] = str(map[platform]);
    }
  }
  const features = (data.features ?? {}) as Record<string, unknown>;
  for (const feature of APP_FEATURES) {
    state.features[feature] = features[feature] !== false;
  }
  const a = data.announcement as Record<string, unknown> | null | undefined;
  if (a && typeof a === "object" && str(a.title) && str(a.message)) {
    state.announcement = {
      enabled: a.enabled === true,
      id: str(a.id) ?? "announcement",
      title: String(a.title),
      message: String(a.message),
      severity: a.severity === "warning" ? "warning" : "info",
      startsAtMs: millis(a.startsAt),
      expiresAtMs: millis(a.expiresAt),
    };
  }
  return state;
}
