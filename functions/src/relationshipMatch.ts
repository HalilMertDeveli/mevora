import {getApps, initializeApp} from "firebase-admin/app";
import {FieldValue, Timestamp, getFirestore, type DocumentData} from "firebase-admin/firestore";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import {isActiveForDiscovery, loadLastActiveAt} from "./discoveryActivity.js";
import {canonicalMatchId, blockId} from "./ids.js";
import {preservedMatchScoreFields} from "./matchScore.js";
import {userLanguage} from "./language.js";
import {interestedInAllows} from "./musicCompatibility.js";
import {
  answersFromSummary,
  canonicalCompatibilityKey,
  hashCompatibilityKey,
  isValidRelationshipAnswer,
  isWithinRelationshipRadius,
  scoreRelationshipCompatibility,
  setIdFor,
  type RelationshipAnswers,
} from "./relationshipCompatibility.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();
const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
const enforceAppCheck =
  process.env.FUNCTIONS_EMULATOR !== "true" && projectId === "mevora-production";
const callableOptions = {
  region: "europe-west1" as const,
  invoker: "public" as const,
  enforceAppCheck,
};
const RESULT_LIMIT = 1;
const skipRadius = process.env.FUNCTIONS_EMULATOR === "true";

function relDebug(message: string, extra?: unknown): void {
  if (extra === undefined) {
    console.log(`[RELATIONSHIP_DEBUG] ${message}`);
    return;
  }
  console.log(`[RELATIONSHIP_DEBUG] ${message}`, extra);
}

function requireUid(request: CallableRequest): string {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "unauthenticated");
  }
  return uid;
}

function toMillis(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (value instanceof Date) return value.getTime();
  if (value instanceof Timestamp) return value.toMillis();
  if (value && typeof value === "object") {
    const record = value as {toMillis?: () => number; toDate?: () => Date};
    if (typeof record.toMillis === "function") return record.toMillis();
    if (typeof record.toDate === "function") return record.toDate().getTime();
  }
  return null;
}

function snapshotPayload(
  answers: RelationshipAnswers,
  summary?: DocumentData,
) {
  const payload: Record<string, unknown> = {
    answeredIds: Object.keys(answers).sort(),
    answerCount: Object.keys(answers).length,
  };
  const cooldown = toMillis(summary?.offerCooldownUntil);
  if (cooldown != null) payload.offerCooldownUntil = cooldown;
  const completed = toMillis(summary?.lastCompletedAt);
  if (completed != null) payload.lastCompletedAt = completed;
  return payload;
}

function profileQuestionAnswerRef(uid: string, questionId: string) {
  return db.doc(`users/${uid}/questionAnswers/${questionId}`);
}

function profileAnswerVisible(data?: DocumentData | null): boolean {
  return data?.isVisible !== false;
}

