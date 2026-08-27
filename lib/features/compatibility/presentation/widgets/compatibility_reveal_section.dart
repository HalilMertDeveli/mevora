import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/compatibility_reveal_scope.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reveal.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reveal_builder.dart';
import 'package:mevora/features/compatibility/presentation/widgets/animated_compatibility_score.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

enum CompatibilityRevealUiState { idle, loading, success, empty, error }

/// Post-match Compatibility Reveal: score → CTA → verified common points.
class CompatibilityRevealSection extends StatefulWidget {
  const CompatibilityRevealSection({
    super.key,
    required this.matchId,
    required this.viewer,
    required this.candidate,
    required this.breakdown,
    this.questionTopTopics = const [],
    this.analytics,
    this.isPremium = false,
  });

  final String? matchId;
  final UserProfile viewer;
  final UserProfile candidate;
  final CompatibilityBreakdown breakdown;
  /// Verified relationship topics from the match candidate (never invented).
  final List<String> questionTopTopics;
  final AnalyticsProvider? analytics;
  /// Optional initial hint only. Live entitlement comes from SubscriptionScope
  /// and the server response always wins after reveal.
  final bool isPremium;

  @override
  State<CompatibilityRevealSection> createState() =>
      _CompatibilityRevealSectionState();
}

class _CompatibilityRevealSectionState extends State<CompatibilityRevealSection>
    with SingleTickerProviderStateMixin {
  CompatibilityReveal? _reveal;
  var _uiState = CompatibilityRevealUiState.idle;
  var _entitlementPremium = false;
  var _serverAuthoritative = false;
  StreamSubscription<PremiumStatus>? _premiumSub;
  late final AnimationController _expand;

  bool get _effectivePremium =>
      _serverAuthoritative
          ? (_reveal?.isPremium ?? false)
          : (_entitlementPremium || widget.isPremium);

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _entitlementPremium = widget.isPremium;
    _rebuildLocalSeed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = SubscriptionScope.maybeOf(context);
    if (repo == null || _premiumSub != null) {
      return;
    }
    _premiumSub = repo.watch().listen((status) {
      if (!mounted || _serverAuthoritative) {
        return;
      }
      setState(() {
        _entitlementPremium = status.isPremium;
        if (_uiState == CompatibilityRevealUiState.idle ||
            _uiState == CompatibilityRevealUiState.empty) {
          _rebuildLocalSeed();
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_premiumSub?.cancel());
    _expand.dispose();
    super.dispose();
  }

  void _rebuildLocalSeed() {
    _reveal = CompatibilityRevealBuilder.build(
      viewer: widget.viewer,
      candidate: widget.candidate,
      breakdown: widget.breakdown,
      isPremium: _effectivePremium,
      questionTopTopics: widget.questionTopTopics,
    );
  }

  Future<void> _onReveal() async {
    if (_uiState == CompatibilityRevealUiState.loading ||
        _uiState == CompatibilityRevealUiState.success) {
      return;
    }
    setState(() => _uiState = CompatibilityRevealUiState.loading);
    unawaited(
      widget.analytics?.logEvent(
        AnalyticsEvents.compatibilityRevealOpened,
        parameters: {'premium': _effectivePremium},
      ),
    );

    final matchId = widget.matchId;
    final repo = CompatibilityRevealScope.maybeOf(context);
    if (matchId == null || matchId.isEmpty || repo == null) {
      if (!mounted) {
        return;
      }
      _applyLocalRevealOutcome();
      return;
    }

    final result = await repo.getReveal(matchId);
    if (!mounted) {
      return;
    }

    switch (result) {
      case Success(:final value):
        setState(() {
          _reveal = value;
          _serverAuthoritative = true;
          _entitlementPremium = value.isPremium;
          if (!value.available || value.points.isEmpty) {
            _uiState = CompatibilityRevealUiState.empty;
          } else {
            _uiState = CompatibilityRevealUiState.success;
          }
        });
        unawaited(_expand.forward(from: 0));
      case Err():
        // Do not invent points. Keep local seed but surface a safe error.
        setState(() {
          _uiState = CompatibilityRevealUiState.error;
        });
    }
  }

  void _applyLocalRevealOutcome() {
    _rebuildLocalSeed();
    final reveal = _reveal;
    setState(() {
      if (reveal == null || !reveal.available || reveal.points.isEmpty) {
        _uiState = CompatibilityRevealUiState.empty;
      } else {
        _uiState = CompatibilityRevealUiState.success;
      }
    });
    unawaited(_expand.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reveal = _reveal;
    final score = reveal?.overallScore ?? widget.breakdown.overallScore;

    if (score <= 0 &&
        (reveal == null || !reveal.available) &&
        widget.breakdown.dataQuality == CompatibilityDataQuality.insufficient &&
        _uiState == CompatibilityRevealUiState.idle) {
      return Text(l10n.compatNotEnoughData, style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedCompatibilityScore(
            target: score,
            label: l10n.compatOverallLabel(score),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.compatRevealTitle,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.compatRevealSubtitle,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        if (_uiState == CompatibilityRevealUiState.idle ||
            _uiState == CompatibilityRevealUiState.loading ||
            _uiState == CompatibilityRevealUiState.error) ...[
          if (_uiState == CompatibilityRevealUiState.error) ...[
            Text(
              l10n.compatRevealError,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          MevoraButton(
            label: _uiState == CompatibilityRevealUiState.loading
                ? l10n.compatRevealLoading
                : (_uiState == CompatibilityRevealUiState.error
                      ? l10n.compatRevealRetry
                      : l10n.compatRevealCta),
            onPressed: _uiState == CompatibilityRevealUiState.loading
                ? null
                : () => unawaited(_onReveal()),
          ),
        ] else ...[
          SizeTransition(
            sizeFactor: CurvedAnimation(
              parent: _expand,
              curve: Curves.easeOutCubic,
            ),
            axisAlignment: -1,
            child: _uiState == CompatibilityRevealUiState.empty
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      l10n.compatNotEnoughData,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  )
                : _RevealBody(reveal: reveal),
          ),
          if (reveal?.showPremiumUpsell == true) ...[
            const SizedBox(height: AppSpacing.md),
            MevoraButton(
              label: l10n.compatRevealPremiumCta,
              variant: MevoraButtonVariant.secondary,
              onPressed: () => context.push(AppRoutes.boost),
            ),
          ],
        ],
      ],
    );
  }
}

class _RevealBody extends StatelessWidget {
  const _RevealBody({required this.reveal});

  final CompatibilityReveal? reveal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = reveal?.points ?? const <CompatibilityRevealPoint>[];

    if (reveal == null || !reveal!.available || points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(
          l10n.compatNotEnoughData,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          _RevealPointTile(index: i + 1, point: points[i]),
        ],
        if (reveal!.breakdown != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.compatRevealBreakdownTitle,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          _MiniScore(
            label: l10n.compatCategoryRelationship,
            score: reveal!.breakdown!.relationshipScore,
          ),
          _MiniScore(
            label: l10n.compatCategoryInterests,
            score: reveal!.breakdown!.interestScore,
          ),
          _MiniScore(
            label: l10n.compatCategoryLifestyle,
            score: reveal!.breakdown!.lifestyleScore,
          ),
          if (reveal!.breakdown!.questionScore != null)
            _MiniScore(
              label: l10n.compatCategoryQuestions,
              score: reveal!.breakdown!.questionScore!,
            ),
          if (reveal!.breakdown!.musicScore != null)
            _MiniScore(
              label: l10n.compatCategoryMusic,
              score: reveal!.breakdown!.musicScore!,
            ),
        ],
      ],
    );
  }
}

class _RevealPointTile extends StatelessWidget {
  const _RevealPointTile({required this.index, required this.point});

  final int index;
  final CompatibilityRevealPoint point;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$index️⃣', style: theme.textTheme.titleMedium),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _kindLabel(l10n, point.kind),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    localizeRevealPoint(l10n, point),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(AppLocalizations l10n, CompatibilityRevealKind kind) {
    return switch (kind) {
      CompatibilityRevealKind.personality => l10n.compatRevealKindPersonality,
      CompatibilityRevealKind.questions => l10n.compatRevealKindQuestions,
      CompatibilityRevealKind.music => l10n.compatRevealKindMusic,
      CompatibilityRevealKind.relationship => l10n.compatRevealKindRelationship,
      CompatibilityRevealKind.preference => l10n.compatRevealKindPreference,
      CompatibilityRevealKind.lifestyle => l10n.compatRevealKindLifestyle,
    };
  }
}

@visibleForTesting
String localizeRevealPoint(
  AppLocalizations l10n,
  CompatibilityRevealPoint point,
) {
  switch (point.messageKey) {
    case 'compatRevealPersonalityAligned':
      return l10n.compatRevealPersonalityAligned(
        point.messageArgs.isNotEmpty ? point.messageArgs.first : '0',
      );
    case 'compatRevealSimilarPersonality':
      return l10n.compatRevealSimilarPersonality;
    case 'compatReasonSameAnswers':
      if (point.messageArgs.length < 2) {
        return l10n.compatNotEnoughData;
      }
      return l10n.compatReasonSameAnswers(
        point.messageArgs.elementAt(0),
        point.messageArgs.elementAt(1),
      );
    case 'compatReasonSimilarMusic':
      if (point.messageArgs.isEmpty) {
        return l10n.compatNotEnoughData;
      }
      return l10n.compatReasonSimilarMusic(point.messageArgs.first);
    case 'compatReasonSameRelationshipGoal':
      if (point.messageArgs.isEmpty) {
        return l10n.compatNotEnoughData;
      }
      return l10n.compatReasonSameRelationshipGoal(
        _goal(l10n, point.messageArgs.first),
      );
    case 'compatReasonSharedInterests':
      return l10n.compatReasonSharedInterests(point.messageArgs.join(', '));
    case 'compatReasonCommunication':
      return l10n.compatReasonCommunication;
    default:
      return point.messageKey;
  }
}

String _goal(AppLocalizations l10n, String key) {
  return switch (key) {
    'longTerm' => l10n.relationshipGoalLongTerm,
    'casual' => l10n.relationshipGoalCasual,
    'figuringOut' => l10n.relationshipGoalFiguringOut,
    _ => key,
  };
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.label, required this.score});

  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text('$score%', style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}
