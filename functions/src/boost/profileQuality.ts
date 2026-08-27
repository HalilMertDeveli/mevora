/**
 * ProfileQualityScore (0–100) — ranking / Smart Boost advice signal.
 * Never hard-excludes from Discover. Spotify is optional bonus only.
 */
export type ProfileQualityInput = {
  photoCount?: number;
  hasBio?: boolean;
  hasAge?: boolean;
  hasLocation?: boolean;
  hasRelationshipGoal?: boolean;
  personalityAnswerCount?: number;
  personalityAnswerTarget?: number;
  profileCompleted?: boolean;
  spotifyConnected?: boolean;
  hoursSinceActive?: number | null;
};

export type ProfileQualityBreakdown = {
  score: number;
  factors: Record<string, number>;
  suggestions: string[];
};

const WEIGHTS = {
  photos: 25,
  bio: 12,
  age: 8,
  location: 10,
  relationshipGoal: 10,
  personality: 20,
  completed: 10,
  activity: 5,
  spotifyBonus: 5,
} as const;

export function computeProfileQuality(
  input: ProfileQualityInput,
): ProfileQualityBreakdown {
  const factors: Record<string, number> = {};
  const suggestions: string[] = [];
  const photoCount = Math.max(0, Number(input.photoCount ?? 0));
  const photoTarget = 3;

  factors.photos = Math.min(1, photoCount / photoTarget) * WEIGHTS.photos;
  if (photoCount < photoTarget) {
    suggestions.push(`add_${photoTarget - photoCount}_photos`);
  }

  factors.bio = input.hasBio ? WEIGHTS.bio : 0;
  if (!input.hasBio) {
    suggestions.push("add_bio");
  }

  factors.age = input.hasAge ? WEIGHTS.age : 0;
  factors.location = input.hasLocation ? WEIGHTS.location : 0;
  if (!input.hasLocation) {
    suggestions.push("add_location");
  }

  factors.relationshipGoal = input.hasRelationshipGoal
    ? WEIGHTS.relationshipGoal
    : 0;
  if (!input.hasRelationshipGoal) {
    suggestions.push("select_relationship_goal");
  }

  const answered = Math.max(0, Number(input.personalityAnswerCount ?? 0));
  const target = Math.max(1, Number(input.personalityAnswerTarget ?? 3));
  factors.personality = Math.min(1, answered / target) * WEIGHTS.personality;
  if (answered < target) {
    suggestions.push("complete_personality_test");
  }

  factors.completed = input.profileCompleted ? WEIGHTS.completed : 0;

  const hours = input.hoursSinceActive;
  if (hours == null) {
    factors.activity = WEIGHTS.activity * 0.6;
  } else if (hours <= 24) {
    factors.activity = WEIGHTS.activity;
  } else if (hours <= 72) {
    factors.activity = WEIGHTS.activity * 0.7;
  } else if (hours <= 14 * 24) {
    factors.activity = WEIGHTS.activity * 0.4;
  } else {
    factors.activity = WEIGHTS.activity * 0.2;
  }

  factors.spotifyBonus = input.spotifyConnected ? WEIGHTS.spotifyBonus : 0;

  const raw =
    factors.photos +
    factors.bio +
    factors.age +
    factors.location +
    factors.relationshipGoal +
    factors.personality +
    factors.completed +
    factors.activity +
    factors.spotifyBonus;

  const score = Math.round(Math.min(100, Math.max(0, raw)));
  return {score, factors, suggestions};
}

export function profileQualityFromDocs(args: {
  profile?: Record<string, unknown> | null;
  user?: Record<string, unknown> | null;
  musicSummary?: Record<string, unknown> | null;
  personalityAnswerCount?: number;
  nowMs?: number;
}): ProfileQualityBreakdown {
  const profile = args.profile ?? {};
  const user = args.user ?? {};
  const photos = Array.isArray(profile.photos) ? profile.photos : [];
  const bio = typeof profile.bio === "string" ? profile.bio.trim() : "";
  const lat = profile.latitude ?? profile.lat ?? user.latitude;
  const lng = profile.longitude ?? profile.lng ?? user.longitude;
  const lastActive = user.lastActiveAt ?? profile.lastActiveAt;
  const now = args.nowMs ?? Date.now();
  let hoursSinceActive: number | null = null;
  const ms = toMillis(lastActive);
  if (ms != null) {
    hoursSinceActive = (now - ms) / (60 * 60 * 1000);
  }

  return computeProfileQuality({
    photoCount: photos.length,
    hasBio: bio.length >= 8,
    hasAge: profile.age != null || profile.birthDate != null,
    hasLocation: lat != null && lng != null,
    hasRelationshipGoal:
      typeof profile.relationshipGoal === "string" &&
      profile.relationshipGoal.length > 0,
    personalityAnswerCount: args.personalityAnswerCount ?? 0,
    personalityAnswerTarget: 3,
    profileCompleted: profile.profileCompleted === true,
    spotifyConnected: args.musicSummary?.spotifyConnected === true,
    hoursSinceActive,
  });
}

function toMillis(value: unknown): number | null {
  if (value == null) {
    return null;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (value instanceof Date) {
    return value.getTime();
  }
  if (typeof value === "object") {
    const record = value as {toMillis?: () => number; toDate?: () => Date};
    if (typeof record.toMillis === "function") {
      return record.toMillis();
    }
    if (typeof record.toDate === "function") {
      return record.toDate().getTime();
    }
  }
  return null;
}
