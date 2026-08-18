import {getApps, initializeApp} from "firebase-admin/app";
import {
  FieldValue,
  Timestamp,
  getFirestore,
  type DocumentData,
} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {logger} from "firebase-functions";
import {blockId} from "./ids.js";
import {loadActiveBoostedUserIds, sortByBoostVisibility} from "./boost/ranking.js";
import {userLanguage} from "./language.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const enforceAppCheck = process.env.FUNCTIONS_EMULATOR !== "true";
const callableOptions = {
  enforceAppCheck,
  region: "europe-west1" as const,
};

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  return uid;
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const sLat = Math.sin(dLat / 2);
  const sLng = Math.sin(dLng / 2);
  const h =
    sLat * sLat + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * sLng * sLng;
  return 2 * 6371 * Math.asin(Math.sqrt(Math.min(1, Math.max(0, h))));
}

function distanceLabel(km: number, lang: "tr" | "en"): {label: string; labelEn: string} {
  const labelEn =
    km < 1 ? "Less than 1 km away" : km >= 100 ? "100+ km away" : `${Math.round(km)} km away`;
  const labelTr =
    km < 1 ? "1 km'den yakın" : km >= 100 ? "100+ km uzakta" : `${Math.round(km)} km uzakta`;
  return {label: lang === "tr" ? labelTr : labelEn, labelEn};
}

function compatibility(a: DocumentData, b: DocumentData) {
  const aInterests = new Set<string>((a.interests as string[]) ?? []);
  const shared = ((b.interests as string[]) ?? []).filter((item) => aInterests.has(item));
  const sharedScore = Math.min(25, shared.length * 5);
  const goalScore = a.relationshipGoal && a.relationshipGoal === b.relationshipGoal ? 20 : 0;
  const reasons: string[] = [];
  if (shared.length) reasons.push("Shared interests");
  if (goalScore) reasons.push("Same relationship goal");
  return {score: Math.round(sharedScore + goalScore), sharedInterests: shared, reasons};
}

async function isBlocked(a: string, b: string): Promise<boolean> {
  const [subA, subB, topA, topB] = await Promise.all([
    db.doc(`users/${a}/blockedUsers/${b}`).get(),
    db.doc(`users/${b}/blockedUsers/${a}`).get(),
    db.doc(`blocks/${blockId(a, b)}`).get(),
    db.doc(`blocks/${blockId(b, a)}`).get(),
  ]);
  return subA.exists || subB.exists || topA.exists || topB.exists;
}

export const getDiscoveryCandidates = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const allowedRadii = new Set([5, 10, 25, 50, 100]);
  const requested = Number(request.data?.radiusKm ?? 25);
  const radiusKm = allowedRadii.has(requested) ? requested : 25;
  const limit = Math.min(Math.max(Number(request.data?.limit ?? 10), 1), 20);
  const cursor = String(request.data?.cursor ?? "");
  const [prefsSnap, locationSnap, blockedSnap, likesSnap, passedSnap, boosted] = await Promise.all([
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.collection(`users/${uid}/blockedUsers`).get(),
    db.collection("likes").where("fromUserId", "==", uid).get(),
    db.collection(`users/${uid}/passedUsers`).get(),
    loadActiveBoostedUserIds(db),
  ]);
  const blocked = new Set(blockedSnap.docs.map((doc) => doc.id));
  const seen = new Set(likesSnap.docs.map((doc) => String(doc.get("toUserId") ?? "")));
  for (const doc of passedSnap.docs) seen.add(doc.id);
  seen.add(uid);
  const prefs = prefsSnap.data() ?? {};
  const lang = await userLanguage(uid);
  const minAge = Number(prefs.minAge ?? 18);
  const maxAge = Number(prefs.maxAge ?? 99);
  const origin = locationSnap.data();
  let query = db
    .collection("profiles")
    .where("isDiscoverable", "==", true)
    .where("profileCompleted", "==", true)
    .orderBy("updatedAt", "desc")
    .limit(40);
  if (cursor) {
    const cursorSnap = await db.doc(`profiles/${cursor}`).get();
    if (cursorSnap.exists) {
      query = query.startAfter(cursorSnap);
    }
  }
  const profiles = await query.get();
  const items: Array<Record<string, unknown>> = [];
  let lastUid: string | null = null;
  for (const doc of profiles.docs) {
    lastUid = doc.id;
    if (seen.has(doc.id) || blocked.has(doc.id)) continue;
    if (await isBlocked(uid, doc.id)) continue;
    const data = doc.data();
    const age = Number(data.age ?? 0);
    if (age && (age < minAge || age > maxAge)) continue;
    let distanceKm: number | null = null;
    let label: string | null = null;
    if (origin?.latitude != null && origin?.longitude != null) {
      const otherLoc = await db.doc(`userLocation/${doc.id}`).get();
      const other = otherLoc.data();
      if (other?.latitude != null && other?.longitude != null) {
        distanceKm = haversineKm(
          Number(origin.latitude),
          Number(origin.longitude),
          Number(other.latitude),
          Number(other.longitude),
        );
        if (distanceKm > radiusKm) continue;
        distanceKm = Math.round(distanceKm * 10) / 10;
        label = distanceLabel(distanceKm, lang).label;
      }
    }
    const compat = compatibility(prefs, data);
    items.push({
      uid: doc.id,
      profile: {
        uid: doc.id,
        displayName: data.displayName ?? "",
        age: data.age ?? null,
        gender: data.gender ?? null,
        bio: data.bio ?? null,
        photos: data.photos ?? [],
        interests: data.interests ?? [],
        relationshipGoal: data.relationshipGoal ?? null,
        city: data.city ?? null,
      },
      distanceLabel: label,
      distanceKm,
      compatibilityScore: compat.score,
      sharedInterests: compat.sharedInterests,
      compatibilityReasons: compat.reasons,
    });
  }
  const ranked = sortByBoostVisibility(items, boosted).slice(0, limit);
  const nextCursor = profiles.size === 40 ? lastUid : null;
  return {items: ranked, nextCursor};
});

