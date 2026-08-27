import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {isActiveForDiscovery, loadLastActiveAt} from "../discoveryActivity.js";
import {
  discoveryProfileRejectReason,
  loadActiveMatchPartnerIds,
  loadPreferencesByUid,
  passesGenderPreferences,
} from "../discoveryMatching.js";
import {passesSmokeDiscoveryIsolation} from "../smoke/smokeTestUsers.js";
import {
  BOOST_PRODUCT_IDS,
  SMART_BOOST_DURATION_MS,
  SMART_BOOST_MULTIPLIER,
} from "./config.js";
import {ensureDefaultCatalog} from "./catalog.js";
import {profileQualityFromDocs} from "./profileQuality.js";

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

/** Currently active for Smart Boost UI — last 30 minutes (server clock). */
export const SMART_ACTIVE_WINDOW_MS = 30 * 60 * 1000;
const PREVIEW_SCAN_LIMIT = 400;

function requireUid(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

function toMillis(value: unknown): number | null {
  if (value == null) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "object") {
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

export function isRecentlyActive(
  lastActiveAt: unknown,
  nowMs: number,
  windowMs: number = SMART_ACTIVE_WINDOW_MS,
): boolean {
  const ms = toMillis(lastActiveAt);
  if (ms == null) {
    return false;
  }
  return nowMs - ms <= windowMs;
}

async function loadExcludedIds(
  firestore: Firestore,
  uid: string,
): Promise<Set<string>> {
  const [likesSnap, passedSnap, matched, blockedSub, blockedSnap, blockerSnap] =
    await Promise.all([
      firestore.collection("likes").where("fromUserId", "==", uid).get(),
      firestore.collection(`users/${uid}/passedUsers`).get(),
      loadActiveMatchPartnerIds(firestore, uid),
      firestore.collection(`users/${uid}/blockedUsers`).get(),
      firestore.collection("blocks").where("blockerId", "==", uid).get(),
      firestore.collection("blocks").where("blockedUserId", "==", uid).get(),
    ]);
  const excluded = new Set<string>([uid, ...matched]);
  likesSnap.docs.forEach((doc) => {
    const to = String(doc.get("toUserId") ?? "");
    if (to) {
      excluded.add(to);
    }
  });
  passedSnap.docs.forEach((doc) => excluded.add(doc.id));
  blockedSub.docs.forEach((doc) => excluded.add(doc.id));
  blockedSnap.docs.forEach((doc) => {
    const other = String(doc.get("blockedUserId") ?? "");
    if (other) {
      excluded.add(other);
    }
  });
  blockerSnap.docs.forEach((doc) => {
    const other = String(doc.get("blockerId") ?? "");
    if (other) {
      excluded.add(other);
    }
  });
  return excluded;
}

/**
 * Real eligible-pool stats for the Smart Boost purchase screen.
 * Never invents scarcity — only returns counts from scanned profiles.
 */
export async function computeSmartBoostPreview(
  firestore: Firestore,
  uid: string,
  nowMs: number = Date.now(),
): Promise<{
  productId: string;
  packs: Array<{
    productId: string;
    durationMinutes: number;
    featured: boolean;
    title: string;
  }>;
  durationMinutes: number;
  multiplier: number;
  activeUserCount: number;
  suitableActiveCount: number;
  newUsersLast30m: number;
  profileQuality: ReturnType<typeof profileQualityFromDocs>;
  lowTraffic: boolean;
  hasActiveBoost: boolean;
  boostExpiresAt: string | null;
}> {
  const [
    viewerProfileSnap,
    viewerUserSnap,
    viewerPrefsSnap,
    musicSnap,
    answerSnap,
    activeBoostSnap,
    excluded,
  ] = await Promise.all([
    firestore.doc(`profiles/${uid}`).get(),
    firestore.doc(`users/${uid}`).get(),
    firestore.doc(`userPreferences/${uid}`).get(),
    firestore.doc(`users/${uid}/music/summary`).get(),
    firestore.collection(`users/${uid}/relationshipAnswers`).limit(20).get(),
    firestore
      .collection(`users/${uid}/boosts`)
      .where("status", "==", "active")
      .limit(5)
      .get(),
    loadExcludedIds(firestore, uid),
  ]);

  const viewerProfile = viewerProfileSnap.data() ?? {};
  const viewerUser = viewerUserSnap.data() ?? {};
  const prefs = viewerPrefsSnap.data() ?? {};
  const quality = profileQualityFromDocs({
    profile: viewerProfile,
    user: viewerUser,
    musicSummary: musicSnap.data() ?? null,
    personalityAnswerCount: answerSnap.size,
    nowMs,
  });

  let hasActiveBoost = false;
  let boostExpiresAt: string | null = null;
  for (const doc of activeBoostSnap.docs) {
    const expires = toMillis(doc.data().expiresAt);
    if (expires != null && expires > nowMs) {
      hasActiveBoost = true;
      boostExpiresAt = new Date(expires).toISOString();
      break;
    }
  }

  const minAge = Number(prefs.minAge ?? 18);
  const maxAge = Number(prefs.maxAge ?? 99);

  const profilesSnap = await firestore
    .collection("profiles")
    .where("isDiscoverable", "==", true)
    .where("profileCompleted", "==", true)
    .orderBy("updatedAt", "desc")
    .limit(PREVIEW_SCAN_LIMIT)
    .get();

  const candidateUids = profilesSnap.docs
    .map((d) => d.id)
    .filter((id) => !excluded.has(id));
  const [lastActiveByUid, preferencesByUid, accountSnaps] = await Promise.all([
    loadLastActiveAt(firestore, candidateUids),
    loadPreferencesByUid(firestore, candidateUids),
    candidateUids.length === 0
      ? Promise.resolve([])
      : firestore.getAll(
          ...candidateUids
            .slice(0, 200)
            .map((id) => firestore.doc(`users/${id}`)),
        ),
  ]);
  const accountsByUid = new Map(
    accountSnaps.map((snap) => [snap.id, snap.data() ?? {}]),
  );

  let activeUserCount = 0;
  let suitableActiveCount = 0;
  let newUsersLast30m = 0;

  for (const doc of profilesSnap.docs) {
    if (excluded.has(doc.id)) {
      continue;
    }
    const data = doc.data();
    const lastActive = lastActiveByUid.get(doc.id);
    const account = accountsByUid.get(doc.id) ?? {};

    if (!passesSmokeDiscoveryIsolation(viewerUser, account)) {
      continue;
    }
    if (!isActiveForDiscovery(lastActive, nowMs)) {
      continue;
    }

    const createdMs = toMillis(data.createdAt) ?? toMillis(data.updatedAt);
    if (createdMs != null && nowMs - createdMs <= SMART_ACTIVE_WINDOW_MS) {
      newUsersLast30m++;
    }

    const recentlyActive = isRecentlyActive(lastActive, nowMs);
    if (recentlyActive) {
      activeUserCount++;
    }

    const profileReject = discoveryProfileRejectReason({
      candidateProfile: data,
      candidateAccount: account,
      minAge,
      maxAge,
    });
    if (profileReject) {
      continue;
    }

    if (
      !passesGenderPreferences({
        viewerPrefs: prefs,
        viewerProfile,
        candidatePrefs: preferencesByUid.get(doc.id) ?? {},
        candidateProfile: data,
      })
    ) {
      continue;
    }

    if (recentlyActive) {
      suitableActiveCount++;
    }
  }

  return {
    productId: BOOST_PRODUCT_IDS.starter30m,
    packs: [
      {
        productId: BOOST_PRODUCT_IDS.starter30m,
        durationMinutes: Math.round(SMART_BOOST_DURATION_MS.starter30m / 60000),
        featured: false,
        title: "Starter",
      },
      {
        productId: BOOST_PRODUCT_IDS.popular1h,
        durationMinutes: Math.round(SMART_BOOST_DURATION_MS.popular1h / 60000),
        featured: true,
        title: "Popular",
      },
      {
        productId: BOOST_PRODUCT_IDS.power24h,
        durationMinutes: Math.round(SMART_BOOST_DURATION_MS.power24h / 60000),
        featured: false,
        title: "Power",
      },
    ],
    durationMinutes: Math.round(SMART_BOOST_DURATION_MS.starter30m / 60000),
    multiplier: SMART_BOOST_MULTIPLIER,
    activeUserCount,
    suitableActiveCount,
    newUsersLast30m,
    profileQuality: quality,
    lowTraffic: suitableActiveCount < 5,
    hasActiveBoost,
    boostExpiresAt,
  };
}

export const getSmartBoostPreview = onCall(callableOptions, async (request) => {
  const uid = requireUid(request.auth?.uid);
  await ensureDefaultCatalog(db);
  const preview = await computeSmartBoostPreview(db, uid);
  return {ok: true, ...preview};
});
