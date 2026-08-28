import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/responsive/responsive.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_result.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_category_icons.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_edge_case_handler.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_explanation_engine.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_ui_status.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

/// Structured “Neden Eşleştiniz?” / Why You Matched reasons panel.
///
/// No fixed heights — content sizes to children and scrolls when embedded
/// in a sheet. Uses theme colors (light/dark) and responsive typography.
class WhyYouMatchedReasonsPanel extends StatelessWidget {
  const WhyYouMatchedReasonsPanel({
    super.key,
    required this.status,
    this.result,
    this.reasons,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  /// Builds from [WhyYouMatchedEdgeCaseHandler] output without inventing copy.
  factory WhyYouMatchedReasonsPanel.fromViewModel({
    Key? key,
    required WhyYouMatchedViewModel viewModel,
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    return WhyYouMatchedReasonsPanel(
      key: key,
      status: viewModel.status,
      result: viewModel.result,
      message: viewModel.message.isEmpty ? null : viewModel.message,
      onRetry: viewModel.canRetry ? onRetry : null,
      compact: compact,
    );
  }

  final WhyYouMatchedUiStatus status;

  /// Prefer this when available (overall score + reasons).
  final WhyYouMatchedResult? result;

  /// Fallback reason list when [result] is null.
  final List<WhyYouMatchedReason>? reasons;

  /// Optional status copy (loading / error / empty). When null, ARB defaults.
  final String? message;

  final VoidCallback? onRetry;

  /// Tighter spacing for compact-height devices / inline cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final gap = compact || context.isCompactHeight
        ? AppSpacing.sm
        : AppSpacing.md;
    final statusMessage = message?.trim();
    final hasStatusMessage =
        statusMessage != null && statusMessage.isNotEmpty;

    return switch (status) {
      WhyYouMatchedUiStatus.loading => _LoadingBody(
          message: hasStatusMessage ? statusMessage : l10n.wymLoadingMessage,
          compact: compact,
        ),
      WhyYouMatchedUiStatus.error => MevoraEmptyState(
          icon: Icons.error_outline_rounded,
          title: l10n.somethingWentWrong,
          message:
              hasStatusMessage ? statusMessage : l10n.wymErrorMessage,
          actionLabel: onRetry == null ? null : l10n.retry,
          onAction: onRetry,
        ),
      WhyYouMatchedUiStatus.empty => MevoraEmptyState(
          icon: Icons.favorite_border_rounded,
          title: l10n.wymEmptyTitle,
          message:
              hasStatusMessage ? statusMessage : l10n.wymInsufficientData,
        ),
      WhyYouMatchedUiStatus.ready => _ReadyBody(
          l10n: l10n,
          theme: theme,
          gap: gap,
          compact: compact,
          result: result,
          reasons: reasons,
        ),
    };
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.message, required this.compact});

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      label: message,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: compact ? AppSpacing.md : AppSpacing.lg,
          horizontal: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 28 : 36,
              height: compact ? 28 : 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.l10n,
    required this.theme,
    required this.gap,
    required this.compact,
    required this.result,
    required this.reasons,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final double gap;
  final bool compact;
  final WhyYouMatchedResult? result;
  final List<WhyYouMatchedReason>? reasons;

  @override
  Widget build(BuildContext context) {
    final source = reasons ?? result?.reasons ?? const <WhyYouMatchedReason>[];
    final explanations =
        WhyYouMatchedExplanationEngine.explainAll(l10n, source);
    if (explanations.isEmpty) {
      return MevoraEmptyState(
        icon: Icons.favorite_border_rounded,
        title: l10n.wymEmptyTitle,
        message: l10n.wymInsufficientData,
      );
    }

    final titleStyle = compact || context.isCompactHeight
        ? theme.textTheme.titleMedium
        : theme.textTheme.titleLarge;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.wymReasonListSemantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.favorite_rounded,
                  color: theme.colorScheme.primary,
                  size: compact ? 22 : 26,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  WhyYouMatchedExplanationEngine.sectionTitle(l10n),
                  style: titleStyle?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: gap),
          for (var i = 0; i < explanations.length; i++) ...[
            if (i > 0) SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            _ReasonTile(
              icon: WhyYouMatchedCategoryIcons.forWire(
                explanations[i].categoryWire,
              ),
              title: explanations[i].title,
              body: explanations[i].body,
              compact: compact,
            ),
          ],
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconSize = compact || context.isNarrowWidth ? 22.0 : 26.0;

    return Semantics(
      container: true,
      label: '$title. $body',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: compact ? AppSpacing.sm : AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: iconSize, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      body,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      // Soft wrap — no fixed height; allow multi-line on small screens.
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
