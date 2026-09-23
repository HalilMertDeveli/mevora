/// Stage of the structured initial humor calibration.
///
/// The server owns progression entirely; this enum only labels what the client
/// was told. Nothing here may be used to *claim* a stage.
enum HumorCalibrationStage { anchor, adaptive, exploration, complete }

/// Client view of `users/{uid}/humor/calibration`, as projected by the
/// Cloud Functions humor API.
///
/// Carries progress only — never anchor slot ids, coverage internals or the
/// raw humor vector.
class HumorCalibration {
  const HumorCalibration({
    this.version = 1,
    this.stage = HumorCalibrationStage.anchor,
    this.completedCount = 0,
    this.totalCount = totalInteractions,
    this.complete = false,
    this.insufficientPool = false,
  });

  /// Initial calibration is 6 anchor + 6 adaptive + 3 exploration.
  static const int anchorInteractions = 6;
  static const int adaptiveInteractions = 6;
  static const int explorationInteractions = 3;
  static const int totalInteractions =
      anchorInteractions + adaptiveInteractions + explorationInteractions;

  static const empty = HumorCalibration();

  final int version;
  final HumorCalibrationStage stage;
  final int completedCount;
  final int totalCount;
  final bool complete;

  /// The curated pool could not fill every calibration position. Surfaced so
  /// QA and analytics can see a catalog gap instead of guessing at a short feed.
  final bool insufficientPool;

  bool get started => completedCount > 0;

  double get progress {
    if (complete || totalCount <= 0) {
      return 1;
    }
    return (completedCount / totalCount).clamp(0.0, 1.0);
  }

  int get remaining => (totalCount - completedCount).clamp(0, totalCount);

  HumorCalibration copyWith({
    int? version,
    HumorCalibrationStage? stage,
    int? completedCount,
    int? totalCount,
    bool? complete,
    bool? insufficientPool,
  }) {
    return HumorCalibration(
      version: version ?? this.version,
      stage: stage ?? this.stage,
      completedCount: completedCount ?? this.completedCount,
      totalCount: totalCount ?? this.totalCount,
      complete: complete ?? this.complete,
      insufficientPool: insufficientPool ?? this.insufficientPool,
    );
  }

  static HumorCalibrationStage parseStage(String? raw) {
    switch (raw) {
      case 'anchor':
        return HumorCalibrationStage.anchor;
      case 'adaptive':
        return HumorCalibrationStage.adaptive;
      case 'exploration':
        return HumorCalibrationStage.exploration;
      case 'complete':
        return HumorCalibrationStage.complete;
      default:
        return HumorCalibrationStage.anchor;
    }
  }

  static String stageValue(HumorCalibrationStage stage) => stage.name;

  @override
  bool operator ==(Object other) =>
      other is HumorCalibration &&
      other.version == version &&
      other.stage == stage &&
      other.completedCount == completedCount &&
      other.totalCount == totalCount &&
      other.complete == complete &&
      other.insufficientPool == insufficientPool;

  @override
  int get hashCode => Object.hash(
    version,
    stage,
    completedCount,
    totalCount,
    complete,
    insufficientPool,
  );
}
