/**
 * Pure match-participant gate for Compatibility Reveal (unit-testable).
 * Used by getMatchCompatibilityReveal before any profile/taste reads.
 */
export type MatchParticipantGateInput = {
  matchId: string;
  uid: string;
  matchExists: boolean;
  /** When explicitly false → inactive. Undefined treated as active. */
  isActive: boolean | undefined;
  userIds: unknown;
  canonicalMatchId: (a: string, b: string) => string;
};

export type MatchParticipantGateResult =
  | {ok: true; peerUid: string}
  | {ok: false; code: "not-found" | "match-inactive" | "not-a-participant" | "peer-missing" | "match-id-mismatch"};

export function resolveMatchParticipant(
  input: MatchParticipantGateInput,
): MatchParticipantGateResult {
  if (!input.matchExists) {
    return {ok: false, code: "not-found"};
  }
  if (input.isActive === false) {
    return {ok: false, code: "match-inactive"};
  }
  const userIds = Array.isArray(input.userIds)
    ? input.userIds.map((id) => String(id))
    : [];
  if (!userIds.includes(input.uid) || userIds.length !== 2) {
    return {ok: false, code: "not-a-participant"};
  }
  const peerUid = userIds.find((id) => id !== input.uid);
  if (!peerUid) {
    return {ok: false, code: "peer-missing"};
  }
  if (input.canonicalMatchId(input.uid, peerUid) !== input.matchId) {
    return {ok: false, code: "match-id-mismatch"};
  }
  return {ok: true, peerUid};
}

/** Payload must never carry raw answer text / answerIds. */
export function revealPayloadLeaksAnswerText(payload: {
  points?: Array<{messageKey?: string; messageArgs?: unknown[]}>;
}): boolean {
  const points = payload.points ?? [];
  for (const point of points) {
    const key = point.messageKey ?? "";
    // Question copy uses counts only — never answer choice ids as sole args
    // unless paired with shared/aligned count keys.
    if (key.includes("AnswerText") || key.includes("answerId")) {
      return true;
    }
    for (const arg of point.messageArgs ?? []) {
      if (typeof arg === "string" && /answerText|answerId/i.test(arg)) {
        return true;
      }
    }
  }
  return false;
}
