import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_error_l10n.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// One onboarding step: back + segmented progress on top, one serif
/// question, the answer area, and a single Continue at the bottom.
///
/// One question per screen keeps each step feeling small; the segments show
/// how far there is to go without a wall of numbers.
class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    required this.onContinue,
    this.onBack,
    this.continueLabel,
    this.isSaving = false,
    this.errorMessage,
    this.canContinue = true,
    this.showContinue = true,
    this.subtitle,
  });

  final OnboardingStep step;
  final String title;
  final Widget child;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;
  final String? continueLabel;
  final bool isSaving;
  final String? errorMessage;
  final bool canContinue;

  /// A step that supplies its own primary actions - the optional Spotify
  /// stage offers Connect and Skip - hides the shared Continue button.
  final bool showContinue;

  /// Supporting line under the question.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = context.palette;
    final total = OnboardingStep.totalSteps;
    final current = step.displayStep.clamp(1, total);
    final resolvedSubtitle =
        subtitle ??
        (step == OnboardingStep.basicInfo
            ? l10n.onboardingUnderstandingMessage
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              if (onBack != null)
                IconButton(
                  tooltip: l10n.onboardingBack,
                  onPressed: isSaving ? null : onBack,
                  icon: const Icon(MevoraIcons.back),
                  style: IconButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                )
              else
                const SizedBox(width: AppSpacing.xs),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  label: l10n.onboardingStepProgress(current, total),
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      for (var i = 1; i <= total; i++) ...[
                        if (i > 1) const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AnimatedContainer(
                            duration: AppDurations.normal,
                            curve: AppCurves.standard,
                            height: 4,
                            decoration: BoxDecoration(
                              color: i <= current
                                  ? theme.colorScheme.primary
                                  : p.surfaceMuted,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              MevoraPill(label: '$current/$total', dense: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineLarge),
        ),
        if (resolvedSubtitle != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            resolvedSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(color: p.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Expanded(child: child),
        if (errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          MevoraBanner(
            message: OnboardingErrorL10n.message(l10n, errorMessage!),
            tone: MevoraTone.error,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (showContinue) ...[
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: continueLabel ?? l10n.onboardingContinue,
            size: MevoraButtonSize.large,
            onPressed: isSaving || !canContinue ? null : onContinue,
            isLoading: isSaving,
          ),
        ],
      ],
    );
  }
}
