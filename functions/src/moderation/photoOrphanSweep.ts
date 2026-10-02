import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import type {Bucket} from "@google-cloud/storage";
import {logger} from "firebase-functions";
import {deletePhotoObjects} from "./deleteProfilePhoto.js";
import {computePhotoInvariants, unreferencedStampChanges} from "./photoInvariants.js";
import {
  LEDGER_COLLECTION,
  isLedgerFaceAnchor,
  isSweptWhenUnreferenced,
  ledgerRef,
  type LedgerEntry,
} from "./photoModerationLedger.js";
import {loadPhotoState, reconcilePhotoModeration} from "./photoModerationService.js";
import {PROCESSING_STALE_MS} from "./types.js";

/**
 * Deletes profile photos that left the profile without deleteProfilePhoto.
 *
 * App versions from before that callable — and any client talking to a backend
 * without it — remove a photo by rewriting profiles/{uid}.photos. Clients
 * cannot delete anything under photos/ or thumbs/, so the published original,
 * its variants, the pending upload and the ledger entry stay behind, the
 * original still reachable through its tokenised download URL.
 *
 * An id missing from the array is not a decision to delete: reconciliation
 * puts a removed last Face Anchor back, and a stale whole-array write can drop
 * a photo the next write restores. So nothing here reacts to one event.
 *
 *  - Mark: every pass over the photo invariants (commitPhotoInvariants) stamps
 *    `unreferencedSince` on a ledger entry whose photo is off the profile and
 *    clears it when the photo is back.
 *  - Sweep: once a day, entries stamped for longer than the grace period are
 *    looked at again, per member and inside a transaction, and deleted only if
 *    the photo is still off the profile, would not be put back, and is not a
 *    moderation record.
 *
 * The grace period is far longer than any of those transients. What it is
 * really for: if a defect ever dropped photos from profiles wholesale, this is
 * the time there is to notice before the sweep makes the loss permanent. The
 * per-run limit and the mode switch (photoOrphanSweepFunction.ts) are for the
 * same day.
 *
 * As in deleteProfilePhoto the ledger entry goes first, in the transaction
 * that checked, and the objects after it: an id written back into the array
 * later can then never be taken for the approved photo it once was. If an
 * object cannot be deleted it is left without an entry, logged, and out of
 * this sweep's reach.
 *
 * Entries that are `rejected` or `manual_review` are never stamped and never
 * swept. A photo with no ledger entry at all — removed before the ledger
 * existed — cannot be stamped and is not found here either.
 */

export const UNREFERENCED_GRACE_MS = 7 * 24 * 60 * 60 * 1000;

const PAGE_SIZE = 200;
/** Members whose photos one run may delete. Past it, the rest waits a day. */
const MAX_MEMBERS_PER_RUN = 200;

/**
 * `delete` — the sweep does its job.
 * `dry-run` — it reports what it would delete and writes nothing.
 * `off` — it does not run.
 */
export type PhotoOrphanSweepMode = "delete" | "dry-run" | "off";

/**
 * The mode a PHOTO_ORPHAN_SWEEP setting asks for. Unset means delete. A word
 * that is not one of the three is read as `dry-run`: a typo in the switch
 * someone reached for to stop the deleting must not leave it deleting.
 */
export function photoOrphanSweepModeFrom(setting: string | undefined): PhotoOrphanSweepMode {
  const word = (setting ?? "").trim().toLowerCase();
  if (word === "" || word === "on" || word === "delete") {
    return "delete";
  }
  return word === "off" ? "off" : "dry-run";
}

export interface PhotoOrphanSweepDeps {
  db: Firestore;
  bucket: () => Bucket;
  now: () => number;
}

export interface PhotoOrphanSweepOptions {
  mode?: PhotoOrphanSweepMode;
  graceMs?: number;
  pageSize?: number;
  maxMembers?: number;
}

export interface PhotoOrphanSweepResult {
  mode: PhotoOrphanSweepMode;
  /**
   * Ledger entries stamped for longer than the grace period that the run read.
   * A member's entries are handled together, so those deleted along with an
   * earlier one are never read and not counted.
   */
  scanned: number;
  members: number;
  /** Photos deleted, or in a dry run the photos that would be. */
  deleted: number;
  /** Photos whose ledger entry is gone but which still have a stored object. */
  incomplete: number;
  /** Members skipped because the pass over them failed. */
  failed: number;
  /** True when the per-run limit stopped the run with members left. */
  capped: boolean;
}

interface OrphanPhoto {
  imageId: string;
  storagePath: string | null;
}

function millisOf(value: unknown): number {
  const stamp = value as {toMillis?: () => number} | null | undefined;
  return typeof stamp?.toMillis === "function" ? stamp.toMillis() : 0;
}

function uidFromLedgerPath(path: string): string {
  // users/{uid}/photoModeration/{imageId}
  return path.split("/")[1] ?? "";
}

function isOrphan(entry: LedgerEntry, cutoffMs: number, nowMs: number): boolean {
  if (entry.unreferencedSince == null || millisOf(entry.unreferencedSince) > cutoffMs) {
    return false;
  }
  // The pipeline is on this photo right now and will write it back by id.
  if (entry.status === "processing" && nowMs - millisOf(entry.moderatedAt) < PROCESSING_STALE_MS) {
    return false;
  }
  // A verdict on an absent photo means the invariants have not been imposed
  // on what this transaction read. Not this run.
  return isSweptWhenUnreferenced(entry) && !isLedgerFaceAnchor(entry);
}

/**
 * The orphans of one member as a single transaction sees them, with their
 * ledger entries deleted in it unless this is a dry run.
 */
