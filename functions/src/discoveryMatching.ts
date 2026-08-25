import {type DocumentData, type Firestore} from "firebase-admin/firestore";
import {interestedInAllows} from "./musicCompatibility.js";
import {
  countUsableDiscoveryPhotos,
  isAccountEligible,
  isAdultProfile,
  isProfileDiscoverable,
  MIN_PROFILE_PHOTOS,
  resolveProfileAge,
} from "./profileSafety.js";

export function datingPreference(
  prefs: DocumentData,
  profile: DocumentData,
): unknown {
  return (
    prefs.preferredGender ||
    prefs.showMe ||
    prefs.interestedIn ||
    profile.interestedIn
  );
}

export function passesGenderPreferences(options: {
  viewerPrefs: DocumentData;
  viewerProfile: DocumentData;
  candidatePrefs: DocumentData;
  candidateProfile: DocumentData;
}): boolean {
  const viewerGender = options.viewerProfile.gender;
  const viewerWant = datingPreference(options.viewerPrefs, options.viewerProfile);
  const candidateWant = datingPreference(
    options.candidatePrefs,
    options.candidateProfile,
  );
  return (
    interestedInAllows(viewerWant, options.candidateProfile.gender) &&
    interestedInAllows(candidateWant, viewerGender)
  );
}

export function discoveryProfileRejectReason(options: {
  candidateProfile: DocumentData | undefined;
  candidateAccount: DocumentData | undefined;
  minAge: number;
  maxAge: number;
}): string | null {
  const data = options.candidateProfile;
  if (!isProfileDiscoverable(data)) {
    if (!data) return "profile_missing";
    if (data.isDiscoverable !== true) return "not_discoverable";
    if (data.profileCompleted !== true) return "profile_incomplete";
    const moderationStatus = String(
      data.profileModerationStatus ?? data.moderationStatus ?? "approved",
    );
    if (
      moderationStatus === "suspended" ||
      moderationStatus === "rejected" ||
      moderationStatus === "manual_review"
    ) {
      return `profile_moderation_${moderationStatus}`;
    }
    return "underage_or_undiscoverable";
  }
  if (!isAccountEligible(options.candidateAccount)) {
    return "account_ineligible";
  }
  if (!isAdultProfile(data)) {
    return "underage";
  }
  const age = resolveProfileAge(data);
  if (age === null || age < 18 || age < options.minAge || age > options.maxAge) {
    return "age_filter";
  }
  if (countUsableDiscoveryPhotos(data?.photos) < MIN_PROFILE_PHOTOS) {
    return "photos_insufficient";
  }
  return null;
}

export function passesDiscoveryProfileFilters(options: {
  candidateProfile: DocumentData | undefined;
  candidateAccount: DocumentData | undefined;
  minAge: number;
  maxAge: number;
}): boolean {
  return discoveryProfileRejectReason(options) === null;
}

export async function loadActiveMatchPartnerIds(
  db: Firestore,
  uid: string,
): Promise<Set<string>> {
  const snap = await db
    .collection("matches")
    .where("userIds", "array-contains", uid)
    .where("isActive", "==", true)
    .get();
  const partners = new Set<string>();
  for (const doc of snap.docs) {
    for (const other of (doc.get("userIds") as string[]) ?? []) {
      if (other && other !== uid) {
        partners.add(other);
      }
    }
  }
  return partners;
}

export async function loadPreferencesByUid(
  db: Firestore,
  uids: string[],
): Promise<Map<string, DocumentData>> {
  const unique = [...new Set(uids.filter(Boolean))];
  if (!unique.length) {
    return new Map();
  }
  const refs = unique.map((uid) => db.doc(`userPreferences/${uid}`));
  const snaps = await db.getAll(...refs);
  const map = new Map<string, DocumentData>();
  for (const snap of snaps) {
    if (snap.exists) {
      map.set(snap.id, snap.data() ?? {});
    }
  }
  return map;
}
