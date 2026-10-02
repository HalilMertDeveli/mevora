import {FieldValue, Timestamp, type Firestore} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {logger} from "firebase-functions";
import {rateLimitDecision} from "../callableRateLimit.js";
import {isAccountEligible} from "../profileSafety.js";
import {safeLogMeta} from "../security/logHygiene.js";
import {
  isLedgerFaceAnchor,
  isPublishedStoragePath,
  ledgerEntryFromData,
  ledgerRef,
  type FaceAnchorLedgerState,
  type LedgerEntry,
} from "../moderation/photoModerationLedger.js";
import {commitPhotoInvariants, loadPhotoState} from "../moderation/photoModerationService.js";
import {
  ATTEMPT_TTL_MS,
  FACE_ANCHOR_CONSENT_VERSION,
  FACE_ANCHOR_SCHEMA_VERSION,
  MAX_SELFIE_BYTES,
  SELFIE_MAX_AGE_MS,
  SELFIE_PREFIX,
  budgetDecision,
  faceAnchorStatePath,
  isProcessingFresh,
  isTerminal,
  parseFaceAnchorState,
  parseSelfiePath,
  refundedCounters,
  selfiePath,
  usageDayKey,
  type FaceAnchorReason,
  type FaceAnchorStateDoc,
  type FaceAnchorStatus,
} from "./faceAnchorRecord.js";
import {contentHash, looksLikeImage} from "./images.js";
import {FaceProviderError, type FaceVerificationProvider} from "./provider.js";

/**
 * Face Anchor verification: does this live member match this profile photo?
 *
 * Two calls. `start` opens an attempt for one approved photo and tells the app
 * where to put a freshly captured selfie. `submit` runs liveness, then a 1:1
 * face match between that selfie and the published photo, and — only on a
 * match — records the verdict on the photo's moderation ledger entry.
 *
 * The app decides nothing: it names a photo and an attempt, both of which are
 * checked against the caller's own documents. The verdict is written by this
 * module alone, and the selfie is deleted on every way out.
 */

/** The Storage surface this module uses; the Admin SDK bucket satisfies it. */
export interface FaceAnchorBucket {
  file(path: string): {
    exists(): Promise<[boolean]>;
    download(options?: {validation?: boolean}): Promise<[Buffer]>;
    getMetadata(): Promise<[Record<string, unknown>]>;
    delete(options?: {ignoreNotFound?: boolean}): Promise<unknown>;
  };
  getFiles(options: {
    prefix: string;
    maxResults?: number;
    autoPaginate?: boolean;
    pageToken?: string;
  }): Promise<unknown[]>;
}

export interface FaceAnchorDeps {
  db: Firestore;
  bucket: () => FaceAnchorBucket;
  /** Null when verification cannot run here. Chosen server-side only. */
  provider: () => FaceVerificationProvider | null;
  now: () => number;
  newAttemptId: () => string;
  /** Re-encodes an image for the provider; throws on undecodable bytes. */
  normalizeImage: (bytes: Buffer) => Promise<Buffer>;
  dailyGlobalCap: () => number;
  /** Runs moderation for a photo whose upload trigger was missed. Best effort. */
  moderatePending: (uid: string, imageId: string) => Promise<void>;
}

export interface FaceAnchorView {
  status: FaceAnchorStatus;
  reason: FaceAnchorReason | null;
  photoId: string | null;
}

const START_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const START_LIMIT_MAX = 20;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

function cleanId(raw: unknown): string {
  const value = typeof raw === "string" ? raw.trim() : "";
  return ID_PATTERN.test(value) ? value : "";
}

function view(state: FaceAnchorStateDoc): FaceAnchorView {
  return {
    status: state.status === "none" ? "expired" : state.status,
    reason: state.reason,
    photoId: state.photoId,
  };
}

function unavailable(): HttpsError {
  return new HttpsError("failed-precondition", "face-anchor-unavailable");
}

