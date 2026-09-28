import {FieldValue, Timestamp, type DocumentData, type Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions";
import {calculateCompatibility} from "../compatibility/compatibilityEngine.js";
import {humorScoreForPair, isHumorCalibrationReady} from "../humor/compatibility.js";
import {loadUserHumorProfile} from "../humor/feed.js";
import {relationshipScoreForPair} from "../relationshipMatch.js";
import {musicScoreForPair} from "../spotifyMusic.js";
import {EVENT_LEDGER_TTL_DAYS, WEAK_SIGNALS} from "./config.js";
import {
  applyLearningEvent,
  effectiveAdjustments,
  parseProfile,
  serializeProfile,
  type Adjustments,
  type DimensionVector,
  type LearningTrace,
  type PersonalizationProfile,
} from "./learner.js";
import {personalizationEventId, utcDayKey} from "./signals.js";

/**
 * Firestore side of adaptive personalization.
 *
 *   userSettings/{uid}.personalizeRecommendations   the member's switch (client-writable, default ON)
 *   users/{uid}/personalization/profile             learned state (server-only; owner may read)
 *   users/{uid}/personalizationEvents/{eventId}     idempotency ledger (server-only, unreadable)
 *
 * Personalization is an enhancement: every entry point here swallows its own
 * failures, so a like, a match or a message never fails because of it.
 */

export const PERSONALIZATION_SETTING_FIELD = "personalizeRecommendations";

export function personalizationProfilePath(uid: string): string {
  return `users/${uid}/personalization/profile`;
}

export function personalizationEventPath(uid: string, eventId: string): string {
  return `users/${uid}/personalizationEvents/${eventId}`;
}

/** Default ON: only an explicit `false` turns personalization off. */
export function isPersonalizationEnabled(settings: DocumentData | undefined | null): boolean {
  return settings?.[PERSONALIZATION_SETTING_FIELD] !== false;
}

export interface PersonalizationContext {
  enabled: boolean;
  profile: PersonalizationProfile;
  adjustments: Adjustments;
}

/**
 * The viewer's personalization for one ranking operation: two reads, once
 * per request, never per candidate. Any failure means neutral ranking.
 */
export async function loadPersonalizationContext(
  db: Firestore,
  uid: string,
): Promise<PersonalizationContext> {
  try {
    const [settings, stored] = await Promise.all([
      db.doc(`userSettings/${uid}`).get(),
      db.doc(personalizationProfilePath(uid)).get(),
    ]);
    const enabled = isPersonalizationEnabled(settings.data());
    const profile = parseProfile(stored.data());
    return {enabled, profile, adjustments: effectiveAdjustments(profile, enabled)};
  } catch (error) {
    logger.warn("personalization: context unavailable, ranking stays neutral", {
      error: error instanceof Error ? error.message : String(error),
    });
    const profile = parseProfile(null);
    return {enabled: false, profile, adjustments: effectiveAdjustments(profile, false)};
  }
}

// ---------------------------------------------------------------------------
// The dimension vector for one viewer/candidate pair.
// ---------------------------------------------------------------------------

/** Same bar Picks uses before relationship answers count as evidence. */
const MIN_SHARED_QUESTIONS = 3;

function hasText(value: unknown): boolean {
  return String(value ?? "").trim().length > 0;
}

function hasList(value: unknown): boolean {
  return Array.isArray(value) && value.some((item) => hasText(item));
}

function hasLifestyle(data: DocumentData): boolean {
  if (hasList(data.lifestyle)) return true;
  const profile = data.lifestyleProfile as Record<string, unknown> | undefined;
  return !!profile && Object.values(profile).some((value) => hasText(value));
}

async function humorForPair(db: Firestore, viewerUid: string, candidateUid: string): Promise<number | null> {
  const load = async (uid: string) => {
    const [profile, calibration] = await Promise.all([
      loadUserHumorProfile(db, uid),
      db.doc(`users/${uid}/humor/calibration`).get(),
    ]);
    return {profile, ready: isHumorCalibrationReady(calibration.data(), profile)};
  };
  const viewer = await load(viewerUid);
  if (!viewer.ready) return null;
  const candidate = await load(candidateUid);
  const result = humorScoreForPair(viewer.profile, candidate.profile, {
    readyA: viewer.ready,
    readyB: candidate.ready,
  });
  return result.available && result.score !== null ? result.score : null;
}

/**
 * The canonical per-dimension scores for a pair, from the same scorers
 * Discover, Picks and the match screen use. A dimension is null unless it
 * was actually measured for BOTH people: a neutral default is not evidence.
 * Returns null when either profile is missing.
 */
export async function pairDimensionVector(
  db: Firestore,
  viewerUid: string,
  candidateUid: string,
): Promise<DimensionVector | null> {
  return (await pairScores(db, viewerUid, candidateUid))?.vector ?? null;
}

/** The dimension vector plus the canonical overall score, for ranking explanations. */
export async function pairScores(
  db: Firestore,
  viewerUid: string,
  candidateUid: string,
): Promise<{vector: DimensionVector; overall: number} | null> {
  const [viewerSnap, candidateSnap, relationship, music, humor] = await Promise.all([
    db.doc(`profiles/${viewerUid}`).get(),
    db.doc(`profiles/${candidateUid}`).get(),
    relationshipScoreForPair(viewerUid, candidateUid).catch(() => null),
    musicScoreForPair(viewerUid, candidateUid).catch(() => null),
    humorForPair(db, viewerUid, candidateUid).catch(() => null),
  ]);
  if (!viewerSnap.exists || !candidateSnap.exists) return null;
  const viewer = viewerSnap.data() ?? {};
  const candidate = candidateSnap.data() ?? {};
  const compat = calculateCompatibility({
    viewerProfile: viewer,
    candidateProfile: candidate,
    relationship: relationship
      ? {
          score: relationship.score,
          alignedCount: relationship.alignedCount,
          sharedQuestionCount: relationship.sharedQuestionCount,
          topTopics: relationship.topTopics ?? [],
        }
      : null,
    musicScore: music?.score ?? null,
  });
  const vector: DimensionVector = {
    relationship:
      hasText(viewer.relationshipGoal) && hasText(candidate.relationshipGoal)
        ? compat.relationshipScore
        : null,
    values:
      relationship && relationship.sharedQuestionCount >= MIN_SHARED_QUESTIONS
        ? relationship.score
        : null,
    lifestyle: hasLifestyle(viewer) && hasLifestyle(candidate) ? compat.lifestyleScore : null,
    interests:
      hasList(viewer.interests) && hasList(candidate.interests) ? compat.interestScore : null,
    music: music?.score ?? null,
    humor,
  };
  return {vector, overall: compat.overallScore};
}

// ---------------------------------------------------------------------------
// Recording a learning event.
// ---------------------------------------------------------------------------

export type RecordOutcome =
  | "applied"
  | "disabled"
  | "duplicate"
  | "noVector"
  | "dailyCap";

export interface RecordEventInput {
  actorUid: string;
  otherUid: string;
  type: string;
  /** Makes this occurrence unique (matchId, day key, ...). */
  key: string;
  strength: number;
  /** Weak events share a daily budget. */
  weak?: boolean;
  /** Precomputed vector; loaded from the pair when omitted. */
  vector?: DimensionVector | null;
  nowMs?: number;
}

/**
 * Apply one event to the actor's learned profile, exactly once.
 *
 * Idempotency: the event id is derived from (type, actor, other, key); the
 * ledger entry is created in the same transaction that updates the profile,
 * so a retried trigger, a replayed listener or a double tap cannot count an
 * event twice. Personalization OFF means the event is dropped, not queued.
 */
export async function recordLearningEvent(
  db: Firestore,
  input: RecordEventInput,
): Promise<{outcome: RecordOutcome; trace?: LearningTrace}> {
  const nowMs = input.nowMs ?? Date.now();
  const eventId = personalizationEventId({
    type: input.type,
    actorUid: input.actorUid,
    otherUid: input.otherUid,
    key: input.key,
  });
  const ledgerRef = db.doc(personalizationEventPath(input.actorUid, eventId));
  const profileRef = db.doc(personalizationProfilePath(input.actorUid));
  const settingsRef = db.doc(`userSettings/${input.actorUid}`);

  // Cheap pre-checks, so a disabled member or a replay costs no scoring reads.
  const [settings, ledger] = await Promise.all([settingsRef.get(), ledgerRef.get()]);
  if (!isPersonalizationEnabled(settings.data())) return {outcome: "disabled"};
  if (ledger.exists) return {outcome: "duplicate"};

  const vector =
    input.vector !== undefined
      ? input.vector
      : await pairDimensionVector(db, input.actorUid, input.otherUid);
  if (!vector) return {outcome: "noVector"};

  return db.runTransaction(async (tx) => {
    const [settingsTx, ledgerTx, storedTx] = await Promise.all([
      tx.get(settingsRef),
      tx.get(ledgerRef),
      tx.get(profileRef),
    ]);
    if (!isPersonalizationEnabled(settingsTx.data())) return {outcome: "disabled" as const};
    if (ledgerTx.exists) return {outcome: "duplicate" as const};

    const stored = storedTx.data() ?? {};
    const today = utcDayKey(nowMs);
    const weakCount = stored.weakDayKey === today ? Number(stored.weakCount ?? 0) : 0;
    if (input.weak && weakCount >= WEAK_SIGNALS.maxEventsPerDay) {
      return {outcome: "dailyCap" as const};
    }

    const {profile, trace} = applyLearningEvent(
      parseProfile(stored),
      {type: input.type, strength: input.strength, vector},
      nowMs,
    );
    tx.set(profileRef, {
      ...serializeProfile(profile),
      lastEventType: input.type,
      ...(input.weak ? {weakDayKey: today, weakCount: weakCount + 1} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    tx.create(ledgerRef, {
      type: input.type,
      createdAt: FieldValue.serverTimestamp(),
      expireAt: Timestamp.fromMillis(nowMs + EVENT_LEDGER_TTL_DAYS * 86_400_000),
    });
    return {outcome: "applied" as const, trace};
  });
}

/**
 * Fire-and-forget wrapper for core flows: never throws, logs without any
 * user identifier, and returns the outcome for tests.
 */
export async function recordLearningEventSafely(
  db: Firestore,
  input: RecordEventInput,
): Promise<RecordOutcome | "failed"> {
  try {
    const {outcome} = await recordLearningEvent(db, input);
    return outcome;
  } catch (error) {
    logger.warn("personalization: event not recorded", {
      type: input.type,
      error: error instanceof Error ? error.message : String(error),
    });
    return "failed";
  }
}
