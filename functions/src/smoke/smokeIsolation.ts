/**
 * Smoke-test isolation in Discover: a smoke account and a real member never
 * see each other.
 *
 * This lives apart from `smokeTestUsers.ts` on purpose. Discovery runs in a
 * deployed backend and needs this rule there (it is restrictive: it only ever
 * removes candidates), while the smoke callables and their secret are
 * emulator-only. Importing the rule from the callables' module would load
 * that module, and declare its secret, in every deploy.
 */
export function isSmokeTestUser(data: Record<string, unknown> | undefined): boolean {
  return data?.isSmokeTestUser === true;
}

export function passesSmokeDiscoveryIsolation(
  viewerAccount: Record<string, unknown> | undefined,
  candidateAccount: Record<string, unknown> | undefined,
): boolean {
  const viewerSmoke = isSmokeTestUser(viewerAccount);
  const candidateSmoke = isSmokeTestUser(candidateAccount);
  if (!viewerSmoke && !candidateSmoke) {
    return true;
  }
  return viewerSmoke && candidateSmoke;
}
