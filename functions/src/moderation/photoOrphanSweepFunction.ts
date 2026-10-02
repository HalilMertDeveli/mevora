import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {defineString} from "firebase-functions/params";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {photoOrphanSweepModeFrom, sweepUnreferencedPhotos} from "./photoOrphanSweep.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

/**
 * The switch for the sweep: unset or `on` deletes, `dry-run` only reports what
 * it would delete, `off` does nothing. Not a secret, not readable by clients.
 *
 * The default is empty rather than "on" because the Functions emulator copies
 * a param's default into the environment, where it would look like a choice
 * someone made.
 */
export const photoOrphanSweepSetting = defineString("PHOTO_ORPHAN_SWEEP", {default: ""});

function setting(): string {
  const fromEnv = process.env.PHOTO_ORPHAN_SWEEP?.trim();
  if (fromEnv) {
    return fromEnv;
  }
  try {
    return photoOrphanSweepSetting.value();
  } catch {
    return "";
  }
}

/**
 * Deletes profile photos that have been off their profile for longer than the
 * grace period (photoOrphanSweep.ts). Daily is enough: the grace period is
 * counted in days.
 */
export const profilePhotoOrphanSweep = onSchedule(
  {schedule: "every 24 hours", region: "europe-west1", timeoutSeconds: 540},
  async () => {
    const mode = photoOrphanSweepModeFrom(setting());
    if (mode === "off") {
      logger.info("Photo orphan sweep is switched off");
      return;
    }
    const result = await sweepUnreferencedPhotos(
      {db, bucket: () => getStorage().bucket(), now: () => Date.now()},
      {mode},
    );
    logger.info("Photo orphan sweep complete", {...result});
  },
);
