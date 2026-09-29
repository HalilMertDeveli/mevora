import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Relationship-answers compatibility as a sage pill (heart glyph when the
/// overlap is meaningful).
class RelationshipCompatibilityBadge extends StatelessWidget {
  const RelationshipCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
    this.showAccent = false,
  });

  final int score;
  final bool compact;

  /// Lead with the heart glyph for result moments.
  final bool showAccent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final strong = score >= 40;
    return MevoraPill(
      label: compact
          ? l10n.relationshipCompatibilityShort(score)
          : l10n.relationshipCompatibilityPercent(score),
      icon: showAccent && strong ? MevoraIcons.liked : MevoraIcons.questions,
      tone: strong ? MevoraTone.compatibility : MevoraTone.neutral,
      dense: compact,
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
