import {getStorage} from "firebase-admin/storage";
import {FieldValue, Timestamp, getFirestore, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";

const PENDING_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const ORPHAN_CHAT_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

type CleanupOptions = {
  dryRun: boolean;
  limit: number;
  requireAdminApproval?: boolean;
  adminUid?: string;
};

type CleanupResult = {
  scanned: number;
  deleted: number;
  skipped: number;
  candidates: Array<Record<string, unknown>>;
  dryRun: boolean;
};

function emptyResult(dryRun: boolean): CleanupResult {
  return {scanned: 0, deleted: 0, skipped: 0, candidates: [], dryRun};
}

/**
 * Delete stale profile pending uploads that never finalized moderation.
 * Never touches users/{uid}/profile/photos (published).
 */
export async function cleanupStalePendingUploads(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles({prefix: "users/", autoPaginate: false, maxResults: 1000});
  const cutoff = Date.now() - PENDING_MAX_AGE_MS;
  for (const file of files) {
    if (result.scanned >= options.limit) {
      break;
    }
    const name = file.name;
    if (!name.includes("/profile/pending/")) {
      continue;
    }
    result.scanned += 1;
    const updated = new Date(file.metadata.updated ?? file.metadata.timeCreated ?? 0).getTime();
    if (!updated || updated > cutoff) {
      result.skipped += 1;
      continue;
    }
    const parts = name.split("/");
    const uid = parts[1];
    if (!uid) {
      result.skipped += 1;
      continue;
    }
    result.candidates.push({path: name, uid, reason: "stale_pending"});
    if (!options.dryRun) {
      await file.delete({ignoreNotFound: true});
      result.deleted += 1;
    }
  }
  logger.info("cleanupStalePendingUploads", result);
  return result;
}

/**
 * Remove Storage under users/{uid}/ when Auth user and Firestore user are both gone.
 * Dry-run lists candidates only. Never deletes when users/{uid} still exists.
 */
export async function cleanupDeletedAccountStorageRemnants(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles({prefix: "users/", autoPaginate: false, maxResults: 2000});
  const uidPrefixes = new Map<string, string[]>();
  for (const file of files) {
    const parts = file.name.split("/");
    const uid = parts[1];
    if (!uid) {
      continue;
    }
    const list = uidPrefixes.get(uid) ?? [];
    list.push(file.name);
    uidPrefixes.set(uid, list);
  }
  for (const [uid, paths] of uidPrefixes) {
    if (result.scanned >= options.limit) {
      break;
    }
    result.scanned += 1;
    const userDoc = await db.doc(`users/${uid}`).get();
    if (userDoc.exists) {
      result.skipped += 1;
      continue;
    }
    result.candidates.push({uid, fileCount: paths.length, reason: "deleted_account_remnant"});
    if (!options.dryRun) {
      await Promise.all(
        paths.slice(0, 200).map((p) => bucket.file(p).delete({ignoreNotFound: true})),
      );
      result.deleted += paths.length;
    }
  }
  logger.info("cleanupDeletedAccountStorageRemnants", {
    dryRun: options.dryRun,
    scanned: result.scanned,
    deleted: result.deleted,
    skipped: result.skipped,
  });
  return result;
}

/**
 * Orphan chat media: Storage object older than retention with no matching message
 * referencing the path. Conservative — skips if match still active and message may exist.
 */
export async function cleanupOrphanChatMedia(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const bucket = getStorage().bucket();
  const [files] = await bucket.getFiles({prefix: "users/", autoPaginate: false, maxResults: 1000});
  const cutoff = Date.now() - ORPHAN_CHAT_MAX_AGE_MS;
  for (const file of files) {
    if (result.scanned >= options.limit) {
      break;
    }
    const name = file.name;
    // users/{uid}/chat/{matchId}/{fileId}
    const m = /^users\/([^/]+)\/chat\/([^/]+)\/(.+)$/.exec(name);
    if (!m) {
      continue;
    }
    result.scanned += 1;
    const [, uid, matchId, fileId] = m;
    const updated = new Date(file.metadata.updated ?? file.metadata.timeCreated ?? 0).getTime();
    if (!updated || updated > cutoff) {
      result.skipped += 1;
      continue;
    }
    const userExists = (await db.doc(`users/${uid}`).get()).exists;
    const matchSnap = await db.doc(`matches/${matchId}`).get();
    if (userExists && matchSnap.exists && matchSnap.data()?.isActive === true) {
      const messageId = fileId.replace(/\.[^.]+$/, "");
      const msg = await db.doc(`matches/${matchId}/messages/${messageId}`).get();
      if (msg.exists) {
        result.skipped += 1;
        continue;
      }
      if (Date.now() - updated < ORPHAN_CHAT_MAX_AGE_MS * 2) {
        result.skipped += 1;
        continue;
      }
    }
    result.candidates.push({path: name, uid, matchId, reason: "orphan_chat_media"});
    if (!options.dryRun) {
      await file.delete({ignoreNotFound: true});
      result.deleted += 1;
    }
  }
  logger.info("cleanupOrphanChatMedia", result);
  return result;
}

export async function cleanupOldNotifications(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const cutoff = Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
  const snap = await db
    .collection("notifications")
    .where("createdAt", "<", cutoff)
    .limit(options.limit)
    .get();
  result.scanned = snap.size;
  for (const doc of snap.docs) {
    result.candidates.push({id: doc.id, userId: doc.data().userId ?? null});
    if (!options.dryRun) {
      await doc.ref.delete();
      result.deleted += 1;
    }
  }
  return result;
}

export async function cleanupOldCalls(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const cutoff = Timestamp.fromDate(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000));
  const snap = await db.collection("calls").where("endedAt", "<", cutoff).limit(options.limit).get();
  result.scanned = snap.size;
  for (const doc of snap.docs) {
    result.candidates.push({id: doc.id});
    if (!options.dryRun) {
      await doc.ref.delete();
      result.deleted += 1;
    }
  }
  return result;
}

