export enum JobKind {
  accountDeletionVerify = "accountDeletionVerify",
}

export type AutomationJob = {
  kind: JobKind;
  idempotencyKey: string;
  payload: Record<string, unknown>;
  createdBy?: string;
};