async function upsertProfileQuestionAnswer(input: {
  uid: string;
  questionId: string;
  answerId: string;
  existing?: DocumentData | null;
}): Promise<void> {
  const ref = profileQuestionAnswerRef(input.uid, input.questionId);
  const isVisible = profileAnswerVisible(input.existing);
  if (input.existing) {
    await ref.update({
      questionId: input.questionId,
      answerId: input.answerId,
      isVisible,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return;
  }
  await ref.set({
    questionId: input.questionId,
    answerId: input.answerId,
    isVisible: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
}

async function loadSummary(uid: string) {
  return db.doc(`users/${uid}/relationshipMatch/summary`).get();
}

async function loadAnswers(uid: string): Promise<RelationshipAnswers> {
  const summary = await loadSummary(uid);
  const fromSummary = answersFromSummary(summary.data());
  if (Object.keys(fromSummary).length > 0) {
    return fromSummary;
  }
  const snap = await db.collection(`users/${uid}/relationshipAnswers`).limit(120).get();
  const answers: RelationshipAnswers = {};
  for (const doc of snap.docs) {
    const answerId = doc.data().answerId;
    if (typeof answerId === "string" && isValidRelationshipAnswer(doc.id, answerId)) {
      answers[doc.id] = answerId;
    }
  }
  return answers;
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

function distanceLabel(km: number, lang: "tr" | "en"): string {
  if (km < 1) return lang === "tr" ? "1 km'den yakın" : "Less than 1 km away";
  if (km >= 100) return lang === "tr" ? "100+ km uzakta" : "100+ km away";
  return lang === "tr" ? `${Math.round(km)} km uzakta` : `${Math.round(km)} km away`;
}

function datingPreference(
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

async function isBlocked(a: string, b: string): Promise<boolean> {
  const [subA, subB, topA, topB] = await Promise.all([
    db.doc(`users/${a}/blockedUsers/${b}`).get(),
    db.doc(`users/${b}/blockedUsers/${a}`).get(),
    db.doc(`blocks/${blockId(a, b)}`).get(),
    db.doc(`blocks/${blockId(b, a)}`).get(),
  ]);
  return subA.exists || subB.exists || topA.exists || topB.exists;
}

async function profilePreview(uid: string): Promise<{name: string; photoUrl?: string}> {
  const snap = await db.doc(`profiles/${uid}`).get();
  const data = snap.data() ?? {};
  return {
    name: String(data.displayName ?? data.name ?? "Mevora"),
    photoUrl: Array.isArray(data.photos) ? data.photos[0] : data.photoUrl,
  };
}

async function excludedMatchUids(uid: string): Promise<Set<string>> {
  const excluded = new Set<string>();
  const snap = await db.collection("matches").where("userIds", "array-contains", uid).limit(100).get();
  for (const doc of snap.docs) {
    const ids = (doc.data().userIds as string[]) ?? [];
    for (const id of ids) {
      if (id && id !== uid) excluded.add(id);
    }
  }
  return excluded;
}

type CandidateRow = {
  uid: string;
  score: number;
  sharedQuestionCount: number;
  alignedCount: number;
  distanceKm: number | null;
  distanceLabel: string | null;
  profile: Record<string, unknown>;
};

async function findExactCandidates(
  uid: string,
  questionIds: string[],
  compatibilityKey: string,
): Promise<CandidateRow[]> {
  const [
    prefsSnap,
    profileSnap,
    locationSnap,
    blockedSnap,
    passedSnap,
    poolSnap,
    matchUids,
    seenSnap,
    lang,
  ] = await Promise.all([
    db.doc(`userPreferences/${uid}`).get(),
    db.doc(`profiles/${uid}`).get(),
    db.doc(`userLocation/${uid}`).get(),
    db.collection(`users/${uid}/blockedUsers`).get(),
    db.collection(`users/${uid}/passedUsers`).get(),
    db.collectionGroup("relationshipMatch").where("compatibilityKey", "==", compatibilityKey).limit(40).get().catch((error: unknown) => {
      const err = error as {code?: string; message?: string};
      relDebug(`FirebaseException ${err.code ?? "unknown"}: ${err.message ?? String(error)}`);
      throw error;
    }),
    excludedMatchUids(uid),
    db.collection(`users/${uid}/relationshipSeen`).get(),
    userLanguage(uid),
  ]);
  const origin = locationSnap.data();
  const originLat = origin?.latitude;
  const originLng = origin?.longitude;
  const hasOrigin = originLat != null && originLng != null;
  relDebug(`Candidates found: ${poolSnap.size}`);
  if (!hasOrigin) {
    relDebug("Distance calculation started — viewer location missing");
    if (!skipRadius) {
      return [];
    }
  } else {
    relDebug("Distance calculation started");
  }
  const blocked = new Set(blockedSnap.docs.map((doc) => doc.id));
  const passed = new Set(passedSnap.docs.map((doc) => doc.id));
  const seen = new Set(seenSnap.docs.map((doc) => doc.id));
  const prefs = prefsSnap.data() ?? {};
  const viewerProfile = profileSnap.data() ?? {};
  const viewerGender = viewerProfile.gender as string | undefined;
  const viewerWant = datingPreference(prefs, viewerProfile);
  const viewerAnswers = answersFromSummary((await loadSummary(uid)).data());
  const minAge = Number(prefs.minAge ?? 18);
  const maxAge = Number(prefs.maxAge ?? 99);
  relDebug(
    `Viewer gender=${viewerGender ?? "none"} interestedIn=${String(viewerWant ?? "everyone")}`,
  );
  const otherUids: string[] = [];
  let afterBlock = 0;
  for (const doc of poolSnap.docs) {
    const otherUid = doc.ref.parent.parent?.id;
    if (!otherUid || otherUid === uid) continue;
    if (blocked.has(otherUid) || passed.has(otherUid) || matchUids.has(otherUid) || seen.has(otherUid)) {
      continue;
    }
    afterBlock += 1;
    otherUids.push(otherUid);
  }
  relDebug(`Preference filter input after block/unmatch/existing: ${afterBlock}`);
  const lastActiveByUid = await loadLastActiveAt(db, otherUids);
  const scored: CandidateRow[] = [];
  let afterActive = 0;
  let afterPreference = 0;
  for (const doc of poolSnap.docs) {
    const otherUid = doc.ref.parent.parent?.id;
    if (!otherUid || otherUid === uid) continue;
    if (blocked.has(otherUid) || passed.has(otherUid) || matchUids.has(otherUid) || seen.has(otherUid)) {
      continue;
    }
    if (!isActiveForDiscovery(lastActiveByUid.get(otherUid))) continue;
    afterActive += 1;
    if (await isBlocked(uid, otherUid)) continue;
    const otherAnswers = answersFromSummary(doc.data());
    if (!questionIds.every((id) => otherAnswers[id])) continue;
    const otherProfile = await db.doc(`profiles/${otherUid}`).get();
    if (!otherProfile.exists) continue;
    const data = otherProfile.data() ?? {};
    if (data.isDiscoverable === false) continue;
    const age = Number(data.age ?? 0);
    if (age && (age < minAge || age > maxAge)) continue;
    const otherPrefs = (await db.doc(`userPreferences/${otherUid}`).get()).data() ?? {};
    const otherWant = datingPreference(otherPrefs, data);
    if (!interestedInAllows(viewerWant, data.gender)) continue;
    if (!interestedInAllows(otherWant, viewerGender)) continue;
    afterPreference += 1;
    const filteredViewer: RelationshipAnswers = {};
    const filteredOther: RelationshipAnswers = {};
    for (const questionId of questionIds) {
      if (viewerAnswers[questionId]) filteredViewer[questionId] = viewerAnswers[questionId];
      if (otherAnswers[questionId]) filteredOther[questionId] = otherAnswers[questionId];
    }
    const compatibility = scoreRelationshipCompatibility(filteredViewer, filteredOther);
    const otherLoc = await db.doc(`userLocation/${otherUid}`).get();
    const other = otherLoc.data();
    let distanceKm: number | null = null;
    if (hasOrigin && other?.latitude != null && other?.longitude != null) {
      distanceKm =
        Math.round(
          haversineKm(
            Number(originLat),
            Number(originLng),
            Number(other.latitude),
            Number(other.longitude),
          ) * 10,
        ) / 10;
      relDebug(`Candidate: ${otherUid} Distance: ${distanceKm} km`);
      if (!skipRadius && !isWithinRelationshipRadius(distanceKm)) continue;
    } else if (!skipRadius) {
      relDebug(`Candidate: ${otherUid} Distance: missing`);
      continue;
    } else {
      relDebug(`Candidate: ${otherUid} Distance: skipped (emulator)`);
    }
    scored.push({
      uid: otherUid,
      score: compatibility.score,
      sharedQuestionCount: compatibility.sharedQuestionCount,
      alignedCount: compatibility.alignedCount,
      distanceKm,
      distanceLabel: distanceKm == null ? null : distanceLabel(distanceKm, lang),
      profile: {
        uid: otherUid,
        displayName: data.displayName ?? "",
        age: data.age ?? null,
        gender: data.gender ?? null,
        bio: data.bio ?? null,
        photos: data.photos ?? [],
        interests: data.interests ?? [],
        city: data.city ?? null,
      },
    });
  }
  relDebug(`Active user filter result: ${afterActive}`);
  relDebug(`Preference filter result: ${afterPreference}`);
  scored.sort((a, b) => (a.distanceKm ?? Number.POSITIVE_INFINITY) - (b.distanceKm ?? Number.POSITIVE_INFINITY));
  relDebug(`Relationship matches created: ${Math.min(scored.length, RESULT_LIMIT)}`);
  return scored.slice(0, RESULT_LIMIT);
}

async function createRelationshipMatch(
  uid: string,
  otherUid: string,
  compatibilityKey: string,
): Promise<string> {
  const matchId = canonicalMatchId(uid, otherUid);
  const matchRef = db.doc(`matches/${matchId}`);
  const existing = await matchRef.get();
  if (existing.exists && existing.data()?.isActive === true) {
    return matchId;
  }
  const [actor, other] = await Promise.all([profilePreview(uid), profilePreview(otherUid)]);
  const previous = existing.data();
  await matchRef.set({
    userIds: [uid, otherUid].sort(),
    createdAt: previous?.createdAt ?? FieldValue.serverTimestamp(),
    lastMessage: null,
    lastMessageAt: FieldValue.serverTimestamp(),
    isActive: true,
    unmatchedBy: null,
    unmatchedAt: null,
    unreadCounts: {[uid]: 0, [otherUid]: 0},
    isNewFor: {[uid]: true, [otherUid]: true},
    participantNames: {[uid]: actor.name, [otherUid]: other.name},
    participantPhotos: {
      ...(actor.photoUrl ? {[uid]: actor.photoUrl} : {}),
      ...(other.photoUrl ? {[otherUid]: other.photoUrl} : {}),
    },
    ...preservedMatchScoreFields(previous),
    source: "relationship_test",
    matchType: "relationship",
    compatibilityKey,
  });
  relDebug(`Match document written ${matchId}`);
  const seen = {
    seenAt: FieldValue.serverTimestamp(),
    reason: "matched",
  };
  await Promise.all([
    db.doc(`users/${uid}/relationshipSeen/${otherUid}`).set(seen, {merge: true}),
    db.doc(`users/${otherUid}/relationshipSeen/${uid}`).set(seen, {merge: true}),
  ]);
  return matchId;
}

export const saveRelationshipAnswer = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      const questionId = String(request.data?.questionId ?? "");
      const answerId = String(request.data?.answerId ?? "");
      relDebug(`Question answers submitted ${questionId}=${answerId}`);
      if (!isValidRelationshipAnswer(questionId, answerId)) {
        throw new HttpsError("invalid-argument", "invalid-relationship-answer");
      }
      const answerRef = db.doc(`users/${uid}/relationshipAnswers/${questionId}`);
      const summaryRef = db.doc(`users/${uid}/relationshipMatch/summary`);
      const profileRef = profileQuestionAnswerRef(uid, questionId);
      const current = await loadAnswers(uid);
      if (current[questionId] === answerId) {
        const summary = await loadSummary(uid);
        const profileSnap = await profileRef.get();
        if (!profileSnap.exists) {
          await upsertProfileQuestionAnswer({
            uid,
            questionId,
            answerId,
          });
        }
        relDebug("Answer unchanged");
        return snapshotPayload(current, summary.data());
      }
      current[questionId] = answerId;
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(answerRef);
        const existingProfile = await tx.get(profileRef);
        if (existing.exists) {
          tx.update(answerRef, {
            answerId,
            answeredAt: FieldValue.serverTimestamp(),
          });
        } else {
          tx.create(answerRef, {
            questionId,
            answerId,
            answeredAt: FieldValue.serverTimestamp(),
          });
        }
        const profileVisible = existingProfile.exists
          ? profileAnswerVisible(existingProfile.data())
          : true;
        if (existingProfile.exists) {
          tx.update(profileRef, {
            questionId,
            answerId,
            isVisible: profileVisible,
            updatedAt: FieldValue.serverTimestamp(),
          });
        } else {
          tx.create(profileRef, {
            questionId,
            answerId,
            isVisible: true,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
        tx.set(
          summaryRef,
          {
            eligibleForMatching: Object.keys(current).length > 0,
            answerCount: Object.keys(current).length,
            answers: current,
            lastAnsweredAt: FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
      });
      const summary = await loadSummary(uid);
      relDebug("Answers saved successfully");
      return snapshotPayload(current, summary.data());
    } catch (error) {
      const err = error as {code?: string; message?: string};
      relDebug(
        `FirebaseException ${err.code ?? "unknown"}: ${err.message ?? String(error)}`,
      );
      throw error;
    }
  },
);

export const getRelationshipAnswered = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const [answers, summary] = await Promise.all([loadAnswers(uid), loadSummary(uid)]);
    return snapshotPayload(answers, summary.data());
  },
);

export const dismissRelationshipTestOffer = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const reason = String(request.data?.reason ?? "declined");
    // declined / empty close → 3 min retry; matched (open chat) → 30 min pause
    const cooldownMs =
      reason === "matched" ? 30 * 60 * 1000 : 3 * 60 * 1000;
    const cooldownUntil = Timestamp.fromMillis(Date.now() + cooldownMs);
    await db.doc(`users/${uid}/relationshipMatch/summary`).set(
      {
        offerDismissedAt: FieldValue.serverTimestamp(),
        offerCooldownUntil: cooldownUntil,
        offerCooldownReason: reason === "matched" ? "matched" : "declined",
      },
      {merge: true},
    );
    const [answers, summary] = await Promise.all([loadAnswers(uid), loadSummary(uid)]);
    return snapshotPayload(answers, summary.data());
  },
);

export const completeRelationshipTest = onCall(
  callableOptions,
  async (request) => {
    try {
      const uid = requireUid(request);
      const rawIds = request.data?.questionIds;
      const questionIds = Array.isArray(rawIds)
        ? rawIds.map((item) => String(item)).filter((item) => item.length > 0)
        : [];
      if (questionIds.length !== 3 || setIdFor(questionIds) == null) {
        throw new HttpsError("invalid-argument", "invalid-relationship-set");
      }
      for (const id of questionIds) {
        if (!isValidRelationshipAnswer(id, "a")) {
          throw new HttpsError("invalid-argument", "invalid-relationship-set");
        }
      }
      const answers = await loadAnswers(uid);
      const sessionAnswers: RelationshipAnswers = {};
      for (const id of questionIds) {
        const answerId = answers[id];
        if (!answerId) {
          throw new HttpsError("failed-precondition", "incomplete-relationship-test");
        }
        sessionAnswers[id] = answerId;
      }
      const canonical = canonicalCompatibilityKey(sessionAnswers, questionIds);
      const compatibilityKey = hashCompatibilityKey(canonical);
      const setId = setIdFor(questionIds);
      relDebug(`Compatibility key generated: ${compatibilityKey ? "YES" : "NO"}`);
      relDebug("Relationship pool query started");
      await db.doc(`users/${uid}/relationshipMatch/summary`).set(
        {
          eligibleForMatching: true,
          compatibilityKey,
          setId,
          questionIds,
          lastCompletedAt: FieldValue.serverTimestamp(),
          offerCooldownUntil: Timestamp.fromMillis(Date.now() + 3 * 60 * 1000),
        },
        {merge: true},
      );
      const items = await findExactCandidates(uid, questionIds, compatibilityKey);
      const nearest = items[0];
      if (!nearest) {
        relDebug("Candidates found: 0");
        relDebug("Relationship matches created: 0");
        return {items: [], empty: true, matched: false};
      }
      const matchId = await createRelationshipMatch(uid, nearest.uid, compatibilityKey);
      relDebug(`Relationship matches created: 1 matchId=${matchId}`);
      return {
        items: [{...nearest, matchId}],
        empty: false,
        matched: true,
        matchId,
      };
    } catch (error) {
      const err = error as {code?: string; message?: string};
      relDebug(
        `FirebaseException ${err.code ?? "unknown"}: ${err.message ?? String(error)}`,
      );
      throw error;
    }
  },
);

export const getRelationshipMatches = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const summary = await loadSummary(uid);
    const data = summary.data() ?? {};
    const compatibilityKey = typeof data.compatibilityKey === "string" ? data.compatibilityKey : "";
    const questionIds = Array.isArray(data.questionIds)
      ? data.questionIds.map((item: unknown) => String(item))
      : [];
    if (!compatibilityKey || questionIds.length !== 3) {
      return {items: []};
    }
    const items = await findExactCandidates(uid, questionIds, compatibilityKey);
    return {items};
  },
);