export const getDiscoveryFeed = getDiscoveryCandidates;

export const recordDiscoveryDecision = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const candidateUid = String(request.data?.candidateUid ?? request.data?.targetUserId ?? "");
  const action = String(request.data?.action ?? "like");
  if (!candidateUid || candidateUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid candidate.");
  }
  if (await isBlocked(uid, candidateUid)) {
    throw new HttpsError("failed-precondition", "blocked");
  }
  if (action === "pass") {
    await db.doc(`users/${uid}/passedUsers/${candidateUid}`).set({
      toUserId: candidateUid,
      createdAt: FieldValue.serverTimestamp(),
    });
    await db.doc(`likes/${uid}_${candidateUid}`).set({
      fromUserId: uid,
      toUserId: candidateUid,
      action: "pass",
      createdAt: FieldValue.serverTimestamp(),
    });
    return {matched: false};
  }
  await db.doc(`likes/${uid}_${candidateUid}`).set({
    fromUserId: uid,
    toUserId: candidateUid,
    action: action === "superLike" ? "superLike" : "like",
    createdAt: FieldValue.serverTimestamp(),
  });
  const reverse = await db.doc(`likes/${candidateUid}_${uid}`).get();
  const reverseAction = reverse.data()?.action as string | undefined;
  const matched = reverse.exists && reverseAction !== "pass";
  if (!matched) {
    return {matched: false};
  }
  const matchId = [uid, candidateUid].sort().join("_");
  const matchRef = db.doc(`matches/${matchId}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(matchRef);
    if (snap.exists && snap.data()?.isActive === true) {
      return;
    }
    tx.set(matchRef, {
      userIds: [uid, candidateUid].sort(),
      createdAt: FieldValue.serverTimestamp(),
      lastMessage: null,
      lastMessageAt: FieldValue.serverTimestamp(),
      isActive: true,
      unmatchedBy: null,
      unmatchedAt: null,
      unreadCounts: {[uid]: 0, [candidateUid]: 0},
      isNewFor: {[uid]: true, [candidateUid]: true},
    });
  });
  return {matched: true, matchId};
});

export const getDistanceLabel = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const otherUid = String(request.data?.otherUid ?? "");
  if (!otherUid || otherUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid user.");
  }
  const [mine, other] = await Promise.all([
    db.doc(`userLocation/${uid}`).get(),
    db.doc(`userLocation/${otherUid}`).get(),
  ]);
  const a = mine.data();
  const b = other.data();
  if (!a || !b) {
    return {label: null};
  }
  const km = haversineKm(
    Number(a.latitude),
    Number(a.longitude),
    Number(b.latitude),
    Number(b.longitude),
  );
  const lang = await userLanguage(uid);
  const labels = distanceLabel(km, lang);
  return {label: labels.label, labelEn: labels.labelEn, kilometers: Math.round(km)};
});

export {deleteUserAccount} from "./deleteAccount.js";

export const exportMyData = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const [account, profile, prefs, settings, privacy, location, matches] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`userSettings/${uid}`).get(),
    db.doc(`userPrivacy/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.collection("matches").where("userIds", "array-contains", uid).get(),
  ]);
  return {
    exportedAt: new Date().toISOString(),
    uid,
    account: account.data() ?? null,
    profile: profile.data() ?? null,
    preferences: prefs.data() ?? null,
    settings: settings.data() ?? null,
    privacy: privacy.data() ?? null,
    location: {present: location.exists},
    matchIds: matches.docs.map((d) => d.id),
  };
});

export const onProfilePhotoUploaded = onObjectFinalized(
  {region: "europe-west1"},
  async (event) => {
    const name = event.data.name ?? "";
    if (!name.includes("/profile/pending/")) return;
    logger.info("Photo queued for moderation", {name});
  },
);

export const retentionCleanup = onSchedule(
  {schedule: "every 24 hours", region: "europe-west1"},
  async () => {
    const cutoff = Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
    const staleNotifications = await db
      .collection("notifications")
      .where("createdAt", "<", cutoff)
      .limit(400)
      .get();
    const batch = db.batch();
    for (const doc of staleNotifications.docs) batch.delete(doc.ref);
    const staleCalls = await db.collection("calls").where("endedAt", "<", cutoff).limit(200).get();
    for (const doc of staleCalls.docs) batch.delete(doc.ref);
    await batch.commit();
    logger.info("Retention cleanup complete", {
      notifications: staleNotifications.size,
      calls: staleCalls.size,
    });
  },
);

export const health = onCall(callableOptions, () => {
  return {status: "ok", service: "mevora"};
});

export const syncAuthAccount = onCall(callableOptions, async (request) => {
  const uid = requireUid(request);
  const record = await getAuth().getUser(uid);
  const phoneNumber = record.phoneNumber ?? null;
  await db.doc(`users/${uid}`).set(
    {
      uid,
      phoneNumber,
      phoneVerified: Boolean(phoneNumber),
      lastLoginAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return {ok: true};
});

