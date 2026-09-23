import 'package:flutter/material.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/emulator_qa_login.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';

/// Sign-in shortcuts for seeded Firebase Emulator accounts.
///
/// Renders nothing unless [EmulatorQaLogin.isEnabled], and each shortcut
/// re-checks the gate before acting — the button being on screen is never the
/// thing that authorises it.
///
/// Tapping a shortcut only fills the existing email/password form and submits
/// it through the normal sign-in path. No auth state is injected.
class EmulatorQaLoginPanel extends StatelessWidget {
  const EmulatorQaLoginPanel({
    super.key,
    required this.onUseAccount,
    this.enabled = true,
  });

  /// Called with the seeded credentials so the host page can fill its own
  /// controllers and run its normal submit.
  final void Function(String email, String password) onUseAccount;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).config;
    if (!EmulatorQaLogin.isEnabled(config)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.science_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Emulator QA sign-in', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Development builds against the Auth emulator only.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final account in EmulatorQaLogin.accounts)
                OutlinedButton(
                  key: Key('qa_login_${account.email}'),
                  onPressed: enabled
                      ? () {
                          // Re-check rather than trusting that this widget was
                          // only built because the gate was open.
                          final resolved = EmulatorQaLogin.resolve(
                            config,
                            account.email,
                          );
                          if (resolved == null) {
                            return;
                          }
                          onUseAccount(resolved.email, resolved.password);
                        }
                      : null,
                  child: Text(account.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
