/// Canonical humor vector dimensions. Order matches Cloud Functions.
enum HumorCategory {
  sarcasm,
  absurd,
  silly,
  romantic,
  dark,
  meme,
  dry,
  wordplay,
  situational,
  cringe,
  teasing;

  String get apiValue => name;

  static HumorCategory? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    for (final value in HumorCategory.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }

  static HumorCategory parse(String raw, {HumorCategory fallback = meme}) {
    return tryParse(raw) ?? fallback;
  }
}
