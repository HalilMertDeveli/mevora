export type IncomingLikeRow = {
  fromUserId: string;
  action: string;
  createdAtMs: number | null;
};

export type IncomingLikeItem = {
  uid: string;
  displayName: string;
  age: number | null;
  photoUrl: string | null;
  city: string | null;
  action: string;
  createdAtMs: number | null;
  compatibilityScore?: number;
  compatibilityBreakdown?: {
    overallScore: number;
    relationshipScore: number;
    interestScore: number;
    lifestyleScore: number;
    questionScore: number | null;
    musicScore: number | null;
    communicationScore: number | null;
  };
  sharedInterests?: string[];
  compatibilityReasons?: string[];
};

export type IncomingLikesPayload = {
  locked: boolean;
  isPremium: boolean;
  premiumRequired: boolean;
  count: number;
  /** Alias for clients that prefer explicit naming. */
  incomingLikeCount: number;
  items: IncomingLikeItem[];
};

/** Pure gate: free users never receive identity-bearing items. */
export function shapeIncomingLikesResponse(input: {
  isPremium: boolean;
  rows: IncomingLikeRow[];
  profiles: Map<string, IncomingLikeItem>;
}): IncomingLikesPayload {
  const seen = new Set<string>();
  const unique = input.rows.filter((row) => {
    if (!row.fromUserId || seen.has(row.fromUserId)) {
      return false;
    }
    seen.add(row.fromUserId);
    return true;
  });
  if (!input.isPremium) {
    return {
      locked: true,
      isPremium: false,
      premiumRequired: true,
      count: unique.length,
      incomingLikeCount: unique.length,
      items: [],
    };
  }
  const items: IncomingLikeItem[] = [];
  for (const row of unique) {
    const profile = input.profiles.get(row.fromUserId);
    if (profile) {
      items.push(profile);
    }
  }
  return {
    locked: false,
    isPremium: true,
    premiumRequired: false,
    count: unique.length,
    incomingLikeCount: unique.length,
    items,
  };
}
