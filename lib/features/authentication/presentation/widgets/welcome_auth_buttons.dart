import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// Premium provider CTAs for the login welcome hero (on photo).
class WelcomeAuthButtons extends StatelessWidget {
  const WelcomeAuthButtons({
    super.key,
    required this.onGoogle,
    required this.onApple,
    required this.onPhone,
    required this.onSpotify,
    required this.onEmail,
    this.enabled = true,
    this.busyProvider,
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onPhone;
  final VoidCallback onSpotify;
  final VoidCallback onEmail;
  final bool enabled;
  final String? busyProvider;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WelcomeProviderButton(
          label: l10n.continueWithGoogle,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'google',
          onPressed: enabled && busyProvider != 'google' ? onGoogle : null,
          leading: const _GoogleMark(),
          style: _WelcomeButtonStyle.filledLight,
        ),
        const SizedBox(height: AppSpacing.sm),
        _WelcomeProviderButton(
          label: l10n.continueWithApple,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'apple',
          onPressed: enabled && busyProvider != 'apple' ? onApple : null,
          leading: const Icon(Icons.apple, size: 22, color: Colors.white),
          style: _WelcomeButtonStyle.filledDark,
        ),
        const SizedBox(height: AppSpacing.sm),
        _WelcomeProviderButton(
          label: l10n.continueWithPhone,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'phone',
          onPressed: enabled && busyProvider != 'phone' ? onPhone : null,
          leading: const Icon(
            Icons.phone_iphone_rounded,
            size: 20,
            color: Color(0xFFF4EEE8),
          ),
          style: _WelcomeButtonStyle.glass,
        ),
        const SizedBox(height: AppSpacing.sm),
        _WelcomeProviderButton(
          label: l10n.continueWithSpotify,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'spotify',
          onPressed: enabled && busyProvider != 'spotify' ? onSpotify : null,
          leading: const _SpotifyMark(),
          style: _WelcomeButtonStyle.spotify,
        ),
        const SizedBox(height: AppSpacing.sm),
        _WelcomeProviderButton(
          label: l10n.continueWithEmail,
          loadingLabel: l10n.signingIn,
          isLoading: busyProvider == 'email',
          onPressed: enabled && busyProvider != 'email' ? onEmail : null,
          leading: const Icon(
            Icons.mail_outline_rounded,
            size: 20,
            color: Color(0xFFF4EEE8),
          ),
          style: _WelcomeButtonStyle.glass,
        ),
      ],
    );
  }
}

enum _WelcomeButtonStyle { filledLight, filledDark, glass, spotify }

class _WelcomeProviderButton extends StatelessWidget {
  const _WelcomeProviderButton({
    required this.label,
    required this.loadingLabel,
    required this.onPressed,
    required this.leading,
    required this.style,
    this.isLoading = false,
  });

  final String label;
  final String loadingLabel;
  final VoidCallback? onPressed;
  final Widget leading;
  final _WelcomeButtonStyle style;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    final colors = _colorsFor(style);
    return Semantics(
      button: true,
      enabled: enabled,
      label: isLoading ? loadingLabel : label,
      child: ExcludeSemantics(
        child: MevoraPressScale(
          enabled: enabled,
          child: SizedBox(
          width: double.infinity,
          height: 52,
          child: Material(
            color: colors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(color: colors.border),
            ),
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: isLoading
                    ? Center(
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.foreground,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          SizedBox(width: 28, child: Center(child: leading)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: colors.foreground),
                            ),
                          ),
                          const SizedBox(width: 28),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  static ({Color background, Color foreground, Color border}) _colorsFor(
    _WelcomeButtonStyle style,
  ) {
    return switch (style) {
      _WelcomeButtonStyle.filledLight => (
        background: const Color(0xFFF7F3F0),
        foreground: const Color(0xFF1C1420),
        border: const Color(0x00FFFFFF),
      ),
      _WelcomeButtonStyle.filledDark => (
        background: const Color(0xFF1C1420),
        foreground: const Color(0xFFF4EEE8),
        border: const Color(0x33FFFFFF),
      ),
      _WelcomeButtonStyle.spotify => (
        background: const Color(0xFF1DB954),
        foreground: const Color(0xFF04140A),
        border: const Color(0x00FFFFFF),
      ),
      _WelcomeButtonStyle.glass => (
        background: const Color(0x33FFFFFF),
        foreground: const Color(0xFFF4EEE8),
        border: const Color(0x55FFFFFF),
      ),
    };
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'G',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: const Color(0xFF4285F4),
        height: 1,
      ),
    );
  }
}

class _SpotifyMark extends StatelessWidget {
  const _SpotifyMark();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.graphic_eq_rounded,
      size: 20,
      color: Color(0xFF04140A),
    );
  }
}
