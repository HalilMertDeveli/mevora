/// Shared motion timings. Keep most of the UI still; use these only for
/// short micro-interactions.
abstract final class AppDurations {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration button = Duration(milliseconds: 170);
  static const Duration short = Duration(milliseconds: 180);
  static const Duration page = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration discoveryCard = Duration(milliseconds: 260);
  static const Duration photo = Duration(milliseconds: 220);
  static const Duration like = Duration(milliseconds: 280);
  static const Duration pass = Duration(milliseconds: 240);
  static const Duration long = Duration(milliseconds: 400);

  /// Compact tab/route accent — keep short so it never feels like a wait.
  static const Duration coverShrink = Duration(milliseconds: 320);
  static const Duration match = Duration(milliseconds: 720);
  static const Duration relationshipPrompt = Duration(minutes: 30);
}
