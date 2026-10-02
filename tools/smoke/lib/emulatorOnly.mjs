/**
 * The smoke harness runs against the Firebase emulator suite and nowhere else.
 *
 * It writes through the Admin SDK — accounts, profiles, photos, a match, a
 * block, a report — and the backend gives smoke accounts no special treatment
 * outside the emulator: the smoke callables are not deployed and the photo
 * fast path does not apply. Pointed at a live project it would only leave test
 * data behind. So it refuses to start unless it was asked for the emulator
 * AND every service it talks to resolves to an emulator on this machine; the
 * Admin SDK follows the *_EMULATOR_HOST variables, not SMOKE_USE_EMULATOR, so
 * the flag alone proves nothing.
 *
 * No dependencies on purpose: this is checked before anything is initialised.
 */
const LOOPBACK_HOST = /^(?:127(?:\.\d{1,3}){3}|localhost|\[::1\]):\d{1,5}$/i;

/** The emulators the harness writes to, by the variable the Admin SDK reads. */
export const SMOKE_EMULATOR_HOST_VARS = [
  "FIRESTORE_EMULATOR_HOST",
  "FIREBASE_AUTH_EMULATOR_HOST",
  "FIREBASE_STORAGE_EMULATOR_HOST",
];

/** The project the emulator suite runs as. There is no default. */
export function smokeProjectId(env = process.env) {
  return env.SMOKE_FIREBASE_PROJECT || env.GCLOUD_PROJECT || null;
}

/** Why this environment may not run the harness; empty when it may. */
export function smokeTargetProblems(env = process.env) {
  const problems = [];
  if (env.SMOKE_USE_EMULATOR !== "true") {
    problems.push(
      "SMOKE_USE_EMULATOR=true is required: the smoke harness runs against the Firebase emulator suite only",
    );
  }
  for (const name of SMOKE_EMULATOR_HOST_VARS) {
    const value = env[name];
    if (!value || !LOOPBACK_HOST.test(value)) {
      problems.push(`${name} must point at an emulator on this machine (e.g. 127.0.0.1:<port>); got "${value ?? ""}"`);
    }
  }
  if (!smokeProjectId(env)) {
    problems.push("SMOKE_FIREBASE_PROJECT (or GCLOUD_PROJECT) must name the project the emulator suite runs as");
  }
  return problems;
}
