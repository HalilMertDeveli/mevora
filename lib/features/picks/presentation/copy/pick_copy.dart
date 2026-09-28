import 'package:flutter/material.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_compatibility_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Turns server-computed Pick reasons into localised copy.
///
/// Every sentence here is built from a structured reason the server sent. A
/// percentage appears only when the reason carries a measured score; a count
/// only when the server counted it. Nothing is inferred on the device.
abstract final class PickCopy {
  static String typeLabel(AppLocalizations l10n, PickType type) {
    return switch (type) {
      PickType.bestOverall => l10n.pickTypeBestOverall,
      PickType.valuesMatch => l10n.pickTypeValuesMatch,
      PickType.humorMatch => l10n.pickTypeHumorMatch,
      PickType.musicMatch => l10n.pickTypeMusicMatch,
      PickType.nearbyMatch => l10n.pickTypeNearbyMatch,
      PickType.unexpectedMatch => l10n.pickTypeUnexpectedMatch,
    };
  }

  static IconData typeIcon(PickType type) {
    return switch (type) {
      PickType.bestOverall => Icons.auto_awesome_rounded,
      PickType.valuesMatch => Icons.favorite_border_rounded,
      PickType.humorMatch => Icons.sentiment_very_satisfied_rounded,
      PickType.musicMatch => Icons.headphones_rounded,
      PickType.nearbyMatch => Icons.near_me_rounded,
      PickType.unexpectedMatch => Icons.explore_rounded,
    };
  }

  /// The one line a card leads with: why Mevora chose this person.
  static String headline(AppLocalizations l10n, MevoraPick pick) {
    switch (pick.pickType) {
      case PickType.bestOverall:
        final overall = pick.reasonOf(PickReasonType.overall);
        return overall != null && overall.isStrong
            ? l10n.pickHeadlineBestOverallStrong
            : l10n.pickHeadlineBestOverall;
      case PickType.valuesMatch:
        return l10n.pickHeadlineValues;
      case PickType.humorMatch:
        final score =
            pick.reasonOf(PickReasonType.humor)?.score ?? pick.humorScore;
        return score != null
            ? l10n.pickHeadlineHumorScore(score)
            : l10n.pickTypeHumorMatch;
      case PickType.musicMatch:
        final artists =
            pick.reasonOf(PickReasonType.music)?.intMeta('artists') ?? 0;
        return artists > 0
            ? l10n.pickHeadlineMusicArtists(artists)
            : l10n.pickHeadlineMusic;
      case PickType.nearbyMatch:
        return l10n.pickHeadlineNearby;
      case PickType.unexpectedMatch:
        return l10n.pickHeadlineUnexpected;
    }
  }

  /// A second, supporting line for the card — the strongest reason that is
  /// not already the headline. Null when there is nothing more to say.
  static String? supportingLine(AppLocalizations l10n, MevoraPick pick) {
    if (pick.pickType == PickType.unexpectedMatch) {
      return l10n.pickDetailUnexpected;
    }
    final headlineType = switch (pick.pickType) {
      PickType.humorMatch => PickReasonType.humor,
      PickType.musicMatch => PickReasonType.music,
      PickType.nearbyMatch => PickReasonType.distance,
      PickType.bestOverall => PickReasonType.overall,
      PickType.valuesMatch => null,
      PickType.unexpectedMatch => null,
    };
    for (final reason in pick.reasons) {
      if (reason.type == headlineType ||
          reason.type == PickReasonType.overall) {
        continue;
      }
      final sentence = reasonSentence(l10n, reason);
      if (sentence != null) {
        return sentence;
      }
    }
    return null;
  }

  /// One reason as a full sentence, or null when the reason lacks the data
  /// its sentence would need.
  static String? reasonSentence(AppLocalizations l10n, PickReason reason) {
    switch (reason.type) {
      case PickReasonType.overall:
        final score = reason.score;
        return score == null ? null : l10n.pickReasonOverall(score);
      case PickReasonType.relationship:
        return l10n.pickReasonRelationship;
      case PickReasonType.relationshipViews:
        final topics = relationshipTopicsFromNames(reason.listMeta('topics'));
        final aligned = reason.intMeta('aligned');
        final shared = reason.intMeta('shared');
        if (aligned != null && shared != null && shared > 0) {
          return l10n.pickReasonViews(aligned, shared);
        }
        return topics.isEmpty ? null : relationshipTopicSummary(l10n, topics);
      case PickReasonType.communication:
        return l10n.pickReasonCommunication;
      case PickReasonType.lifestyle:
        return l10n.pickReasonLifestyle;
      case PickReasonType.humor:
        final score = reason.score;
        return score == null ? null : l10n.pickHeadlineHumorScore(score);
      case PickReasonType.music:
        final artists = reason.intMeta('artists') ?? 0;
        if (artists > 0) {
          return l10n.pickReasonMusicArtists(artists);
        }
        final score = reason.score;
        return score == null ? null : l10n.pickReasonMusicScore(score);
      case PickReasonType.distance:
        final km = reason.intMeta('km');
        return km == null
            ? null
            : l10n.pickReasonDistance(L10nFormat.distance(l10n, km.toDouble()));
      case PickReasonType.interests:
        final count = reason.intMeta('count') ?? 0;
        return count > 0 ? l10n.pickReasonInterests(count) : null;
    }
  }

  /// Extra detail for the humor reason: which humor styles both lean towards.
  static String? humorTraits(AppLocalizations l10n, MevoraPick pick) {
    if (pick.sharedHumorTraits.isEmpty) {
      return null;
    }
    final labels = pick.sharedHumorTraits
        .map((trait) => HumorProfileDisplay.categoryLabel(l10n, trait))
        .join(', ');
    return l10n.pickReasonHumorTraits(labels);
  }

  /// Every reason, as sentences, for the profile's "Why {name}?" section.
  static List<({IconData icon, String text})> whyLines(
    AppLocalizations l10n,
    MevoraPick pick,
  ) {
    final lines = <({IconData icon, String text})>[];
    if (pick.pickType == PickType.unexpectedMatch) {
      lines.add((icon: Icons.explore_rounded, text: l10n.pickDetailUnexpected));
    }
    for (final reason in pick.reasons) {
      final sentence = reasonSentence(l10n, reason);
      if (sentence == null) {
        continue;
      }
      lines.add((icon: _reasonIcon(reason.type), text: sentence));
      if (reason.type == PickReasonType.humor) {
        final traits = humorTraits(l10n, pick);
        if (traits != null) {
          lines.add((icon: Icons.theater_comedy_outlined, text: traits));
        }
      }
    }
    return lines;
  }

  static IconData _reasonIcon(PickReasonType type) {
    return switch (type) {
      PickReasonType.overall => Icons.auto_awesome_rounded,
      PickReasonType.relationship => Icons.favorite_border_rounded,
      PickReasonType.relationshipViews => Icons.forum_outlined,
      PickReasonType.communication => Icons.chat_bubble_outline_rounded,
      PickReasonType.lifestyle => Icons.spa_outlined,
      PickReasonType.humor => Icons.sentiment_very_satisfied_rounded,
      PickReasonType.music => Icons.headphones_rounded,
      PickReasonType.distance => Icons.near_me_outlined,
      PickReasonType.interests => Icons.interests_outlined,
    };
  }
}
