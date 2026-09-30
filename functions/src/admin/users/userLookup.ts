import {FieldValue, type DocumentData, type Firestore} from "firebase-admin/firestore";

/**
 * `adminUserLookup/{uid}` — the one search index the admin console needs that
 * Firestore cannot answer directly: case- and accent-insensitive display-name
 * prefix search.
 *
 * It deliberately holds no contact data. Email and phone lookups go to
 * Firebase Auth (exact match only, so the console cannot be used to enumerate
 * addresses by prefix); the index carries just the folded name and enough to
 * sort. Maintained by the `syncAdminUserLookup` profile trigger and deleted
 * with the account.
 */
export const LOOKUP_COLLECTION = "adminUserLookup";

const TURKISH_FOLD: Record<string, string> = {
  "ı": "i",
  "İ": "i",
  "ş": "s",
  "Ş": "s",
  "ğ": "g",
  "Ğ": "g",
  "ç": "c",
  "Ç": "c",
  "ö": "o",
  "Ö": "o",
  "ü": "u",
  "Ü": "u",
};

/** Lowercase, Turkish-aware, diacritic-free, single-spaced. */
export function foldSearchText(value: string): string {
  return value
    .replace(/[ıİşŞğĞçÇöÖüÜ]/g, (ch) => TURKISH_FOLD[ch] ?? ch)
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 80);
}

export function lookupDocFor(uid: string, profile: DocumentData | undefined): Record<string, unknown> | null {
  const name = typeof profile?.displayName === "string" ? profile.displayName : "";
  const folded = foldSearchText(name);
  if (!folded) {
    return null;
  }
  return {
    uid,
    displayNameLower: folded,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Keeps one lookup row in step with its profile. Writes only when the folded
 * name actually changed, so the far more frequent profile writes (photos,
 * reconciliation) cost a single read here and nothing else.
 */
export async function syncLookupForProfile(
  db: Firestore,
  uid: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): Promise<"written" | "deleted" | "unchanged"> {
  const ref = db.doc(`${LOOKUP_COLLECTION}/${uid}`);
  if (!after) {
    await ref.delete();
    return "deleted";
  }
  const next = lookupDocFor(uid, after);
  const previousName = foldSearchText(String(before?.displayName ?? ""));
  if (!next) {
    if (previousName) {
      await ref.delete();
      return "deleted";
    }
    return "unchanged";
  }
  if (before && previousName === next.displayNameLower) {
    return "unchanged";
  }
  await ref.set(next, {merge: true});
  return "written";
}
