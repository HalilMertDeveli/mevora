/// Binary Humor Lab rating sent to `submitHumorFeedback`.
///
/// Live API accepts only [funny] and [notFunny].
/// Legacy five-level strings remain parseable for older interaction docs.
enum HumorRating {
  funny('funny'),
  notFunny('not_funny'),
  /// Legacy stored value — not shown in UI.
  veryFunny('very_funny'),
  /// Legacy / internal skip mapping — not shown in UI.
  neutral('neutral'),
  /// Legacy stored value — not shown in UI.
  notAtAll('not_at_all');

  const HumorRating(this.apiValue);

  final String apiValue;

  /// Ratings exposed in the Humor Lab UI.
  static const binaryChoices = <HumorRating>[funny, notFunny];

  bool get isBinary => this == funny || this == notFunny;

  static HumorRating? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final value in HumorRating.values) {
      if (value.apiValue == raw || value.name == raw) {
        return value;
      }
    }
    return null;
  }
}
