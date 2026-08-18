# Mevora Location Architecture

This document describes location permission, GPS capture, persistence, and privacy for Mevora. Product phases still follow `MEVORA_DEVELOPMENT.md`. Data-model ownership stays in `FIREBASE_DATA_ARCHITECTURE.md`.

**Foreground only.** Mevora never requests background location, never stores a location history, and never puts coordinates on the public profile.

---

## 1. Permission flow

```text
Auth success
  → load profile + userSettings + userLocation/{uid}
      → NEW (profile incomplete)
          → Location Permission Screen (once)
              → Allow → OS dialog → GPS → userLocation/{uid}
              → then name, DOB, gender, preference, photos, interests, goal, complete, discovery
      → EXISTING (profile complete)
          → location already OK (stored coords or onboarding completed) → Main App
          → location missing → Location Permission Screen once
          → never again on every launch
```

The custom screen is **not** a grant. `[ Konumumu Aç ]` calls the real OS permission API (`LocationProvider.requestPermission` → Geolocator).

Native dialogs are not shown on page load. They are shown only from the primary button, and never when status is `deniedForever` / `restricted` (those open system settings instead).

### Screen copy (Turkish)

| Element | Copy |
| --- | --- |
| Title | Yakınındaki insanları keşfet |
| Body | Mevora, sana daha uygun eşleşmeler gösterebilmek için konumunu kullanır. |
| Sub | Konumun diğer kullanıcılara tam olarak gösterilmez. Yalnızca eşleşme ve mesafe hesaplamalarında kullanılır. |
| Primary | Konumumu Aç |
| Skip | Şimdilik Atla — eşleşme ve keşif için konum gerekir |
| Success | Harika! Yakınındaki eşleşmeleri bulmaya hazırız. |
| Locating | Konumun belirleniyor... |
| Preparing | Yakındaki eşleşmeler hazırlanıyor... |

Exact latitude / longitude is never rendered.

### UI states

| State | Meaning | Primary action |
| --- | --- | --- |
| `notDetermined` / prompt | OS has not been asked, or can still be asked | Konumumu Aç → native dialog |
| `granted` | OS permission on; capture one-shot GPS | Save and continue |
| `denied` | User said no; dialog not looped | Retry (OS may suppress) or skip |
| `deniedForever` / `restricted` | Settings only | Ayarları Aç → app settings |
| `serviceDisabled` | Device GPS off | Ayarları Aç → location settings |
| `error` | timeout, unavailable, network, invalid coords, provider | Retry / skip — never crash |
| iOS Precise Location off | Coarse fix still saved | Explain; do not block |

Skip writes `locationOnboardingCompleted: true` and `locationEnabled: false` so the screen is not shown again. Matching still needs location; discovery can prompt later without re-spamming the OS dialog.

`LocationOnboardingGate` is the pure rule:

- stored `userLocation/{uid}` **or** `locationOnboardingCompleted` → do not show
- otherwise → show once

---

## 2. Android / iOS configuration

### Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

Intentionally **absent**: `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE_LOCATION`.

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Mevora, yakındaki eşleşmeleri göstermek için konumunuzu kullanır.</string>
```

Intentionally **absent**: `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`.

When iOS Precise Location is off, `LocationProvider.checkAccuracy()` returns `reduced`. The UI explains that distance will be approximate; coordinates are still never shown.

---

## 3. Architecture (Clean + SOLID)

```text
UI (LocationPermissionPage)
  → LocationController
    → Use cases
      → LocationRepository (domain; not coupled to Firebase)
        → LocationProvider (OS GPS) / FirebaseLocationDataSource (owner doc)
