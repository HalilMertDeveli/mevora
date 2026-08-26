import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';

/// Future premium gating for compatibility features (no payment wired yet).
abstract final class CompatibilityFeatureGate {
  static const bool fullBreakdownEnabled = true;
  static const bool hiddenCompatibilityEnabled = true;
  static const bool advancedFiltersEnabled = false;

  static bool canShowFullBreakdown(CompatibilityBreakdown breakdown) {
    if (!fullBreakdownEnabled) {
      return breakdown.dataQuality == CompatibilityDataQuality.sufficient;
    }
    return true;
  }
}
