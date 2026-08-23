import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/interest_option.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileInterestPicker extends StatelessWidget {
  const ProfileInterestPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.showHint = true,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHint) ...[
          Text(l10n.onboardingInterestsHint),
          const SizedBox(height: AppSpacing.md),
        ],
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final option in InterestCatalog.options)
              MevoraChip(
                label: OnboardingLabels.interest(l10n, option.id),
                avatar: Icon(option.icon, size: 18),
                selected: selected.contains(option.id),
                onSelected: enabled
                    ? (value) {
                        final next = {...selected};
                        if (value) {
                          if (next.length >= OnboardingConfig.maxInterests) {
                            return;
                          }
                          next.add(option.id);
                        } else {
                          next.remove(option.id);
                        }
                        onChanged(next);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}
