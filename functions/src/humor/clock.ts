import type {Firestore} from "firebase-admin/firestore";
import {canonicalDayId, isDayId} from "./daily.js";

/**
 * Emulator-only clock override: `devClock/humorDaily {dayId}`. Read only when
 * the process runs inside the Functions emulator, so a deployed function can
 * never be steered to another day. Clients cannot write it (rules deny).
 */
export const DAILY_DEV_CLOCK_DOC = "devClock/humorDaily";

export function isEmulatorProcess(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

/** Today's canonical day id. Server clock; emulator override only in the emulator. */
export async function resolveDailyToday(db: Firestore, nowMs: number): Promise<string> {
  if (isEmulatorProcess()) {
    const clock = await db.doc(DAILY_DEV_CLOCK_DOC).get();
    const override = clock.data()?.dayId;
    if (isDayId(override)) {
      return override;
    }
  }
  return canonicalDayId(nowMs);
}
