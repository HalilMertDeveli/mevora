import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/authentication/domain/apple_sign_in_support.dart';
import 'package:mevora/features/authentication/presentation/widgets/welcome_auth_buttons.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Provider sign-up options on the register page. Shares
/// [MevoraProviderButton] with the welcome screen so the two entry points
/// look like one product. Apple follows the same rule as there: offered only
/// where Sign in with Apple can run.
class SocialAuthButtons extends StatelessWidget {
  const SocialAuthButtons({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.onSpotify,
    this.onPhone,
    this.enabled = true,
    this.busyProvider,
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback? onSpotify;
  final VoidCallback? onPhone;
  final bool enabled;
  final String? busyProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget button(String id, String label, IconData icon, VoidCallback onTap) =>
        MevoraProviderButton(
          label: label,
          loadingLabel: l10n.signingIn,
          icon: icon,
          isLoading: busyProvider == id,
          onPressed: enabled && busyProvider != id ? onTap : null,
        );

    return Column(
      children: [
        button('google', l10n.continueWithGoogle, MevoraIcons.google, onGoogle),
        if (isAppleSignInSupported) ...[
          const SizedBox(height: AppSpacing.sm),
          button('apple', l10n.continueWithApple, MevoraIcons.apple, onApple),
        ],
        if (onSpotify != null) ...[
          const SizedBox(height: AppSpacing.sm),
          button(
            'spotify',
            l10n.continueWithSpotify,
            MevoraIcons.spotify,
            onSpotify!,
          ),
        ],
        if (onPhone != null) ...[
          const SizedBox(height: AppSpacing.sm),
          button('phone', l10n.continueWithPhone, MevoraIcons.phone, onPhone!),
        ],
      ],
    );
  }
}
