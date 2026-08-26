import type {Firestore} from "firebase-admin/firestore";

/**
 * Last-active window for new discovery / Music Match candidates.
 * Fixed 90 days (not calendar months) so timestamp math matches Firestore.
 * Missing lastActiveAt is treated as active (new / just-registered users).
 * Existing matches and messages are never deleted by this filter.
 * lastActiveAt is read from private users/{uid}, never from public profiles.
 */
export const DISCOVERY_ACTIVE_DAYS = 90;
export const DISCOVERY_ACTIVE_MS = DISCOVERY_ACTIVE_DAYS * 24 * 60 * 60 * 1000;

export function isActiveForDiscovery(
  lastActiveAt: unknown,
  nowMs: number = Date.now(),
): boolean {
  if (lastActiveAt == null) {
    return true;
  }
  const ms = toMillis(lastActiveAt);
  if (ms == null) {
    return true;
  }
  return nowMs - ms <= DISCOVERY_ACTIVE_MS;
}

export async function loadLastActiveAt(
  db: Firestore,
  uids: readonly string[],
): Promise<Map<string, unknown>> {
  const result = new Map<string, unknown>();
  const unique = [...new Set(uids.filter((id) => id.length > 0))];
  for (let i = 0; i < unique.length; i += 100) {
    const chunk = unique.slice(i, i + 100);
    const snaps = await db.getAll(...chunk.map((id) => db.doc(`users/${id}`)));
    for (const snap of snaps) {
      result.set(snap.id, snap.data()?.lastActiveAt);
    }
  }
  return result;
}

function toMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (value && typeof value === "object") {
    const record = value as {toMillis?: () => number; toDate?: () => Date};
    if (typeof record.toMillis === "function") {
      return record.toMillis();
    }
    if (typeof record.toDate === "function") {
      return record.toDate().getTime();
    }
  }
  return null;
}
