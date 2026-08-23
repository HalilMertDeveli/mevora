import 'package:flutter/foundation.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_breakdown_mapper.dart';
import 'package:mevora/features/compatibility/domain/services/mevora_compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/compatibility/compatibility_engine.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_filters.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Single source of truth for discover compatibility score + breakdown.
abstract final class CompatibilityScoreResolver {
  static DiscoveryCandidate resolve({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    DiscoveryFilters filters = const DiscoveryFilters(),
  }) {
    final serverScore = _serverOverallScore(candidate);
    if (serverScore != null && serverScore > 0) {
      return candidate.copyWith(
        compatibilityScore: serverScore,
        compatibilityStatus: CompatibilityDisplayStatus.ready,
        sharedInterests: candidate.sharedInterests.isNotEmpty
            ? candidate.sharedInterests
            : _sharedInterests(viewer, candidate),
      );
    }

    final breakdown = _breakdown(
      viewer: viewer,
      candidate: candidate,
      filters: filters,
    );

    if (breakdown.dataQuality == CompatibilityDataQuality.insufficient ||
        breakdown.overallScore <= 0 ||
        !_hasMeaningfulSignals(viewer: viewer, candidate: candidate)) {
      _debug(
        'unavailable ${viewer.uid}↔${candidate.uid} '
        'quality=${breakdown.dataQuality} overall=${breakdown.overallScore}',
      );
      return candidate.copyWith(
        compatibilityStatus: CompatibilityDisplayStatus.unavailable,
      );
    }

    _debug(
      'resolved ${viewer.uid}↔${candidate.uid} → ${breakdown.overallScore}% '
      '(interests=${breakdown.interestScore}, goal=${breakdown.relationshipScore})',
    );

    return candidate.copyWith(
      compatibilityScore: breakdown.overallScore,
      compatibilityStatus: CompatibilityDisplayStatus.ready,
      sharedInterests: breakdown.sharedInterests.isNotEmpty
          ? breakdown.sharedInterests
          : _sharedInterests(viewer, candidate),
      categoryRelationshipScore: breakdown.relationshipScore,
      categoryInterestScore: breakdown.interestScore,
      categoryLifestyleScore: breakdown.lifestyleScore,
      categoryQuestionScore: breakdown.questionScore,
      categoryMusicScore: breakdown.musicScore,
      categoryCommunicationScore: breakdown.communicationScore,
    );
  }

  static CompatibilityBreakdown breakdownFor({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    DiscoveryFilters filters = const DiscoveryFilters(),
  }) {
    final serverScore = _serverOverallScore(candidate);
    if (serverScore != null &&
        serverScore > 0 &&
        candidate.categoryRelationshipScore != null) {
      return CompatibilityBreakdownMapper.fromCandidate(candidate).copyWith(
        overallScore: serverScore,
        dataQuality: CompatibilityDataQuality.sufficient,
      );
    }
    return _breakdown(viewer: viewer, candidate: candidate, filters: filters);
  }

  static int? _serverOverallScore(DiscoveryCandidate candidate) {
    if (candidate.compatibilityScore > 0) {
      return candidate.compatibilityScore;
    }
    final categories = [
      candidate.categoryRelationshipScore,
      candidate.categoryInterestScore,
      candidate.categoryLifestyleScore,
    ];
    if (categories.any((score) => score != null && score > 0)) {
      return candidate.compatibilityScore > 0
          ? candidate.compatibilityScore
          : _weightedFromCategories(candidate);
    }
    return null;
  }

  static int _weightedFromCategories(DiscoveryCandidate candidate) {
    final parts = <double>[];
    void add(int? value, double weight) {
      if (value != null && value > 0) {
        parts.add(value * weight);
      }
    }

    add(candidate.categoryInterestScore, 0.35);
    add(candidate.categoryRelationshipScore, 0.25);
    add(candidate.categoryLifestyleScore, 0.2);
    add(candidate.categoryQuestionScore, 0.15);
    add(candidate.categoryMusicScore, 0.15);
    if (parts.isEmpty) {
      return 0;
    }
    final weightSum = [
      if (candidate.categoryInterestScore != null) 0.35,
      if (candidate.categoryRelationshipScore != null) 0.25,
      if (candidate.categoryLifestyleScore != null) 0.2,
      if (candidate.categoryQuestionScore != null) 0.15,
      if (candidate.categoryMusicScore != null) 0.15,
    ].fold<double>(0, (a, b) => a + b);
    final sum = parts.fold<double>(0, (a, b) => a + b);
    return (sum / weightSum).round().clamp(1, 100);
  }

  static CompatibilityBreakdown _breakdown({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
    required DiscoveryFilters filters,
  }) {
    return MevoraCompatibilityEngine.fromCandidate(
      viewer: viewer,
      candidate: candidate,
      preferences: DiscoveryPreferences(
        minAge: filters.minAge,
        maxAge: filters.maxAge,
        maxDistanceKm: filters.maxDistanceKm,
      ),
    );
  }

  static List<String> _sharedInterests(
    UserProfile viewer,
    DiscoveryCandidate candidate,
  ) {
    final viewerSet = viewer.interests.map((i) => i.trim().toLowerCase()).toSet();
    return candidate.interests
        .where((interest) => viewerSet.contains(interest.trim().toLowerCase()))
        .toList();
  }

  static void _debug(String message) {
    if (kDebugMode) {
      debugPrint('[COMPAT_DEBUG] $message');
    }
  }

  static bool _hasMeaningfulSignals({
    required UserProfile viewer,
    required DiscoveryCandidate candidate,
  }) {
    final viewerHasProfile = viewer.interests.isNotEmpty ||
        (viewer.relationshipGoal?.isNotEmpty ?? false) ||
        viewer.lifestyle.isNotEmpty;
    final candidateHasProfile = candidate.interests.isNotEmpty ||
        (candidate.relationshipGoal?.isNotEmpty ?? false) ||
        candidate.categoryInterestScore != null ||
        candidate.categoryRelationshipScore != null;
    return viewerHasProfile && candidateHasProfile;
  }
}
