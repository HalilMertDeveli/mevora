import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
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
        _GoogleContinueButton(
          label: l10n.continueWithGoogle,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'google',
          onPressed: enabled && busyProvider != 'google' ? onGoogle : null,
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

/// Light outlined Google continue control — Mevora styling with Google-appropriate
/// contrast (no custom logo asset; "G" mark is typographic).
class _GoogleContinueButton extends StatelessWidget {
  const _GoogleContinueButton({
    required this.label,
    required this.loadingLabel,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final String loadingLabel;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      label: isLoading ? loadingLabel : label,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: isLoading
              ? Semantics(
                  label: loadingLabel,
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'G',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4285F4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
