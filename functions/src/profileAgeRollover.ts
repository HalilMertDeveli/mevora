import {getApps, initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {logger} from "firebase-functions";
import {rollOverProfileAges} from "./profileAge.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

/**
 * Keeps profiles/{uid}.age current. The date of birth it is derived from is
 * private to the member's account, so no client can recompute the age it shows
 * for someone else — this is the only thing that moves it after onboarding.
 */
export const profileAgeRollover = onSchedule(
  {schedule: "every day 00:10", region: "europe-west1"},
  async () => {
    const result = await rollOverProfileAges(db);
    if (result.due > 0) {
      logger.info("profile age roll-over", result);
    }
  },
);
