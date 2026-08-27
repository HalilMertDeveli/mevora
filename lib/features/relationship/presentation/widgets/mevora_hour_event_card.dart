import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/relationship/domain/entities/mevora_hour_phase.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

/// Soft / full Mevora Hour EVENT chrome (not a generic personality-test sheet).
class MevoraHourEventCard extends StatelessWidget {
  const MevoraHourEventCard({
    super.key,
    required this.phase,
    required this.onPrimary,
    required this.onRemind,
    this.onDismiss,
    this.hourLabel,
    this.nextHourLabel,
    this.countdown,
    this.reminderEnabled = false,
    this.compact = false,
  });

  final MevoraHourPhase phase;
  final VoidCallback onPrimary;
  final VoidCallback onRemind;
  final VoidCallback? onDismiss;
  final String? hourLabel;
  final String? nextHourLabel;
  final Duration? countdown;
  final bool reminderEnabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hour = hourLabel ?? '--';
    final next = nextHourLabel ?? '--';
    final remain = _formatCountdown(countdown);

    final String eyebrow;
    final String title;
    final String body;
    final String? primaryLabel;
    final String? secondaryLabel;

    switch (phase) {
      case MevoraHourPhase.upcoming:
        eyebrow = l10n.mevoraHourTitle;
        title = l10n.mevoraHourUpcomingTitle(hour);
        body = remain == null
            ? l10n.mevoraHourUpcomingBody
            : l10n.mevoraHourUpcomingCountdown(remain);
        primaryLabel = null;
        secondaryLabel = reminderEnabled
            ? l10n.mevoraHourReminderOn
            : l10n.mevoraHourRemindMe;
      case MevoraHourPhase.live:
        eyebrow = l10n.mevoraHourLiveBadge;
        title = l10n.mevoraHourLiveTitle(hour);
        body = remain == null
            ? l10n.mevoraHourMessage
            : '${l10n.mevoraHourMessage}\n${l10n.mevoraHourCountdown(remain)}';
        primaryLabel = l10n.mevoraHourJoinNow;
        secondaryLabel = reminderEnabled
            ? l10n.mevoraHourReminderOn
            : l10n.mevoraHourRemindMe;
      case MevoraHourPhase.joined:
        eyebrow = l10n.mevoraHourTitle;
        title = l10n.mevoraHourJoinedTitle;
        body = l10n.mevoraHourJoinedBody;
        primaryLabel = null;
        secondaryLabel = null;
      case MevoraHourPhase.answered:
        eyebrow = l10n.mevoraHourTitle;
        title = l10n.mevoraHourAnsweredTitle;
        body = l10n.mevoraHourAnsweredBody;
        primaryLabel = l10n.matchingGameWaitingDismiss;
        secondaryLabel = null;
      case MevoraHourPhase.result:
        eyebrow = l10n.mevoraHourTitle;
        title = l10n.mevoraHourResultTitle;
        body = l10n.mevoraHourResultBody;
        primaryLabel = null;
        secondaryLabel = null;
      case MevoraHourPhase.ended:
        eyebrow = l10n.mevoraHourTitle;
        title = l10n.mevoraHourEndedTitle(hour);
        body = l10n.mevoraHourEndedBody(next);
        primaryLabel = null;
        secondaryLabel = reminderEnabled
            ? l10n.mevoraHourReminderOn
            : l10n.mevoraHourRemindMe;
      case MevoraHourPhase.none:
        return const SizedBox.shrink();
    }

    final card = MevoraCard(
      emphasis: MevoraCardEmphasis.elevated,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            eyebrow,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: phase == MevoraHourPhase.live
                  ? theme.colorScheme.error
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: theme.textTheme.bodyLarge),
          if (primaryLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            MevoraButton(label: primaryLabel, onPressed: onPrimary),
          ],
          if (secondaryLabel != null) ...[
            SizedBox(height: primaryLabel == null ? AppSpacing.lg : AppSpacing.sm),
            MevoraButton(
              label: secondaryLabel,
              variant: MevoraButtonVariant.secondary,
              onPressed: reminderEnabled ? null : onRemind,
            ),
          ],
          if (onDismiss != null && phase == MevoraHourPhase.live) ...[
            const SizedBox(height: AppSpacing.sm),
            MevoraButton(
              label: l10n.relationshipTestLater,
              variant: MevoraButtonVariant.ghost,
              onPressed: onDismiss,
            ),
          ],
        ],
      ),
    );

    if (compact) {
      return card;
    }

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: card,
          ),
        ),
      ),
    );
  }

  static String? _formatCountdown(Duration? remain) {
    if (remain == null) {
      return null;
    }
    final h = remain.inHours;
    final m = remain.inMinutes.remainder(60);
    final s = remain.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