async function collectOrphans(
  db: Firestore,
  uid: string,
  cutoffMs: number,
  nowMs: number,
  dryRun: boolean,
): Promise<OrphanPhoto[]> {
  return db.runTransaction(async (tx) => {
    const state = await loadPhotoState(tx, db, uid);
    // Stamps are only written against a profile. Without one there is nothing
    // to hold the entries up to; account deletion removes them.
    if (!state.exists) {
      return [];
    }
    // Absent from the array the invariants produce, not from the stored one:
    // a last anchor reconciliation is about to put back is on the profile.
    const present = new Set(
      computePhotoInvariants(state.photos, state.ledger).photos.map((photo) => String(photo.id ?? "")));
    const orphans: OrphanPhoto[] = [];
    for (const [imageId, entry] of state.ledger) {
      if (present.has(imageId) || !isOrphan(entry, cutoffMs, nowMs)) {
        continue;
      }
      orphans.push({imageId, storagePath: entry.storagePath ?? null});
      if (!dryRun) {
        tx.delete(ledgerRef(db, uid, imageId));
      }
    }
    return orphans;
  });
}

export async function sweepUnreferencedPhotos(
  deps: PhotoOrphanSweepDeps,
  options: PhotoOrphanSweepOptions = {},
): Promise<PhotoOrphanSweepResult> {
  const {db} = deps;
  const mode = options.mode ?? "delete";
  const result: PhotoOrphanSweepResult = {
    mode,
    scanned: 0,
    members: 0,
    deleted: 0,
    incomplete: 0,
    failed: 0,
    capped: false,
  };
  if (mode === "off") {
    return result;
  }
  const dryRun = mode === "dry-run";
  const pageSize = options.pageSize ?? PAGE_SIZE;
  const maxMembers = options.maxMembers ?? MAX_MEMBERS_PER_RUN;
  const nowMs = deps.now();
  const cutoffMs = nowMs - (options.graceMs ?? UNREFERENCED_GRACE_MS);
  const due = db.collectionGroup(LEDGER_COLLECTION)
    .where("unreferencedSince", "<=", Timestamp.fromMillis(cutoffMs))
    .orderBy("unreferencedSince", "asc");

  const seen = new Set<string>();
  let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
  paging: for (;;) {
    const page: FirebaseFirestore.QuerySnapshot = await (last ? due.startAfter(last) : due).limit(pageSize).get();
    for (const doc of page.docs) {
      result.scanned += 1;
      const uid = uidFromLedgerPath(doc.ref.path);
      if (!uid || seen.has(uid)) {
        continue;
      }
      if (seen.size >= maxMembers) {
        result.capped = true;
        break paging;
      }
      seen.add(uid);
      result.members += 1;
      try {
        if (!dryRun) {
          // Whatever reconciliation would do for this profile is done first —
          // put a last anchor back, give up a stale one, clear the stamp of a
          // photo that returned — so the transaction below judges a profile
          // the rules have been imposed on, and a stamp that should not be
          // there does not stay at the head of this query.
          await reconcilePhotoModeration(db, uid, deps.bucket());
        }
        const orphans = await collectOrphans(db, uid, cutoffMs, nowMs, dryRun);
        for (const orphan of orphans) {
          if (dryRun) {
            result.deleted += 1;
            logger.info("Unreferenced profile photo would be deleted", {uid, imageId: orphan.imageId});
            continue;
          }
          const failures = await deletePhotoObjects(deps.bucket(), uid, orphan.imageId, orphan.storagePath);
          if (failures > 0) {
            result.incomplete += 1;
            logger.error("Swept profile photo still has stored objects", {
              uid,
              imageId: orphan.imageId,
              failures,
            });
          } else {
            result.deleted += 1;
            logger.info("Unreferenced profile photo deleted", {uid, imageId: orphan.imageId});
          }
        }
      } catch (error) {
        result.failed += 1;
        logger.error("Photo orphan sweep failed for a member", {
          uid,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }
    if (page.size < pageSize) {
      break;
    }
    last = page.docs[page.docs.length - 1];
  }
  if (result.capped) {
    logger.warn("Photo orphan sweep stopped at its per-run limit", {...result});
  }
  return result;
}

export interface UnreferencedStampResult {
  stamped: string[];
  cleared: string[];
}

/**
 * Brings one member's `unreferencedSince` stamps in line with their profile
 * and writes nothing else — no photo, no status, no profile field.
 *
 * A profile is only marked when something writes it, so photos that were
 * orphaned before the mark existed stay unmarked until the member next edits
 * their profile. This is the catch-up for those (tool/
 * stampUnreferencedProfilePhotos.cjs). It deletes nothing: what it stamps
 * waits out the same grace period and goes through the same sweep.
 */
export async function stampUnreferencedPhotos(
  db: Firestore,
  uid: string,
  options: {dryRun?: boolean} = {},
): Promise<UnreferencedStampResult> {
  return db.runTransaction(async (tx) => {
    const state = await loadPhotoState(tx, db, uid);
    const result: UnreferencedStampResult = {stamped: [], cleared: []};
    if (!state.exists) {
      return result;
    }
    const photos = computePhotoInvariants(state.photos, state.ledger).photos;
    for (const [imageId, unreferenced] of unreferencedStampChanges(photos, state.ledger)) {
      (unreferenced ? result.stamped : result.cleared).push(imageId);
      if (!options.dryRun) {
        tx.update(ledgerRef(db, uid, imageId), {
          unreferencedSince: unreferenced ? FieldValue.serverTimestamp() : FieldValue.delete(),
        });
      }
    }
    return result;
  });
}
