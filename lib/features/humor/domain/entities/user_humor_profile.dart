import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
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
    this.profileBuilding = true,
    this.topVibes = const [],
    this.vector = const {},
    this.exploredCategories = const [],
    this.version = 1,
    this.calibration = HumorCalibration.empty,
  });

  static const empty = UserHumorProfile();

  final double confidence;
  final int interactionCount;

  /// True while *initial calibration* is still running.
  ///
  /// This is no longer "the profile has stopped learning" — lifetime learning
  /// continues indefinitely past calibration. Read [calibration] for the
  /// structured milestone and [interactionCount] for lifetime volume.
  final bool profileBuilding;
  final List<HumorVibe> topVibes;
  final Map<HumorCategory, double> vector;
  final List<String> exploredCategories;
  final int version;
  final HumorCalibration calibration;

  /// Lifetime learning never stops; only the initial milestone completes.
  bool get calibrationComplete => calibration.complete;

  UserHumorProfile copyWith({
    double? confidence,
    int? interactionCount,
    bool? profileBuilding,
    List<HumorVibe>? topVibes,
    Map<HumorCategory, double>? vector,
    List<String>? exploredCategories,
    int? version,
    HumorCalibration? calibration,
  }) {
    return UserHumorProfile(
      confidence: confidence ?? this.confidence,
      interactionCount: interactionCount ?? this.interactionCount,
      profileBuilding: profileBuilding ?? this.profileBuilding,
      topVibes: topVibes ?? this.topVibes,
      vector: vector ?? this.vector,
      exploredCategories: exploredCategories ?? this.exploredCategories,
      version: version ?? this.version,
      calibration: calibration ?? this.calibration,
    );
  }
}

class HumorFeedbackResult {
  const HumorFeedbackResult({
    required this.ok,
    required this.profileBuilding,
    required this.interactionCount,
    required this.confidence,
    this.calibration = HumorCalibration.empty,
  });

  final bool ok;
  final bool profileBuilding;
  final int interactionCount;
  final double confidence;

  /// Calibration progress after this rating, as computed by the server.
  final HumorCalibration calibration;
}
