import type {Firestore} from "firebase-admin/firestore";
import {resolveDiditFaceConfig} from "../identity/didit/diditConfig.js";
import {DiditFaceClient} from "../identity/didit/diditFaceClient.js";
import {DiditFaceProvider} from "./diditFaceProvider.js";
import {
  isEmulatorProcess,
  resolveLivenessThreshold,
  resolveMatchThreshold,
} from "./faceAnchorConfig.js";
import {PROVIDER_TIMEOUT_MS} from "./faceAnchorRecord.js";
import {EmulatorFakeFaceProvider} from "./fakeProvider.js";
import type {FaceVerificationProvider} from "./provider.js";

/**
 * Which provider answers, decided from the server's own environment and
 * nothing else. There is no request field, header or document a client can
 * write that reaches this function.
 *
 * - Emulator: the fake, always. A test run never contacts Didit.
 * - Deployed: Didit, but only when an API key is present **and** the
 *   deployment has been declared live. A sandbox key answers the standalone
 *   biometric APIs with a canned approval, so an undeclared environment gets no
 *   provider at all rather than one that verifies everybody.
 *
 * Null means "cannot verify" and every caller fails closed on it.
 */
export function resolveFaceVerificationProvider(db: Firestore): FaceVerificationProvider | null {
  if (isEmulatorProcess()) {
    return new EmulatorFakeFaceProvider(db);
  }
  const config = resolveDiditFaceConfig();
  if (!config || config.environment !== "live") {
    return null;
  }
  return new DiditFaceProvider(
    new DiditFaceClient({apiKey: config.apiKey, baseUrl: config.baseUrl, timeoutMs: PROVIDER_TIMEOUT_MS}),
    {liveness: resolveLivenessThreshold(), match: resolveMatchThreshold()},
  );
}
