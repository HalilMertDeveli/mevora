import 'package:flutter/material.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

/// Something failed. Says so plainly and offers the one useful next step.
class MevoraErrorView extends StatelessWidget {
  const MevoraErrorView({
    super.key,
    this.art = MevoraArt.error,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  });

  final MevoraArt art;
  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    return MevoraEmptyState(
      art: art,
      compact: compact,
      title: title ?? l10n?.somethingWentWrong ?? 'Something went wrong',
      message:
          message ??
          l10n?.unexpectedError ??
          'The app hit an unexpected error.',
      actionLabel: onRetry == null
          ? null
          : (retryLabel ?? l10n?.retry ?? 'Retry'),
      onAction: onRetry,
    );
  }
}