```

| Piece | Role |
| --- | --- |
| `LocationProvider` | `requestPermission`, `getCurrentLocation`, `getPermissionStatus`, `openLocationSettings` |
| `LocationDevice` / `GeolocatorLocationDevice` | Geolocator adapter (medium accuracy, one-shot, timeout) |
| `LocationService` | Implements `LocationProvider`; maps GPS errors to `LocationFailure` |
| `LocationRepository` | Permission + owner persist + flags + distance label |
| `FirebaseLocationDataSource` | `userLocation/{uid}` and location flags on `userSettings/{uid}` |
| Use cases | `RequestLocationPermission`, `GetCurrentLocation`, `SaveUserLocation`, `GetLocationPermissionStatus`, `UpdateUserLocation` |

Widgets never call Geolocator or Firestore. OS permission is the source of truth. Firebase only stores app-level flags (`locationEnabled`, `lastLocationUpdate`, `locationOnboardingCompleted`) plus the private last-known point.

Client UID checks: persist/load only when `AuthUidSource.currentUid` matches the path uid (in addition to security rules).

---

## 4. Firebase

### `userLocation/{uid}` (owner read/write only)

```json
{
  "uid": "<auth uid>",
  "latitude": 41.0082,
  "longitude": 28.9784,
  "geohash": "sxk3y...",
  "updatedAt": "<server timestamp>"
}
```

- Not on `profiles/{uid}`.
- Other clients **cannot** read lat/lng.
- No history collection. Last known only; each save overwrites.

### `userSettings/{uid}` flags (owner only)

`locationEnabled`, `locationOnboardingCompleted`, `lastLocationUpdate`.

These are not GPS. They decide whether to show onboarding again and whether resume updates should run.

### Distance

`getDistanceLabel` and `getDiscoveryFeed` return labels such as `"3 km uzaklıkta"` / `"2 km away"`. The Flutter client never downloads other users' coordinates to compute distance.

---

## 5. Geohash

`GeoHash.encode(lat, lng)` (precision 9 by default) is written with the owner document so Cloud Functions can run **prefix range queries** instead of scanning every profile.

MVP discovery still filters a paged `profiles` query by distance on the backend (not on the device). The stored geohash is the hook for cheaper geo queries; do not pull the whole user set into Flutter.

---

## 6. Security rules

`userLocation/{userId}`:

- read / delete: owner
- create / update: owner, `uid == userId`, valid lat/lng, geohash string length 1..12
- everyone else: denied (catch-all `allow read, write: if false`)

`profiles/{userId}` forbids `latitude`, `longitude`, `geohash`.

---

## 7. Privacy

- Foreground / while-in-use only.
- One-shot current location after grant (not a high-accuracy stream).
- No location history.
- Analytics and Crashlytics never receive lat/lng or geohash. Events are names only (`location_permission_granted`, `location_acquired`, `location_error` with a `kind` enum).
- `AppLogger` redacts `lat` / `lng` / `longitude` assignments.
- GDPR export reports location as `{ present: bool }`, not coordinates.

---

## 8. Cost and update strategy

Writes are expensive if they happen on every GPS tick. `LocationUpdatePolicy`:

| Signal | Threshold (MVP) |
| --- | --- |
| Distance | ≥ 750 m from last saved point |
| Time | ≥ 10 minutes since last persist |
| Lifecycle | App resume, only if `locationEnabled` and OS permission is granted |

`SaveUserLocation` (onboarding) always writes. `UpdateUserLocation` applies the policy (`force: true` bypasses it).

No background isolate, no geofencing, no continuous `getPositionStream`.

---

## 9. Testing

| Layer | Coverage |
| --- | --- |
| Use cases | grant, deny, denied forever, GPS off, invalid coords, debounce |
| Repository | foreign-uid reject, no GPS capture when denied, settings openers |
| Widgets | permission, denied, loading, GPS off, error — no coordinates on screen |
| Integration (fake GPS + fake Auth) | new user allow → Firebase-shaped persist → onboarding; existing with location → main app; missing location once then skip; restart via `locationOnboardingCompleted` |
| Native config | Android foreground-only; iOS When-In-Use usage string |

Emulator GPS, Play SHA-1, and Apple location simulation are **device/CI setup**, not asserted in unit tests.

---

## 10. Remaining operational notes

- Android emulator: set a point in Extended controls → Location, or GPS stays unavailable / times out.
- Google Sign-In / App Check: debug SHA-1 / SHA-256 must be in the Firebase Android app; that is independent of location.
- iOS Simulator: Features → Location → Custom Location.
- Precise vs coarse: Android 12+ may grant only coarse; iOS 14+ may turn Precise Location off. Both are valid; UI explains reduced accuracy.
- Discovery still uses callable distance labels. Client-side haversine on other users' coords is forbidden.
