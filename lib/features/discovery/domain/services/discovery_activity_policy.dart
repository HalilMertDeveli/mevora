/// Last-active window for **new discovery / Music Match candidates**.
///
/// Uses a fixed **90 days** (not calendar months) so Firestore and Cloud
/// Functions can compare timestamps without month-length edge cases.
/// Missing [lastActiveAt] is treated as active (new / just-registered users).
/// Existing matches and messages are never deleted by this policy.
abstract final class DiscoveryActivityPolicy {
  static const int maxInactiveDays = 90;

  static const Duration maxInactive = Duration(days: maxInactiveDays);

  /// Whether [lastActiveAt] is within the 90-day discovery window.
  ///
  /// * `null` → eligible (new user, field not written yet).
  /// * `now - lastActiveAt <= 90 days` → eligible.
  /// * older than 90 days → not a discovery candidate (until they log in again).
  static bool isEligible(DateTime? lastActiveAt, {DateTime? now}) {
    if (lastActiveAt == null) {
      return true;
    }
    final current = now ?? DateTime.now();
    return current.difference(lastActiveAt) <= maxInactive;
  }
}