async function deleteSelfie(deps: FaceAnchorDeps, uid: string, attemptId: string): Promise<void> {
  try {
    await deps.bucket().file(selfiePath(uid, attemptId)).delete({ignoreNotFound: true});
  } catch (error) {
    // The sweep removes it by age; nothing else may be said about it here.
    logger.warn("face anchor: selfie delete deferred to sweep", safeLogMeta({
      error: error instanceof Error ? error.name : "unknown",
    }));
  }
}

async function readLedgerEntry(db: Firestore, uid: string, imageId: string): Promise<LedgerEntry | null> {
  const snap = await ledgerRef(db, uid, imageId).get();
  return snap.exists ? ledgerEntryFromData(snap.data() ?? {}) : null;
}

/** A cheap ceiling on how often an attempt can be opened; opening is free. */
async function consumeStartLimit(db: Firestore, uid: string, nowMs: number): Promise<void> {
  const ref = db.doc(`users/${uid}/rateLimits/faceAnchorStart`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const decision = rateLimitDecision(snap.data() ?? null, nowMs, START_LIMIT_WINDOW_MS, START_LIMIT_MAX);
    if (decision.action === "refuse") {
      throw new HttpsError("resource-exhausted", "too-many-requests");
    }
    tx.set(ref, {
      windowStart: decision.windowStart,
      count: decision.count,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export async function startFaceAnchorVerification(
  deps: FaceAnchorDeps,
  uid: string,
  input: {photoId?: unknown; consentVersion?: unknown},
): Promise<{attemptId: string; uploadPath: string; expiresAtMs: number; status: FaceAnchorStatus}> {
  const {db} = deps;
  const photoId = cleanId(input.photoId);
  if (!photoId) {
    throw new HttpsError("invalid-argument", "photo-id-required");
  }
  // A selfie is biometric data. No attempt opens without the member having
  // agreed to the current wording.
  if (input.consentVersion !== FACE_ANCHOR_CONSENT_VERSION) {
    throw new HttpsError("failed-precondition", "consent-required");
  }
  if (!deps.provider()) {
    logger.error("face anchor: no verification provider is configured");
    throw unavailable();
  }

  const userRef = db.doc(`users/${uid}`);
  const accountSnap = await userRef.get();
  if (!accountSnap.exists) {
    throw new HttpsError("failed-precondition", "account-missing");
  }
  if (!isAccountEligible(accountSnap.data())) {
    throw new HttpsError("permission-denied", "account-suspended");
  }
  const nowMs = deps.now();
  await consumeStartLimit(db, uid, nowMs);

  const profileSnap = await db.doc(`profiles/${uid}`).get();
  const photos = (profileSnap.data()?.photos as Array<Record<string, unknown>> | undefined) ?? [];
  if (!photos.some((photo) => String(photo.id ?? "") === photoId)) {
    throw new HttpsError("failed-precondition", "photo-not-found");
  }

  let entry = await readLedgerEntry(db, uid, photoId);
  if (!entry || entry.status === "pending") {
    // The upload trigger may have been missed; do not make a new member wait
    // for the daily retry before they can verify.
    await deps.moderatePending(uid, photoId);
    entry = await readLedgerEntry(db, uid, photoId);
  }
  if (!entry || entry.status !== "approved" || !isPublishedStoragePath(uid, entry.storagePath)) {
    throw new HttpsError("failed-precondition", "photo-not-approved");
  }
  if (isLedgerFaceAnchor(entry)) {
    throw new HttpsError("failed-precondition", "already-verified");
  }

  const attemptId = deps.newAttemptId();
  const expiresAtMs = nowMs + ATTEMPT_TTL_MS;
  const stateRef = db.doc(faceAnchorStatePath(uid));
  const previousAttemptId = await db.runTransaction(async (tx) => {
    const [userSnap, stateSnap] = await Promise.all([tx.get(userRef), tx.get(stateRef)]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "account-missing");
    }
    const state = parseFaceAnchorState(stateSnap.data());
    if (isProcessingFresh(state, nowMs)) {
      // A verification is running. Opening another would let its result land
      // on an attempt the member no longer sees.
      throw new HttpsError("failed-precondition", "verification-in-progress");
    }
    tx.set(stateRef, {
      schemaVersion: FACE_ANCHOR_SCHEMA_VERSION,
      attemptId,
      photoId,
      status: "awaiting_selfie",
      reason: null,
      consentVersion: FACE_ANCHOR_CONSENT_VERSION,
      consentAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAtMs,
      processingStartedAtMs: 0,
    }, {merge: true});
    return state.attemptId;
  });
  if (previousAttemptId && previousAttemptId !== attemptId) {
    await deleteSelfie(deps, uid, previousAttemptId);
  }
  return {attemptId, uploadPath: selfiePath(uid, attemptId), expiresAtMs, status: "awaiting_selfie"};
}

type Outcome =
  | {status: "verified"}
  | {status: "failed"; reason: FaceAnchorReason}
  | {status: "error"; reason: "technical_error"; refund: boolean};

/**
 * Ends an attempt that never reached the provider. Compare-and-set on the
 * attempt and the status it was read in, so two endings cannot both apply.
 */
async function settle(
  deps: FaceAnchorDeps,
  uid: string,
  attemptId: string,
  from: "awaiting_selfie" | "processing",
  to: {status: "failed" | "expired" | "error"; reason: FaceAnchorReason | null; refund?: boolean},
): Promise<FaceAnchorView> {
  const stateRef = deps.db.doc(faceAnchorStatePath(uid));
  const result = await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    const state = parseFaceAnchorState(snap.data());
    if (!snap.exists || state.attemptId !== attemptId || state.status !== from) {
      return view(state);
    }
    tx.update(stateRef, {
      status: to.status,
      reason: to.reason,
      ...(to.refund ? refundedCounters(state) : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {status: to.status, reason: to.reason, photoId: state.photoId};
  });
  await deleteSelfie(deps, uid, attemptId);
  return result;
}

export async function submitFaceAnchorVerification(
  deps: FaceAnchorDeps,
  uid: string,
  input: {attemptId?: unknown},
): Promise<FaceAnchorView> {
  const {db} = deps;
  const attemptId = cleanId(input.attemptId);
  if (!attemptId) {
    throw new HttpsError("invalid-argument", "attempt-id-required");
  }
  const userRef = db.doc(`users/${uid}`);
  const stateRef = db.doc(faceAnchorStatePath(uid));
  const nowMs = deps.now();

  // The attempt is looked up under the caller's own uid, so an attempt id
  // belonging to anyone else simply is not found.
  const state = parseFaceAnchorState((await stateRef.get()).data());
  if (!state.attemptId || state.attemptId !== attemptId || !state.photoId) {
    throw new HttpsError("failed-precondition", "attempt-not-found");
  }
  if (isTerminal(state.status)) {
    // A repeat of a call whose answer was lost: same answer, nothing re-run.
    return view(state);
  }
  if (state.status === "processing") {
    if (isProcessingFresh(state, nowMs)) {
      return view(state);
    }
    // Its invocation is past the callable timeout: it is dead, not slow.
    return settle(deps, uid, attemptId, "processing",
      {status: "error", reason: "technical_error", refund: true});
  }
  if (nowMs >= state.expiresAtMs) {
    return settle(deps, uid, attemptId, "awaiting_selfie", {status: "expired", reason: null});
  }
  const provider = deps.provider();
  if (!provider) {
    logger.error("face anchor: no verification provider is configured");
    throw unavailable();
  }
  const photoId = state.photoId;

  // Everything that can fail without the provider is checked before the
  // attempt is charged.
  const bucket = deps.bucket();
  const selfieFile = bucket.file(selfiePath(uid, attemptId));
  const [selfieExists] = await selfieFile.exists();
  if (!selfieExists) {
    throw new HttpsError("failed-precondition", "selfie-missing");
  }
  const invalidSelfie = () => settle(deps, uid, attemptId, "awaiting_selfie",
    {status: "failed", reason: "selfie_invalid"});
  const [selfieMeta] = await selfieFile.getMetadata();
  if (Number(selfieMeta.size ?? 0) > MAX_SELFIE_BYTES) {
    return invalidSelfie();
  }
  const [selfieRaw] = await selfieFile.download({validation: false});
  if (selfieRaw.length > MAX_SELFIE_BYTES || !looksLikeImage(selfieRaw)) {
    return invalidSelfie();
  }

  const entry = await readLedgerEntry(db, uid, photoId);
  if (!entry || entry.status !== "approved" || !isPublishedStoragePath(uid, entry.storagePath)) {
    return settle(deps, uid, attemptId, "awaiting_selfie", {status: "error", reason: "technical_error"});
  }
  const storagePath = String(entry.storagePath);
  const referenceFile = bucket.file(storagePath);
  let referenceRaw: Buffer;
  let referenceGeneration: string;
  try {
    const [referenceMeta] = await referenceFile.getMetadata();
    referenceGeneration = String(referenceMeta.generation ?? "");
    [referenceRaw] = await referenceFile.download({validation: false});
  } catch {
    return settle(deps, uid, attemptId, "awaiting_selfie", {status: "error", reason: "technical_error"});
  }
  // The "selfie" is the profile photo itself, sent back. Not a capture.
  if (contentHash(selfieRaw) === contentHash(referenceRaw)) {
    return invalidSelfie();
  }
  let selfie: Buffer;
  try {
    selfie = await deps.normalizeImage(selfieRaw);
  } catch {
    return invalidSelfie();
  }
  let reference: Buffer;
  try {
    reference = await deps.normalizeImage(referenceRaw);
  } catch {
    return settle(deps, uid, attemptId, "awaiting_selfie", {status: "failed", reason: "photo_face_unclear"});
  }

  // Claim the attempt. From here the provider is paid, so this is where the
  // member's budget and the global daily cap are spent — once, however many
  // times the app calls.
  const usageRef = db.doc(`faceAnchorUsage/${usageDayKey(nowMs)}`);
  const claim = await db.runTransaction(async (tx) => {
    const [userSnap, stateSnap, usageSnap] = await Promise.all([
      tx.get(userRef),
      tx.get(stateRef),
      tx.get(usageRef),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "account-missing");
    }
    const current = parseFaceAnchorState(stateSnap.data());
    if (!stateSnap.exists || current.attemptId !== attemptId) {
      throw new HttpsError("failed-precondition", "attempt-not-found");
    }
    if (current.status !== "awaiting_selfie") {
      return {claimed: false as const, state: current};
    }
    const budget = budgetDecision(current, nowMs);
    if (!budget.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        budget.reason === "cooldown" ? "face-anchor-cooldown" : "face-anchor-attempt-limit",
        {retryAfterSeconds: budget.retryAfterSeconds},
      );
    }
    const used = typeof usageSnap.data()?.count === "number" ? Number(usageSnap.data()?.count) : 0;
    if (used >= deps.dailyGlobalCap()) {
      logger.error("face anchor: daily global verification cap reached");
      throw unavailable();
    }
    tx.update(stateRef, {
      status: "processing",
      processingStartedAtMs: nowMs,
      windowStartedAtMs: budget.windowStartedAtMs,
      attemptCount: budget.attemptCount,
      refundCount: budget.refundCount,
      lastAttemptAtMs: nowMs,
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(usageRef, {count: used + 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return {claimed: true as const};
  });
  if (!claim.claimed) {
    // A concurrent call got there first; report whatever it has reached.
    return view(claim.state);
  }

  try {
    let outcome: Outcome;
    try {
      outcome = await askProvider(provider, selfie, reference);
    } catch (error) {
      const providerError = error instanceof FaceProviderError ? error : null;
      // The code only. A provider message could carry anything.
      logger.error("face anchor: verification provider failed", safeLogMeta({
        reasonCode: providerError?.code ?? "unexpected",
        retryable: providerError?.retryable === true,
        unavailable: providerError?.unavailable === true,
      }));
      outcome = {status: "error", reason: "technical_error", refund: providerError?.retryable === true};
    }
    if (outcome.status === "verified") {
      // The object the verdict is about must still be the one that was read.
      let generationNow: string | null = null;
      try {
        const [meta] = await referenceFile.getMetadata();
        generationNow = String(meta.generation ?? "");
      } catch {
        generationNow = null;
      }
      if (generationNow !== referenceGeneration) {
        outcome = {status: "error", reason: "technical_error", refund: false};
      }
    }
    const result = await finalize(deps, uid, attemptId, outcome, {
      photoId,
      storagePath,
      providerId: provider.id,
    });
    if (result.status === "failed" || result.status === "error") {
      logger.info("face anchor: verification not granted", safeLogMeta({reasonCode: result.reason ?? "none"}));
    }
    return result;
  } finally {
    await deleteSelfie(deps, uid, attemptId);
  }
}

async function askProvider(
  provider: FaceVerificationProvider,
  selfie: Buffer,
  reference: Buffer,
): Promise<Outcome> {
  const liveness = await provider.checkLiveness(selfie);
  if (liveness !== "live") {
    return {status: "failed", reason: "liveness_failed"};
  }
  let match;
  try {
    match = await provider.matchFaces(selfie, reference);
  } catch (error) {
    if (!(error instanceof FaceProviderError) || !error.retryable) {
      throw error;
    }
    // Liveness is already paid for. One more try at the match, so a blip does
    // not send the member back to pay for liveness again.
    match = await provider.matchFaces(selfie, reference);
  }
  if (match === "match") {
    return {status: "verified"};
  }
  return {status: "failed", reason: match === "no_match" ? "face_mismatch" : "photo_face_unclear"};
}

/**
 * Writes the result — or discards it.
 *
 * One compare-and-set transaction. The result lands only if this is still the
 * member's current attempt and still `processing`, the account still exists,
 * the photo is still on the profile, and the ledger still calls the same
 * published object approved. An invocation that outlived its attempt, raced an
 * account deletion or lost its photo therefore cannot write anything. Only
 * `update` is used: a deleted account is never re-created by a late result.
 */
async function finalize(
  deps: FaceAnchorDeps,
  uid: string,
  attemptId: string,
  outcome: Outcome,
  target: {photoId: string; storagePath: string; providerId: string},
): Promise<FaceAnchorView> {
  const {db} = deps;
  const stateRef = db.doc(faceAnchorStatePath(uid));
  return db.runTransaction(async (tx) => {
    const [userSnap, stateSnap] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(stateRef)]);
    const photoState = await loadPhotoState(tx, db, uid);
    const state = parseFaceAnchorState(stateSnap.data());
    if (
      !userSnap.exists ||
      !stateSnap.exists ||
      state.attemptId !== attemptId ||
      state.status !== "processing"
    ) {
      return view(state);
    }
    const stamp = {updatedAt: FieldValue.serverTimestamp()};
    if (outcome.status !== "verified") {
      tx.update(stateRef, {
        status: outcome.status,
        reason: outcome.reason,
        ...(outcome.status === "error" && outcome.refund ? refundedCounters(state) : {}),
        ...stamp,
      });
      return {status: outcome.status, reason: outcome.reason, photoId: target.photoId};
    }

    const entry = photoState.ledger.get(target.photoId);
    const onProfile = photoState.exists &&
      photoState.photos.some((photo) => String(photo.id ?? "") === target.photoId);
    if (!onProfile || entry?.status !== "approved" || entry.storagePath !== target.storagePath) {
      // The photo changed under the verification. The verdict is about
      // something that is no longer there.
      tx.update(stateRef, {status: "error", reason: "technical_error", ...stamp});
      return {status: "error", reason: "technical_error", photoId: target.photoId};
    }
    const verdict: FaceAnchorLedgerState = {
      status: "verified",
      verifiedAt: Timestamp.fromMillis(deps.now()),
      provider: target.providerId,
      attemptId,
      storagePath: target.storagePath,
    };
    photoState.ledger.set(target.photoId, {...entry, faceAnchor: verdict});
    commitPhotoInvariants(tx, db, uid, photoState, {
      // From the first verified anchor on, this profile is held to the rule.
      profilePatch: photoState.profile.faceAnchorRequired === true ? {} : {faceAnchorRequired: true},
    });
    tx.update(ledgerRef(db, uid, target.photoId), {faceAnchor: verdict, ...stamp});
    tx.update(stateRef, {status: "verified", reason: null, ...stamp});
    return {status: "verified", reason: null, photoId: target.photoId};
  });
}

/**
 * Deletes every selfie older than `maxAgeMs`, whatever became of its attempt.
 *
 * The backstop for the paths `submit` never sees: the app closed after the
 * upload, the network dropped, the function was killed. Age is the only
 * criterion, so nothing can keep a selfie alive.
 */
export async function sweepFaceAnchorSelfies(
  deps: FaceAnchorDeps,
  options: {maxAgeMs?: number; pageSize?: number; maxPages?: number} = {},
): Promise<{scanned: number; deleted: number}> {
  const maxAgeMs = options.maxAgeMs ?? SELFIE_MAX_AGE_MS;
  const pageSize = options.pageSize ?? 200;
  const maxPages = options.maxPages ?? 25;
  const nowMs = deps.now();
  const bucket = deps.bucket();
  let pageToken: string | undefined;
  let scanned = 0;
  let deleted = 0;
  for (let page = 0; page < maxPages; page += 1) {
    const [files, next] = await bucket.getFiles({
      prefix: SELFIE_PREFIX,
      maxResults: pageSize,
      autoPaginate: false,
      ...(pageToken ? {pageToken} : {}),
    }) as [Array<{name: string; metadata?: Record<string, unknown>}>, {pageToken?: string} | null | undefined];
    for (const file of files) {
      scanned += 1;
      let createdRaw = file.metadata?.timeCreated;
      if (createdRaw === undefined) {
        try {
          const [metadata] = await bucket.file(file.name).getMetadata();
          createdRaw = metadata.timeCreated;
        } catch {
          continue;
        }
      }
      const created = Date.parse(String(createdRaw ?? ""));
      // An unreadable age is treated as old: when in doubt the selfie goes.
      if (!Number.isNaN(created) && created > nowMs - maxAgeMs) {
        continue;
      }
      try {
        await bucket.file(file.name).delete({ignoreNotFound: true});
        deleted += 1;
      } catch {
        continue;
      }
      const parsed = parseSelfiePath(file.name);
      if (parsed) {
        await expireAbandonedAttempt(deps, parsed.uid, parsed.attemptId, nowMs);
      }
    }
    pageToken = next?.pageToken;
    if (!pageToken) {
      break;
    }
  }
  return {scanned, deleted};
}

/** Marks the attempt a swept selfie belonged to, if it is still open. */
async function expireAbandonedAttempt(
  deps: FaceAnchorDeps,
  uid: string,
  attemptId: string,
  nowMs: number,
): Promise<void> {
  const stateRef = deps.db.doc(faceAnchorStatePath(uid));
  await deps.db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    const state = parseFaceAnchorState(snap.data());
    if (!snap.exists || state.attemptId !== attemptId) {
      return;
    }
    if (state.status === "awaiting_selfie") {
      tx.update(stateRef, {status: "expired", reason: null, updatedAt: FieldValue.serverTimestamp()});
    } else if (state.status === "processing" && !isProcessingFresh(state, nowMs)) {
      tx.update(stateRef, {
        status: "error",
        reason: "technical_error",
        ...refundedCounters(state),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
}
