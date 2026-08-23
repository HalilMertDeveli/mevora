/**
 * Sumsub applicant data lifecycle hooks.
 *
 * Firestore verification docs are removed in deleteUserAccount.
 * Sumsub-side applicant deletion requires credentials and a separate API call.
 * TODO(sumsub-activation): call Sumsub applicant reset/delete API when configured.
 */
export async function requestSumsubApplicantDeletion(input: {
  uid: string;
  applicantId?: string;
}): Promise<void> {
  if (!input.applicantId) {
    return;
  }
  // Placeholder — implement with SumsubClient when production credentials exist.
  void input.uid;
}
