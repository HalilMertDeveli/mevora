/// Five-level rating sent to `submitHumorFeedback`.
enum HumorRating {
  veryFunny('very_funny'),
  funny('funny'),
  neutral('neutral'),
  notFunny('not_funny'),
  notAtAll('not_at_all');

  const HumorRating(this.apiValue);

  final String apiValue;

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
