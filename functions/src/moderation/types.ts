export type PhotoModerationStatus =
  | "pending"
  | "processing"
  | "manual_review"
  | "approved"
  | "rejected";

export interface ModerationResult {
  status: PhotoModerationStatus;
  reason?: string;
}

export interface PhotoRecord {
  id: string;
  storagePath?: string;
  downloadUrl?: string | null;
  thumbUrl?: string | null;
  moderationStatus?: string;
  moderationReason?: string | null;
  moderatedAt?: unknown;
  moderatedBy?: string | null;
  processingAttempts?: number;
  lastProcessingAttempt?: unknown;
  processingError?: string | null;
  order?: number;
  isPrimary?: boolean;
}

export const MAX_PROCESSING_ATTEMPTS = 3;
export const PROCESSING_STALE_MS = 5 * 60 * 1000;
