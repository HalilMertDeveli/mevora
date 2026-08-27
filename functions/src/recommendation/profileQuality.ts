/**
 * Profile Quality Score (0–100).
 *
 * Ranking / UX signal only — never hard-excludes Discover candidates.
 * Spotify is an optional bonus and never required.
 * A floor keeps sparse profiles from scoring to zero.
 */

export const PROFILE_QUALITY_FLOOR = 15;
export const PROFILE_PHOTO_TARGET = 3;
export const PROFILE_PERSONALITY_TARGET = 3;
export const MIN_BIO_LENGTH_FOR_QUALITY = 8;

/** Core weights sum to 100 without Spotify. Spotify is a capped bonus. */
export const PROFILE_QUALITY_WEIGHTS = {
  photos: 25,
  bio: 12,
  age: 8,
  location: 10,
  relationshipGoal: 10,
  personality: 20,
  completed: 10,
  activity: 5,
  /** Optional bonus — never required. */
  spotifyBonus: 5,
} as const;

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
  /** Hours since lastActiveAt; null = unknown / treat gently. */
  hoursSinceActive?: number | null;
};

export type ProfileQualityResult = {
  score: number;
  factors: Record<string, number>;
  suggestions: string[];
};

export function computeProfileQuality(input: ProfileQualityInput): ProfileQualityResult {
  const factors: Record<string, number> = {};
  const suggestions: string[] = [];

  const photoCount = Math.max(0, Number(input.photoCount ?? 0));
  const photoTarget = PROFILE_PHOTO_TARGET;
  factors.photos = Math.min(1, photoCount / photoTarget) * PROFILE_QUALITY_WEIGHTS.photos;
  if (photoCount < photoTarget) {
    suggestions.push(`add_${photoTarget - photoCount}_photos`);
  }

  factors.bio = input.hasBio ? PROFILE_QUALITY_WEIGHTS.bio : 0;
  if (!input.hasBio) {
    suggestions.push("add_bio");
  }

  factors.age = input.hasAge ? PROFILE_QUALITY_WEIGHTS.age : 0;

  factors.location = input.hasLocation ? PROFILE_QUALITY_WEIGHTS.location : 0;
  if (!input.hasLocation) {
    suggestions.push("add_location");
  }

  factors.relationshipGoal = input.hasRelationshipGoal
    ? PROFILE_QUALITY_WEIGHTS.relationshipGoal
    : 0;
  if (!input.hasRelationshipGoal) {
    suggestions.push("select_relationship_goal");
  }

  const answered = Math.max(0, Number(input.personalityAnswerCount ?? 0));
  const target = Math.max(1, Number(input.personalityAnswerTarget ?? PROFILE_PERSONALITY_TARGET));
  factors.personality = Math.min(1, answered / target) * PROFILE_QUALITY_WEIGHTS.personality;
  if (answered < target) {
    suggestions.push("complete_personality_test");
  }

  factors.completed = input.profileCompleted ? PROFILE_QUALITY_WEIGHTS.completed : 0;

  const hours = input.hoursSinceActive;
  if (hours == null) {
    factors.activity = PROFILE_QUALITY_WEIGHTS.activity * 0.6;
  } else if (hours <= 24) {
    factors.activity = PROFILE_QUALITY_WEIGHTS.activity;
  } else if (hours <= 72) {
    factors.activity = PROFILE_QUALITY_WEIGHTS.activity * 0.7;
  } else if (hours <= 14 * 24) {
    factors.activity = PROFILE_QUALITY_WEIGHTS.activity * 0.4;
  } else {
    factors.activity = PROFILE_QUALITY_WEIGHTS.activity * 0.2;
  }

  // Optional Spotify bonus — capped, never required / never listed as missing.
  factors.spotifyBonus = input.spotifyConnected ? PROFILE_QUALITY_WEIGHTS.spotifyBonus : 0;

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

  // Max without Spotify = 100; with Spotify can exceed slightly — clamp + floor.
  const score = Math.round(
    Math.min(100, Math.max(PROFILE_QUALITY_FLOOR, raw)),
  );

  return {score, factors, suggestions};
}

export type ProfileQualityDocsArgs = {
  profile?: Record<string, unknown> | null;
  user?: Record<string, unknown> | null;
  musicSummary?: Record<string, unknown> | null;
  personalityAnswerCount?: number;
  nowMs?: number;
};

export function profileQualityFromDocs(args: ProfileQualityDocsArgs): ProfileQualityResult {
  const profile = args.profile ?? {};
  const user = args.user ?? {};
  const photos = Array.isArray(profile.photos) ? profile.photos : [];
  const photoCount = countUsablePhotos(photos);
  const bio = typeof profile.bio === "string" ? profile.bio.trim() : "";
  const city = typeof profile.city === "string" ? profile.city.trim() : "";
  const lat = profile.latitude ?? profile.lat ?? user.latitude;
  const lng = profile.longitude ?? profile.lng ?? user.longitude;
  const lastActive = user.lastActiveAt ?? profile.lastActiveAt;
  const now = args.nowMs ?? Date.now();
  let hoursSinceActive: number | null = null;
  const ms = toMillis(lastActive);
  if (ms != null) {
    hoursSinceActive = (now - ms) / (60 * 60 * 1000);
  }

  const spotifyConnected =
    args.musicSummary?.spotifyConnected === true ||
    profile.spotifyConnected === true;

  return computeProfileQuality({
    photoCount,
    hasBio: bio.length >= MIN_BIO_LENGTH_FOR_QUALITY,
    hasAge: profile.age != null || profile.birthDate != null,
    hasLocation: city.length > 0 || (lat != null && lng != null),
    hasRelationshipGoal:
      typeof profile.relationshipGoal === "string" &&
      profile.relationshipGoal.trim().length > 0,
    personalityAnswerCount: args.personalityAnswerCount ?? 0,
    personalityAnswerTarget: PROFILE_PERSONALITY_TARGET,
    profileCompleted: profile.profileCompleted === true,
    spotifyConnected,
    hoursSinceActive,
  });
}

function countUsablePhotos(photos: unknown[]): number {
  let count = 0;
  for (const photo of photos) {
    if (!photo || typeof photo !== "object") {
      continue;
    }
    const record = photo as Record<string, unknown>;
    const status = String(record.moderationStatus ?? "pending");
    if (status === "rejected") {
      continue;
    }
    const hasAsset =
      (typeof record.storagePath === "string" && record.storagePath.length > 0) ||
      (typeof record.downloadUrl === "string" && record.downloadUrl.length > 0) ||
      (typeof record.thumbUrl === "string" && record.thumbUrl.length > 0);
    if (hasAsset || record.id != null) {
      count += 1;
    }
  }
  return count;
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
