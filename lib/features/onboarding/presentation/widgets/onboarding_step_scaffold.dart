import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

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
    this.riveAsset,
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
  final String? riveAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: step.displayStep / OnboardingStep.totalSteps,
            minHeight: 4,
            backgroundColor: theme.colorScheme.outline.withValues(alpha: 0.35),
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.onboardingStepProgress(
            step.displayStep,
            OnboardingStep.totalSteps,
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        if (step == OnboardingStep.basicInfo) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.onboardingUnderstandingMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Expanded(child: child),
        if (errorMessage != null) ...[
          Text(
            errorMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (onBack != null) ...[
          MevoraButton(
            label: l10n.onboardingBack,
            onPressed: isSaving ? null : onBack,
            variant: MevoraButtonVariant.ghost,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        MevoraButton(
          label: continueLabel ?? l10n.onboardingContinue,
          onPressed: isSaving || !canContinue ? null : onContinue,
          isLoading: isSaving,
        ),
      ],
    );
  }
}
