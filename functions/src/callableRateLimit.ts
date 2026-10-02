import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

export const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
export const RATE_LIMIT_MAX = 20;

/**
 * The counters whose document id is a member's uid: the Spotify sign-in
 * (`spotify_<uid>`, spotifyAuth.ts) and link (`spotify_link_<uid>`,
 * spotifyMusic.ts) budgets. Nothing expires them, so account deletion removes
 * them and its verification checks them. A key added for a signed-in caller
 * belongs here too.
 */
export function uidRateLimitPaths(uid: string): string[] {
  return [`authRateLimits/spotify_${uid}`, `authRateLimits/spotify_link_${uid}`];
}

/**
 * Decides what a fixed-window counter should do next.
 *
 * Kept pure so the window edges and the refusal are testable without a
 * Firestore round trip.
 */
export function rateLimitDecision(
  existing: {windowStart?: unknown; count?: unknown} | null,
  now: number,
  windowMs: number = RATE_LIMIT_WINDOW_MS,
  max: number = RATE_LIMIT_MAX,
): {action: "start" | "increment" | "refuse"; count: number; windowStart: number} {
  const data = existing ?? {};
  const started = typeof data.windowStart === "number" ? data.windowStart : null;
  const count = typeof data.count === "number" ? data.count : 0;
  // No window, an unreadable one, or one that has run out: begin a new one.
  // A corrupt document must open a window rather than be read as an empty
  // budget that never fills.
  if (started === null || now - started > windowMs) {
    return {action: "start", count: 1, windowStart: now};
  }
  if (count >= max) {
    return {action: "refuse", count, windowStart: started};
  }
  return {action: "increment", count: count + 1, windowStart: started};
}

/**
 * Spends one unit of a caller's budget, or refuses.
 *
 * The OAuth callables sit in front of a third party that charges us for every
 * request and hands out one-time codes; without this, a loop in a client — or
 * someone replaying a callback — walks straight through to Spotify.
 */
export async function consumeRateLimit(key: string): Promise<void> {
  const ref = db.doc(`authRateLimits/${key}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const decision = rateLimitDecision(snap.data() ?? null, Date.now());
    if (decision.action === "refuse") {
      throw new HttpsError("resource-exhausted", "too-many-requests");
    }
    tx.set(ref, {
      windowStart: decision.windowStart,
      count: decision.count,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}
