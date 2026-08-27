/** Minimal stubs so TypeScript resolves automation imports on this branch. */

export async function cleanupOldCalls(_options?: {
  olderThanMs?: number;
  dryRun?: boolean;
  limit?: number;
  requireAdminApproval?: boolean;
}): Promise<{deleted: number}> {
  return {deleted: 0};
}

export async function cleanupOldNotifications(_options?: {
  olderThanMs?: number;
  dryRun?: boolean;
  limit?: number;
  requireAdminApproval?: boolean;
}): Promise<{deleted: number}> {
  return {deleted: 0};
}
