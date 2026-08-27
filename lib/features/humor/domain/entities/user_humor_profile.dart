import 'package:mevora/features/humor/domain/entities/humor_category.dart';

class HumorVibe {
  const HumorVibe({required this.category, required this.value});

  final HumorCategory category;
  final int value;
}

/// Client view of `getHumorProfile` (basic or detailed).
class UserHumorProfile {
  const UserHumorProfile({
    this.confidence = 0,
    this.interactionCount = 0,
    this.funnyCount = 0,
    this.notFunnyCount = 0,
    this.profileBuilding = true,
    this.topVibes = const [],
    this.vector = const {},
    this.exploredCategories = const [],
    this.version = 1,
  });

  static const empty = UserHumorProfile();

  final double confidence;
  final int interactionCount;
  final int funnyCount;
  final int notFunnyCount;
  final bool profileBuilding;
  final List<HumorVibe> topVibes;
  final Map<HumorCategory, double> vector;
  final List<String> exploredCategories;
  final int version;

  UserHumorProfile copyWith({
    double? confidence,
    int? interactionCount,
    int? funnyCount,
    int? notFunnyCount,
    bool? profileBuilding,
    List<HumorVibe>? topVibes,
    Map<HumorCategory, double>? vector,
    List<String>? exploredCategories,
    int? version,
  }) {
    return UserHumorProfile(
      confidence: confidence ?? this.confidence,
      interactionCount: interactionCount ?? this.interactionCount,
      funnyCount: funnyCount ?? this.funnyCount,
      notFunnyCount: notFunnyCount ?? this.notFunnyCount,
      profileBuilding: profileBuilding ?? this.profileBuilding,
      topVibes: topVibes ?? this.topVibes,
      vector: vector ?? this.vector,
      exploredCategories: exploredCategories ?? this.exploredCategories,
      version: version ?? this.version,
    );
  }
}

class HumorFeedbackResult {
  const HumorFeedbackResult({
    required this.ok,
    required this.profileBuilding,
    required this.interactionCount,
    required this.confidence,
    this.funnyCount = 0,
    this.notFunnyCount = 0,
  });

  final bool ok;
  final bool profileBuilding;
  final int interactionCount;
  final double confidence;
  final int funnyCount;
  final int notFunnyCount;
}
