import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {loadActiveMatchPartnerIds} from "./discoveryMatching.js";
import {shapeIncomingLikesResponse, type IncomingLikeItem} from "./incomingLikesShape.js";
import {buildCompatibilitySnapshotFromProfiles} from "./compatibility/compatibilitySnapshot.js";
import {isUserPremium} from "./premium.js";
import {usableDiscoveryPhotos} from "./profileSafety.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};

const POSITIVE_ACTIONS = new Set(["like", "superLike"]);
const RESULT_LIMIT = 40;

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

function photoUrlFromProfile(data: Record<string, unknown>): string | null {
  const usable = usableDiscoveryPhotos(data.photos);
  if (usable.length > 0) {
    const first = usable[0];
    const url = first.downloadUrl ?? first.url ?? first.photoUrl;
    if (typeof url === "string" && url.length > 0) {
      return url;
    }
  }
  if (typeof data.photoUrl === "string" && data.photoUrl.length > 0) {
    return data.photoUrl;
  }
  return null;
}

/**
 * Incoming likes (admirers) — premium-gated on the server.
 *
 * Free: count + locked/premiumRequired metadata only — no liker UIDs/profiles.
 * Premium: real profile previews for users who liked the viewer and are not
 * already matched, enriched with the same calculateCompatibility() engine as
 * Discovery (profile signals only — no per-row music/relationship N+1 reads).
 *
 * Clients must never query likes by toUserId (Firestore rules forbid it).
 * Mutual matches remain on the matches collection and are not premium-gated.
 */
export const getIncomingLikes = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth?.uid);
  const premium = await isUserPremium(uid);

  const likesSnap = await db
    .collection("likes")
    .where("toUserId", "==", uid)
    .orderBy("createdAt", "desc")
    .limit(80)
    .get();

  const matched = await loadActiveMatchPartnerIds(db, uid);
  const positive: Array<{fromUserId: string; action: string; createdAtMs: number | null}> = [];
  for (const doc of likesSnap.docs) {
    const data = doc.data();
    const action = String(data.action ?? "");
    if (!POSITIVE_ACTIONS.has(action)) {
      continue;
    }
    const fromUserId = String(data.fromUserId ?? "");
    if (!fromUserId || fromUserId === uid || matched.has(fromUserId)) {
      continue;
    }
    const createdAt = data.createdAt;
    const createdAtMs =
      createdAt && typeof createdAt.toMillis === "function"
        ? createdAt.toMillis()
        : null;
    positive.push({fromUserId, action, createdAtMs});
  }

  // Dedupe by fromUserId (keep newest).
  const seen = new Set<string>();
  const unique = positive.filter((row) => {
    if (seen.has(row.fromUserId)) {
      return false;
    }
    seen.add(row.fromUserId);
    return true;
  });

  if (!premium) {
    return shapeIncomingLikesResponse({
      isPremium: false,
      rows: unique,
      profiles: new Map(),
    });
  }

  const slice = unique.slice(0, RESULT_LIMIT);
  const viewerProfileSnap = await db.doc(`profiles/${uid}`).get();
  const viewerProfile = viewerProfileSnap.data() ?? {};

  const profiles = new Map<string, IncomingLikeItem>();
  for (const row of slice) {
    const profileSnap = await db.doc(`profiles/${row.fromUserId}`).get();
    if (!profileSnap.exists) {
      continue;
    }
    const data = profileSnap.data() ?? {};
    if (data.isDiscoverable === false) {
      continue;
    }
    const item: IncomingLikeItem = {
      uid: row.fromUserId,
      displayName: String(data.displayName ?? ""),
      age: data.age == null ? null : Number(data.age),
      photoUrl: photoUrlFromProfile(data),
      city: typeof data.city === "string" ? data.city : null,
      action: row.action,
      createdAtMs: row.createdAtMs,
    };
    try {
      // Viewer = likes-you recipient; candidate = liker.
      // Same engine as Discovery; music/relationship omitted to avoid N+1.
      const snap = buildCompatibilitySnapshotFromProfiles({
        viewerProfile,
        candidateProfile: data,
        relationship: null,
        musicScore: null,
      });
      if (snap.compatibilityScore > 0) {
        item.compatibilityScore = snap.compatibilityScore;
        item.compatibilityBreakdown = snap.compatibilityBreakdown;
        item.sharedInterests = snap.sharedInterests;
        item.compatibilityReasons = snap.compatibilityReasons;
      }
    } catch {
      // Leave compatibility fields absent — UI stays null-safe.
    }
    profiles.set(row.fromUserId, item);
  }

  return shapeIncomingLikesResponse({
    isPremium: true,
    rows: unique,
    profiles,
  });
});