export const syncProfileQuestionAnswers = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const answers = await loadAnswers(uid);
    const entries = Object.entries(answers);
    if (entries.length === 0) {
      return {synced: 0};
    }
    const batch = db.batch();
    for (const [questionId, answerId] of entries) {
      const ref = profileQuestionAnswerRef(uid, questionId);
      const existing = await ref.get();
      batch.set(
        ref,
        {
          questionId,
          answerId,
          isVisible: existing.exists ? profileAnswerVisible(existing.data()) : true,
          createdAt: existing.exists
            ? existing.data()?.createdAt ?? FieldValue.serverTimestamp()
            : FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    }
    await batch.commit();
    relDebug(`Profile question answers synced: ${entries.length}`);
    return {synced: entries.length};
  },
);

export const updateQuestionAnswerVisibility = onCall(
  callableOptions,
  async (request) => {
    const uid = requireUid(request);
    const questionId = String(request.data?.questionId ?? "");
    const isVisible = request.data?.isVisible === true;
    if (!/^rq_\d{3}$/.test(questionId)) {
      throw new HttpsError("invalid-argument", "invalid-question");
    }
    const ref = profileQuestionAnswerRef(uid, questionId);
    const snap = await ref.get();
    if (!snap.exists) {
      const answers = await loadAnswers(uid);
      const answerId = answers[questionId];
      if (!answerId) {
        throw new HttpsError("not-found", "answer-not-found");
      }
      await ref.set({
        questionId,
        answerId,
        isVisible,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {ok: true};
    }
    await ref.update({
      isVisible,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {ok: true};
  },
);

export async function relationshipScoreForPair(
  viewerUid: string,
  candidateUid: string,
): Promise<ReturnType<typeof scoreRelationshipCompatibility> | null> {
  const [viewer, candidate] = await Promise.all([
    db.doc(`users/${viewerUid}/relationshipMatch/summary`).get(),
    db.doc(`users/${candidateUid}/relationshipMatch/summary`).get(),
  ]);
  const viewerAnswers = answersFromSummary(viewer.data());
  const candidateAnswers = answersFromSummary(candidate.data());
  if (Object.keys(viewerAnswers).length === 0 || Object.keys(candidateAnswers).length === 0) {
    return null;
  }
  const viewerKey = viewer.data()?.compatibilityKey;
  const candidateKey = candidate.data()?.compatibilityKey;
  if (
    typeof viewerKey === "string" &&
    typeof candidateKey === "string" &&
    viewerKey.length > 0 &&
    viewerKey === candidateKey
  ) {
    return {score: 100, sharedQuestionCount: 3, alignedCount: 3, topTopics: []};
  }
  const rel = scoreRelationshipCompatibility(viewerAnswers, candidateAnswers);
  return rel.alignedCount > 0 ? rel : null;
}
