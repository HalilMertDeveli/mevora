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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onboardingStepProgress(step.displayStep, OnboardingStep.totalSteps),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title, style: theme.textTheme.headlineSmall),
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
