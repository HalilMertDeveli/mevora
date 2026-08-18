import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

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
    return Column(
      children: [
        _button(
          label: l10n.continueWithGoogle,
          icon: Icons.g_mobiledata_rounded,
          onPressed: onGoogle,
          provider: 'google',
        ),
        const SizedBox(height: AppSpacing.sm),
        _button(
          label: l10n.continueWithApple,
          icon: Icons.apple,
          onPressed: onApple,
          provider: 'apple',
        ),
        if (onSpotify != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _button(
            label: l10n.continueWithSpotify,
            icon: Icons.library_music_outlined,
            onPressed: onSpotify!,
            provider: 'spotify',
          ),
        ],
        if (onPhone != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _button(
            label: l10n.continueWithPhone,
            icon: Icons.phone_outlined,
            onPressed: onPhone!,
            provider: 'phone',
          ),
        ],
      ],
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required String provider,
  }) {
    final loading = busyProvider == provider;
    return MevoraButton(
      label: label,
      variant: MevoraButtonVariant.secondary,
      icon: icon,
      isLoading: loading,
      onPressed: enabled && !loading ? onPressed : null,
    );
  }
}
