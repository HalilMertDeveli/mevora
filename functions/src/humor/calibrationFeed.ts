import type {Firestore} from "firebase-admin/firestore";
import {HUMOR_CALIBRATION_VERSION} from "./calibration.js";
import {listCalibrationPool} from "./contentRepository.js";
import type {UserHumorCalibrationDoc} from "./types.js";

/**
 * Whether any curated calibration item is still unseen by this user.
 *
 * Only asked on a rare path — an *uncurated* item rated while the anchor stage
 * is open — to decide whether that rating may take an anchor position. The
 * Core sequence hands out curated items only, so members no longer reach it;
 * it stays for ratings that arrive some other way. Exact per-item check,
 * bounded by the pool size.
 */
export async function hasUnseenCuratedCandidate(input: {
  db: Firestore;
  uid: string;
  state: UserHumorCalibrationDoc;
}): Promise<boolean> {
  const pool = await listCalibrationPool(input.db, {
    calibrationVersion: HUMOR_CALIBRATION_VERSION,
    limit: 200,
  });
  const rated = new Set(input.state.ratedContentIds);
  const candidates = pool.filter((item) => !rated.has(item.contentId));
  if (candidates.length === 0) {
    return false;
  }
  const snaps = await input.db.getAll(
    ...candidates.map((item) =>
      input.db.doc(`users/${input.uid}/humorInteractions/${item.contentId}`),
    ),
  );
  return snaps.some((snap) => !snap.exists);
}
