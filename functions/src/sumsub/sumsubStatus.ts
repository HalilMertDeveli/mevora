export type VerificationStatus =
  | "not_started"
  | "started"
  | "pending"
  | "approved"
  | "rejected"
  | "retry_required";

export type SumsubReviewAnswer = "GREEN" | "RED" | "YELLOW" | string;

export type SumsubWebhookPayload = {
  type?: string;
  applicantId?: string;
  externalUserId?: string;
  reviewStatus?: string;
  reviewResult?: {
    reviewAnswer?: SumsubReviewAnswer;
    rejectLabels?: string[];
    reviewRejectType?: string;
  };
  testMode?: boolean;
};

/** Maps Sumsub webhook / review signals to internal verification status. */
export function mapSumsubToVerificationStatus(payload: SumsubWebhookPayload): VerificationStatus {
  const type = String(payload.type ?? "");
  const reviewStatus = String(payload.reviewStatus ?? "").toLowerCase();
  const answer = String(payload.reviewResult?.reviewAnswer ?? "").toUpperCase();

  if (type === "applicantPending" || reviewStatus === "pending" || reviewStatus === "queued") {
    return "pending";
  }
  if (type === "applicantOnHold" || reviewStatus === "onhold" || reviewStatus === "on_hold") {
    return "pending";
  }
  if (type === "applicantCreated" || type === "applicantPersonalInfoChanged") {
    return "started";
  }
  if (type === "applicantReviewed" || reviewStatus === "completed") {
    if (answer === "GREEN") {
      return "approved";
    }
    if (answer === "RED") {
      const rejectType = String(payload.reviewResult?.reviewRejectType ?? "").toLowerCase();
      if (rejectType === "retry" || rejectType === "external") {
        return "retry_required";
      }
      return "rejected";
    }
    return "pending";
  }
  if (type === "applicantReset") {
    return "retry_required";
  }
  return "pending";
}

export function isTerminalStatus(status: VerificationStatus): boolean {
  return status === "approved" || status === "rejected";
}

export function shouldSetVerified(status: VerificationStatus): boolean {
  return status === "approved";
}
