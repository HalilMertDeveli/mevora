import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Nothing to show yet — and what to do about it.
///
/// The spot illustration names the subject, the serif title says what is
/// happening in human terms, the message says what happens next, and at most
/// one primary action gets the user moving again.
class MevoraEmptyState extends StatelessWidget {
  const MevoraEmptyState({
    super.key,
    this.art = MevoraArt.generic,
    this.animate = false,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  final MevoraArt art;

  /// Animate the illustration — only for states that are actively waiting.
  final bool animate;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// Smaller illustration and spacing, for use inside a section.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolvedTitle = title ?? l10n?.emptyTitle ?? 'Nothing here yet';
    final resolvedMessage =
        message ??
        l10n?.emptyMessage ??
        'When there is something to show, it will appear here.';

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MevoraSpot(art: art, size: compact ? 88 : 128, animate: animate),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(
            resolvedTitle,
            textAlign: TextAlign.center,
            style: compact
                ? theme.textTheme.titleMedium
                : theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          resolvedMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        if (actionLabel != null && onAction != null) ...[
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          MevoraButton(
            label: actionLabel!,
            onPressed: onAction,
            isExpanded: false,
            size: compact ? MevoraButtonSize.small : MevoraButtonSize.medium,
          ),
        ],
        if (secondaryActionLabel != null && onSecondaryAction != null) ...[
          const SizedBox(height: AppSpacing.xs),
          MevoraButton(
            label: secondaryActionLabel!,
            onPressed: onSecondaryAction,
            variant: MevoraButtonVariant.ghost,
            isExpanded: false,
            size: compact ? MevoraButtonSize.small : MevoraButtonSize.medium,
          ),
        ],
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: body),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: body,
        ),
      ),
    );
  }
}
