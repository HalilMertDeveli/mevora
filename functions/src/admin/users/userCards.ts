import type {DocumentData, Firestore} from "firebase-admin/firestore";
import {approvedPhotos, effectiveAccountStatus} from "../../profileSafety.js";

/**
 * The minimum a queue row needs to say who a user is. No email, no phone, no
 * location: those belong to the sensitive overview only.
 */
export interface UserCard {
  uid: string;
  exists: boolean;
  displayName: string | null;
  accountStatus: string;
  isVerified: boolean;
  photoUrl: string | null;
}

export function userCardFrom(
  uid: string,
  account: DocumentData | undefined,
  profile: DocumentData | undefined,
  nowMs: number,
): UserCard {
  const photos = approvedPhotos(profile?.photos);
  const primary = photos.find((photo) => photo.isPrimary === true) ?? photos[0];
  return {
    uid,
    exists: Boolean(account || profile),
    displayName: (profile?.displayName ?? account?.displayName ?? null) as string | null,
    accountStatus: account ? effectiveAccountStatus(account, nowMs) : (profile ? "active" : "unknown"),
    isVerified: account?.isVerified === true,
    photoUrl: typeof primary?.downloadUrl === "string" ? primary.downloadUrl : null,
  };
}

/** Hydrates up to 100 cards with two batched reads. */
export async function loadUserCards(
  db: Firestore,
  uids: Iterable<string | null | undefined>,
  nowMs: number,
): Promise<Map<string, UserCard>> {
  const unique = [...new Set([...uids].filter((u): u is string => typeof u === "string" && u.length > 0))]
    .slice(0, 100);
  const out = new Map<string, UserCard>();
  if (!unique.length) {
    return out;
  }
  const [accounts, profiles] = await Promise.all([
    db.getAll(...unique.map((u) => db.doc(`users/${u}`))),
    db.getAll(...unique.map((u) => db.doc(`profiles/${u}`))),
  ]);
  unique.forEach((u, index) => {
    out.set(u, userCardFrom(u, accounts[index]?.data(), profiles[index]?.data(), nowMs));
  });
  return out;
}

/** "a***@example.com" — enough to confirm, not enough to contact. */
export function maskEmail(email: unknown): string | null {
  if (typeof email !== "string" || !email.includes("@")) {
    return null;
  }
  const [local, domain] = email.split("@");
  return `${local.slice(0, 1)}***@${domain}`;
}

/** "+90 *** *** 12 34" style: country code and last four only. */
export function maskPhone(phone: unknown): string | null {
  if (typeof phone !== "string" || phone.length < 6) {
    return null;
  }
  return `${phone.slice(0, 3)}******${phone.slice(-4)}`;
}
