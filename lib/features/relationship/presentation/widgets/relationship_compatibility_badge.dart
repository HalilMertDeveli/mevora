import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class RelationshipCompatibilityBadge extends StatelessWidget {
  const RelationshipCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
    this.showAccent = false,
  });

  final int score;
  final bool compact;

  /// Optional tiny Rive accent for result moments (never large).
  final bool showAccent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chip = MevoraChip(
      label: compact
          ? l10n.relationshipCompatibilityShort(score)
          : l10n.relationshipCompatibilityPercent(score),
      selected: score >= 40,
      compact: compact,
    );
    if (!showAccent || score < 40) {
      return chip;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MevoraRiveAnimation(
          asset: MevoraRiveAssets.relationshipResult,
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          fallback: Icon(
            Icons.favorite_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        chip,
      ],
    );
  }
}

String relationshipTopicSummary(
  AppLocalizations l10n,
  List<RelationshipTopic> topics,
) {
  if (topics.isEmpty) {
    return l10n.relationshipSimilarThinker;
  }
  return switch (topics.first) {
    RelationshipTopic.jealousy => l10n.relationshipTopicJealousy,
    RelationshipTopic.trust => l10n.relationshipTopicTrust,
    RelationshipTopic.loyalty => l10n.relationshipTopicLoyalty,
    RelationshipTopic.communication => l10n.relationshipTopicCommunication,
    RelationshipTopic.boundaries => l10n.relationshipTopicBoundaries,
    RelationshipTopic.socialLife => l10n.relationshipTopicSocialLife,
    RelationshipTopic.friendship => l10n.relationshipTopicFriendship,
    RelationshipTopic.personalSpace => l10n.relationshipTopicPersonalSpace,
    RelationshipTopic.futurePlans => l10n.relationshipTopicFuturePlans,
    RelationshipTopic.money => l10n.relationshipTopicMoney,
    RelationshipTopic.flirting => l10n.relationshipTopicFlirting,
    RelationshipTopic.exes => l10n.relationshipTopicExes,
    RelationshipTopic.expectations => l10n.relationshipTopicExpectations,
  };
}

List<RelationshipTopic> relationshipTopicsFromNames(List<String> names) {
  final out = <RelationshipTopic>[];
  for (final name in names) {
    for (final topic in RelationshipTopic.values) {
      if (topic.name == name) {
        out.add(topic);
        break;
      }
    }
  }
  return out;
}
