/**
 * Message rate limits, decided from one counter document per sender
 * (`users/{uid}/rateLimits/messages`) instead of reading the match's recent
 * messages on every send.
 *
 * Both limits share one fixed 60 s window: 20 messages per match and 60
 * overall. A rejected message is not counted. The ids already counted in
 * the window make a redelivered trigger for the same message a no-op
 * instead of a second count.
 */
export const MESSAGE_RATE_WINDOW_MS = 60_000;
export const MAX_MESSAGES_PER_MATCH = 20;
export const MAX_MESSAGES_GLOBAL = 60;

export interface MessageRateState {
  windowStartMs: number;
  count: number;
  perMatch: Record<string, number>;
  messageIds: string[];
}

export type MessageRateDecision =
  | {action: "duplicate"}
  | {action: "reject"; reason: "match" | "global"}
  | {action: "accept"; state: MessageRateState};

/** Reads the stored counter; anything malformed counts as an empty window. */
export function parseMessageRateState(
  data: Record<string, unknown> | undefined,
  windowStartMs: number,
): MessageRateState {
  const perMatch: Record<string, number> = {};
  const rawPerMatch = data?.perMatch;
  if (rawPerMatch && typeof rawPerMatch === "object") {
    for (const [matchId, value] of Object.entries(rawPerMatch)) {
      const n = Number(value);
      if (Number.isFinite(n) && n > 0) {
        perMatch[matchId] = n;
      }
    }
  }
  const rawIds = data?.messageIds;
  return {
    windowStartMs,
    count: Math.max(0, Number(data?.count ?? 0) || 0),
    perMatch,
    messageIds: Array.isArray(rawIds) ? rawIds.map(String) : [],
  };
}

export function messageRateDecision(
  stored: MessageRateState,
  input: {matchId: string; messageId: string; nowMs: number},
): MessageRateDecision {
  const expired = input.nowMs - stored.windowStartMs > MESSAGE_RATE_WINDOW_MS;
  const state: MessageRateState = expired
    ? {windowStartMs: input.nowMs, count: 0, perMatch: {}, messageIds: []}
    : stored;
  if (state.messageIds.includes(input.messageId)) {
    return {action: "duplicate"};
  }
  const inMatch = state.perMatch[input.matchId] ?? 0;
  if (inMatch >= MAX_MESSAGES_PER_MATCH) {
    return {action: "reject", reason: "match"};
  }
  if (state.count >= MAX_MESSAGES_GLOBAL) {
    return {action: "reject", reason: "global"};
  }
  return {
    action: "accept",
    state: {
      windowStartMs: state.windowStartMs,
      count: state.count + 1,
      perMatch: {...state.perMatch, [input.matchId]: inMatch + 1},
      messageIds: [...state.messageIds, input.messageId],
    },
  };
}
