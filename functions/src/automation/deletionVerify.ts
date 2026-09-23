import {getAuth} from "firebase-admin/auth";
import {getFirestore, type Firestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {logger} from "firebase-functions";
import {safeLogMeta} from "../security/logHygiene.js";

export type DeletionVerifyResult = {
  uid: string;
  complete: boolean;
  issues: string[];
  checkedAt: string;
};

export type DeletionVerifyInput = {
  uid: string;
  /** Ticket ids the deletion pass resolved as owned by `uid`, from the job payload. */
  supportTicketIds?: string[];
};

/** Injected so verification can be exercised without Auth and Storage. */
export type DeletionVerifyDeps = {
  authUserExists(uid: string): Promise<boolean>;
  prefixHasObjects(prefix: string): Promise<boolean>;
};

/** How many matches a single verification pass samples for un-erased messages. */
const MATCH_SAMPLE_LIMIT = 20;

/**
 * Documents `deleteUserAccount` removes last. Anything still present here means
 * the deletion transaction did not finish.
 */
const REMNANT_DOC_PATHS = (uid: string): string[] => [
  `users/${uid}`,
  `profiles/${uid}`,
  `userPreferences/${uid}`,
  `userSettings/${uid}`,
  `userPrivacy/${uid}`,
  `userLocation/${uid}`,
  `spotifySecrets/${uid}`,
  `authRateLimits/spotify_${uid}`,
];

/** Storage prefixes `deleteUserAccount` clears. */
const REMNANT_STORAGE_PREFIXES = (uid: string): string[] => [
  `users/${uid}/`,
  `profiles/${uid}/`,
];

const liveDeps: DeletionVerifyDeps = {
  async authUserExists(uid) {
    try {
      await getAuth().getUser(uid);
      return true;
    } catch (error) {
      // Only "no such user" proves the account is gone. Any other failure is an
      // infrastructure error and must not be reported as a clean deletion.
      const code = (error as {code?: string}).code ?? "";
      if (code === "auth/user-not-found") {
        return false;
      }
      throw error;
    }
  },
  async prefixHasObjects(prefix) {
    const [files] = await getStorage().bucket().getFiles({
      prefix,
      maxResults: 5,
      autoPaginate: false,
    });
    return files.length > 0;
  },
};

/**
 * Post-deletion verification: Auth gone, core docs gone, Storage empty, the
 * departed user's messages erased, their support attachments gone.
 *
 * Reports gaps only — it never deletes, so a partial deletion surfaces for repair
 * or manual review instead of being silently retried destructively.
 *
 * Deliberately does **not** flag records that are retained on purpose: matches and
 * their peer-authored messages (DL-2) and moderation reports (DL-3). Flagging
 * those would turn intentional retention into a permanent false failure.
 */
export async function verifyAccountDeletion(
  input: DeletionVerifyInput | string,
  db: Firestore = getFirestore(),
  deps: DeletionVerifyDeps = liveDeps,
): Promise<DeletionVerifyResult> {
  const {uid, supportTicketIds = []} =
    typeof input === "string" ? {uid: input, supportTicketIds: []} : input;
  const issues: string[] = [];

  try {
    if (await deps.authUserExists(uid)) {
      issues.push("auth_user_still_exists");
    }
  } catch (error) {
    logger.warn("deletion verify auth check failed", safeLogMeta({uid, error: String(error)}));
    issues.push("auth_check_failed");
  }

  for (const path of REMNANT_DOC_PATHS(uid)) {
    if ((await db.doc(path).get()).exists) {
      issues.push(`firestore_remnant:${path}`);
    }
  }

  const [likesFrom, likesTo, supportTickets] = await Promise.all([
    db.collection("likes").where("fromUserId", "==", uid).limit(1).get(),
    db.collection("likes").where("toUserId", "==", uid).limit(1).get(),
    db.collection("supportTickets").where("userId", "==", uid).limit(1).get(),
  ]);
  if (!likesFrom.empty) {
    issues.push("likes_from_remnant");
  }
  if (!likesTo.empty) {
    issues.push("likes_to_remnant");
  }
  if (!supportTickets.empty) {
    issues.push("support_ticket_remnant");
  }

  for (const prefix of REMNANT_STORAGE_PREFIXES(uid)) {
    try {
      if (await deps.prefixHasObjects(prefix)) {
        issues.push(`storage_remnant:${prefix}`);
      }
    } catch (error) {
      // A Storage outage must not be reported as a clean deletion.
      logger.warn(
        "deletion verify storage check failed",
        safeLogMeta({uid, prefix, error: String(error)}),
      );
      issues.push(`storage_check_failed:${prefix}`);
    }
  }

  // Support attachments sit outside the uid-scoped prefixes, so they are checked
  // by the ticket ids the deletion pass resolved as owned by this user.
  for (const ticketId of supportTicketIds) {
    const prefix = `support/${ticketId}/`;
    try {
      if (await deps.prefixHasObjects(prefix)) {
        issues.push(`support_attachment_remnant:${ticketId}`);
      }
    } catch (error) {
      logger.warn(
        "deletion verify support attachment check failed",
        safeLogMeta({uid, ticketId, error: String(error)}),
      );
      issues.push(`support_attachment_check_failed:${ticketId}`);
    }
  }

  issues.push(...(await unerasedMessageIssues(db, uid)));

  return {
    uid,
    complete: issues.length === 0,
    issues,
    checkedAt: new Date().toISOString(),
  };
}

/**
 * The match and the peer's messages are retained by design; the departed user's
 * own messages must be tombstoned. Sampled over a bounded number of matches —
 * this runs after the account is gone, so it is an audit, not a hot path.
 */
async function unerasedMessageIssues(db: Firestore, uid: string): Promise<string[]> {
  const matches = await db
    .collection("matches")
    .where("userIds", "array-contains", uid)
    .limit(MATCH_SAMPLE_LIMIT)
    .get();

  const issues: string[] = [];
  for (const match of matches.docs) {
    const authored = await match.ref
      .collection("messages")
      .where("senderId", "==", uid)
      .get();
    const live = authored.docs.filter((doc) => doc.get("deleted") !== true);
    if (live.length > 0) {
      issues.push(`message_content_remnant:${match.id}`);
    }
  }
  return issues;
}
