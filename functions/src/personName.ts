import type {DocumentData} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

// One rule for a member's first and last name. Mirrors
// lib/features/profile/domain/validators/person_name_validator.dart, so the
// app and completeOnboarding agree on what a valid name is.
//
// Deliberately permissive: any script, accents, apostrophes, hyphens and
// multi-part names pass. A name only has to contain a letter and fit the cap.
export const MAX_FIRST_NAME_LENGTH = 40;
export const MAX_LAST_NAME_LENGTH = 50;

export type PersonNameIssue = "required" | "too-long";

const LETTER = /\p{L}/u;

export function personNameIssue(value: unknown, maxLength: number): PersonNameIssue | null {
  const name = typeof value === "string" ? value.trim() : "";
  if (!LETTER.test(name)) {
    return "required";
  }
  if (name.length > maxLength) {
    return "too-long";
  }
  return null;
}

/**
 * Name gate for finishing onboarding. The first name is the public
 * `profiles/{uid}.displayName`; the surname is `users/{uid}.lastName`, which
 * only its owner can read and which no member-facing projection copies.
 *
 * The error carries the field and the reason only — never the name itself.
 */
export function requireOnboardingNames(
  profile: DocumentData,
  account: DocumentData | undefined,
): void {
  const firstName = personNameIssue(profile.displayName, MAX_FIRST_NAME_LENGTH);
  if (firstName) {
    throw new HttpsError("failed-precondition", `first-name-${firstName}`);
  }
  const lastName = personNameIssue(account?.lastName, MAX_LAST_NAME_LENGTH);
  if (lastName) {
    throw new HttpsError("failed-precondition", `last-name-${lastName}`);
  }
}
