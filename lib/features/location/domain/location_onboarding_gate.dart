/// Decides whether the location permission screen should appear.
///
/// Existing users with a stored location, or anyone who already finished this
/// step (allow / skip / deny), must not see it again on every launch.
abstract final class LocationOnboardingGate {
  static bool shouldShow({
    required bool locationOnboardingCompleted,
    required bool hasStoredLocation,
  }) {
    if (hasStoredLocation || locationOnboardingCompleted) {
      return false;
    }
    return true;
  }
}
