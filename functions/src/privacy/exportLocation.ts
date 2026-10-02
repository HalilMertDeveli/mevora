import {GeoPoint} from "firebase-admin/firestore";

/**
 * Field names that hold an exact position, in any letter case and with the
 * leading underscore a serialised GeoPoint carries. Whole names only:
 * `relationshipGoal` and `translationLanguage` contain "lat" and "lon" too.
 */
const EXACT_LOCATION_KEY =
  /^_?(lat|lng|lon|long|latitude|longitude|geohash|geopoint|coordinates|coords)$/i;

function isGeoPoint(value: unknown): boolean {
  if (value instanceof GeoPoint) {
    return true;
  }
  // The same shape from another copy of the SDK: a class instance, not a map,
  // exposing numeric latitude and longitude.
  if (value === null || typeof value !== "object" || isPlainObject(value)) {
    return false;
  }
  const point = value as {latitude?: unknown; longitude?: unknown};
  return typeof point.latitude === "number" && typeof point.longitude === "number";
}

function isPlainObject(value: object): boolean {
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

/**
 * A copy of `value` with every exact position removed, at any depth:
 * coordinate and geohash fields by name, and GeoPoint values under any name.
 *
 * The personal data export promises to leave exact location out, and the
 * documents it copies are not all shaped by this backend — the app mirrors the
 * member's position onto their account document. Filtering the finished
 * export, rather than each field that is known today, keeps that promise when
 * a document gains a coordinate somewhere new.
 *
 * Coarse location (city, country, the time of the last update) is kept, and so
 * is every Timestamp or other non-map value. The input is not modified.
 */
export function withoutExactLocation<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.filter((item) => !isGeoPoint(item)).map((item) => withoutExactLocation(item)) as T;
  }
  if (value === null || typeof value !== "object" || !isPlainObject(value)) {
    return value;
  }
  const out: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value as Record<string, unknown>)) {
    if (EXACT_LOCATION_KEY.test(key) || isGeoPoint(child)) {
      continue;
    }
    out[key] = withoutExactLocation(child);
  }
  return out as T;
}
