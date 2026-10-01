/// Stage label of the initial humor calibration.
///
/// Kept only because the server still sends it for older builds. Nothing is
/// selected by stage any more — every member rates the same canonical items —
/// and nothing here may be used to *claim* a stage.
enum HumorCalibrationStage { anchor, adaptive, exploration, complete }

/// Client view of the initial calibration, as projected by the Cloud Functions
/// humor API: the first run of the canonical Humor Core sequence.
///
/// Carries progress only — never content ids, positions or the raw humor
/// vector. Every number comes from the server; the client knows no count of
/// its own.
class HumorCalibration {
  const HumorCalibration({
    this.version = 1,
    this.stage = HumorCalibrationStage.anchor,
    this.completedCount = 0,
    this.totalCount = 0,
    this.complete = false,
    this.insufficientPool = false,
    this.continuesTomorrow = false,
  });

  static const empty = HumorCalibration();

  final int version;
  final HumorCalibrationStage stage;
  final int completedCount;

  /// How many items the initial calibration has. Zero until the server said.
  final int totalCount;
  final bool complete;

  /// The catalogue could not provide the calibration items. Surfaced so QA
  /// and analytics can see a catalog gap instead of guessing at a short feed.
  final bool insufficientPool;

  /// Nothing is left to rate today although the calibration is not finished:
  /// an item whose media failed comes back on the next day.
  final bool continuesTomorrow;

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
    bool? continuesTomorrow,
  }) {
    return HumorCalibration(
      version: version ?? this.version,
      stage: stage ?? this.stage,
      completedCount: completedCount ?? this.completedCount,
      totalCount: totalCount ?? this.totalCount,
      complete: complete ?? this.complete,
      insufficientPool: insufficientPool ?? this.insufficientPool,
      continuesTomorrow: continuesTomorrow ?? this.continuesTomorrow,
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
      other.insufficientPool == insufficientPool &&
      other.continuesTomorrow == continuesTomorrow;

  @override
  int get hashCode => Object.hash(
    version,
    stage,
    completedCount,
    totalCount,
    complete,
    insufficientPool,
    continuesTomorrow,
  );
}