export async function cleanupOldAuditLogs(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  if (!options.dryRun && options.requireAdminApproval && !options.adminUid) {
    throw new Error("audit_log_cleanup_requires_admin");
  }
  const cutoff = Timestamp.fromDate(new Date(Date.now() - 180 * 24 * 60 * 60 * 1000));
  const snap = await db
    .collection("auditLogs")
    .where("timestamp", "<", cutoff)
    .limit(options.limit)
    .get();
  result.scanned = snap.size;
  for (const doc of snap.docs) {
    result.candidates.push({id: doc.id, action: doc.data().action ?? null});
    if (!options.dryRun) {
      await doc.ref.delete();
      result.deleted += 1;
    }
  }
  return result;
}

/** Mark soft-deleted / banned users non-discoverable (idempotent). */
export async function refreshDiscoverEligibilityBatch(
  options: CleanupOptions,
  db: Firestore = getFirestore(),
): Promise<CleanupResult> {
  const result = emptyResult(options.dryRun);
  const snap = await db
    .collection("profiles")
    .where("isDiscoverable", "==", true)
    .limit(options.limit)
    .get();
  for (const doc of snap.docs) {
    result.scanned += 1;
    const account = await db.doc(`users/${doc.id}`).get();
    const data = account.data() ?? {};
    const banned = data.isBanned === true || data.isSuspended === true;
    const missing = !account.exists;
    const status = String(data.accountStatus ?? "active");
    if (!banned && !missing && status !== "deleted") {
      result.skipped += 1;
      continue;
    }
    result.candidates.push({
      uid: doc.id,
      reason: missing ? "missing_user" : "banned_or_deleted",
    });
    if (!options.dryRun) {
      await doc.ref.set(
        {
          isDiscoverable: false,
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      result.deleted += 1;
    }
  }
  return result;
}
