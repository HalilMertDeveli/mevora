export function canonicalMatchId(a: string, b: string): string {
  return [a, b].sort().join("_");
}

export function likeId(fromUserId: string, toUserId: string): string {
  return `${fromUserId}_${toUserId}`;
}

export function blockId(blockerId: string, blockedUserId: string): string {
  return `${blockerId}_${blockedUserId}`;
}

export function previewText(text: string, max = 80): string {
  const trimmed = text.trim();
  return trimmed.length <= max ? trimmed : `${trimmed.slice(0, max)}…`;
}
