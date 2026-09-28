import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_chat_starter_chip.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_badge.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_context_row.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Match-chat humor strip, the sibling of the music banner.
///
/// Renders nothing while loading, on error, with Humor Lab switched off or
/// without a [HumorScope] — the chat must look exactly as before in all of
/// those cases. With a real reading it shows the coarse badge (tap opens the
/// details sheet) and, in an empty chat, a humor-based opening line. While
/// either side is still building a profile it shows one quiet line.
class MatchHumorCompatibilityBanner extends StatefulWidget {
  const MatchHumorCompatibilityBanner({
    super.key,
    required this.matchId,
    this.showChatStarter = false,
    this.onChatStarter,
    this.analytics,
  });

  final String matchId;

  /// True only while the chat is empty and the user can write in it.
  final bool showChatStarter;

  /// Receives the opening line. The chat pre-fills its composer with it;
  /// nothing is sent on the user's behalf.
  final ValueChanged<String>? onChatStarter;

  /// Overrides the analytics found in [BoostScope] (tests).
  final AnalyticsProvider? analytics;

  @override
  State<MatchHumorCompatibilityBanner> createState() =>
      _MatchHumorCompatibilityBannerState();
}

class _MatchHumorCompatibilityBannerState
    extends State<MatchHumorCompatibilityBanner> {
  HumorCompatibility? _data;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    final enabled =
        AppScope.maybeOf(context)?.config.featureFlags.humorLabEnabled == true;
    final repository = HumorScope.maybeOf(context);
    if (!enabled || repository == null) {
      return;
    }
    final analytics =
        widget.analytics ?? BoostScope.maybeOf(context)?.analytics;
    unawaited(_load(repository, analytics));
  }

  Future<void> _load(
    HumorRepository repository,
    AnalyticsProvider? analytics,
  ) async {
    // An error renders nothing: humor is an extra, never a chat failure.
    HumorCompatibility? value;
    try {
      value = (await repository.getMatchCompatibility(
        widget.matchId,
      )).valueOrNull;
    } on Object {
      value = null;
    }
    if (!mounted || value == null) {
      return;
    }
    setState(() => _data = value);
    final level = value.level;
    if (level != null && analytics != null) {
      // Bucket and count only — never the score, never a vector.
      unawaited(
        analytics.logEvent(
          AnalyticsEvents.humorCompatibilityViewed,
          parameters: {
            'surface': 'chat',
            'level': level.name,
            'shared_count': value.strongestShared.length,
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    if (data.hasResult) {
      final onChatStarter = widget.onChatStarter;
      final offerStarter =
          widget.showChatStarter &&
          onChatStarter != null &&
          data.strongestShared.isNotEmpty;
      final l10n = AppLocalizations.of(context);
      final score = data.score!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MevoraContextRow(
            icon: MevoraIcons.humor,
            tone: MevoraTone.humor,
            title: l10n.humorLabTitle,
            trailing: HumorCompatibilityBadge(
              score: score,
              strongestShared: data.strongestShared,
            ),
            onTap: () => unawaited(
              HumorCompatibilitySheet.show(
                context,
                score: score,
                strongestShared: data.strongestShared,
              ),
            ),
          ),
          if (offerStarter)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: HumorChatStarterChip(
                sharedCategories: data.strongestShared,
                analytics: widget.analytics,
                onUsed: onChatStarter,
              ),
            ),
        ],
      );
    }
    if (data.isBuilding) {
      final muted = theme.colorScheme.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Icon(MevoraIcons.humor, size: 16, color: muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                AppLocalizations.of(context).humorCompatibilityBuilding,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      );
    }
    // 'no-signal', 'invalid-match' or anything unknown: stay silent.
    return const SizedBox.shrink();
  }
}
