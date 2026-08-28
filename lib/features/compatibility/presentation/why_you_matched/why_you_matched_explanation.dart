/// Localized, user-facing lines for one Why You Matched reason.
class WhyYouMatchedExplanation {
  const WhyYouMatchedExplanation({
    required this.reasonId,
    required this.title,
    required this.body,
    required this.categoryWire,
  });

  final String reasonId;
  final String title;
  final String body;
  final String categoryWire;

  /// Combined short blurb (title + body) for accessibility / previews.
  String get combined => '$title $body'.trim();
}
