import type {Firestore} from "firebase-admin/firestore";
import {isEmulatorProcess} from "./faceAnchorConfig.js";
import {
  FaceProviderError,
  type FaceMatchOutcome,
  type FaceVerificationProvider,
  type LivenessOutcome,
} from "./provider.js";

/**
 * Emulator-only stand-in for the verification provider.
 *
 * The outcome is trusted local server state: a document only the Admin SDK can
 * write (devControl/* is denied to every client by the rules), set with
 * tool/faceAnchorDev.cjs. Nothing a client sends selects this provider or its
 * answer — it is chosen by resolveFaceVerificationProvider from the process
 * environment, and it refuses to exist anywhere else.
 */

export const FAKE_OUTCOMES = ["success", "liveness_failed", "face_mismatch", "provider_error"] as const;
export type FakeOutcome = (typeof FAKE_OUTCOMES)[number];

export const FACE_ANCHOR_DEV_CONTROL_DOC = "devControl/faceAnchor";

export class EmulatorFakeFaceProvider implements FaceVerificationProvider {
  readonly id = "emulator-fake";

  /** Read once per verification so liveness and match agree on one outcome. */
  private outcome: Promise<FakeOutcome> | null = null;

  constructor(private readonly db: Firestore) {
    if (!isEmulatorProcess()) {
      throw new Error("EmulatorFakeFaceProvider is not available outside the emulator");
    }
  }

  private resolveOutcome(): Promise<FakeOutcome> {
    this.outcome ??= (async () => {
      const ref = this.db.doc(FACE_ANCHOR_DEV_CONTROL_DOC);
      const snap = await ref.get();
      const raw = snap.data()?.outcome;
      const outcome = (FAKE_OUTCOMES as readonly string[]).includes(String(raw))
        ? (raw as FakeOutcome)
        : "success";
      if (snap.data()?.once === true) {
        await ref.delete();
      }
      return outcome;
    })();
    return this.outcome;
  }

  async checkLiveness(): Promise<LivenessOutcome> {
    const outcome = await this.resolveOutcome();
    if (outcome === "provider_error") {
      throw new FaceProviderError("emulator-fake-outage", true);
    }
    return outcome === "liveness_failed" ? "not_live" : "live";
  }

  async matchFaces(): Promise<FaceMatchOutcome> {
    const outcome = await this.resolveOutcome();
    if (outcome === "provider_error") {
      throw new FaceProviderError("emulator-fake-outage", true);
    }
    return outcome === "face_mismatch" ? "no_match" : "match";
  }
}
