import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/authentication/domain/apple_sign_in_support.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';

/// Sign-in providers on the welcome screen.
///
/// Providers are peers, so they share one style — white pill, provider glyph
/// on the left, label centred. The first is filled ink so the eye has a
/// starting point without implying the others are second-class.
///
/// Apple is offered only where Sign in with Apple can run
/// ([isAppleSignInSupported]); elsewhere the button could only fail.
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
    final appleSupported = isAppleSignInSupported;
    final appleFirst =
        appleSupported && Theme.of(context).platform == TargetPlatform.iOS;

    MevoraProviderButton button(
      String id,
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool emphasized = false,
    }) => MevoraProviderButton(
      label: label,
      loadingLabel: l10n.signingIn,
      icon: icon,
      emphasized: emphasized,
      isLoading: busyProvider == id,
      onPressed: enabled && busyProvider != id ? onTap : null,
    );

    final google = button(
      'google',
      l10n.continueWithGoogle,
      MevoraIcons.google,
      onGoogle,
      emphasized: !appleFirst,
    );
    final apple = button(
      'apple',
      l10n.continueWithApple,
      MevoraIcons.apple,
      onApple,
      emphasized: appleFirst,
    );
    final ordered = appleFirst
        ? [apple, google]
        : [google, if (appleSupported) apple];

    final buttons = [
      ...ordered,
      button('phone', l10n.continueWithPhone, MevoraIcons.device, onPhone),
      button(
        'spotify',
        l10n.continueWithSpotify,
        MevoraIcons.spotify,
        onSpotify,
      ),
      button('email', l10n.continueWithEmail, MevoraIcons.email, onEmail),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s12 - 2),
          buttons[i],
        ],
      ],
    );
  }
}

/// A sign-in provider button: glyph left, label centred, full width.
class MevoraProviderButton extends StatelessWidget {
  const MevoraProviderButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.loadingLabel,
    this.isLoading = false,
    this.emphasized = false,
  });

  final String label;
  final String? loadingLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Filled ink instead of white.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final enabled = onPressed != null && !isLoading;
    final bg = emphasized ? p.textPrimary : p.surface;
    final fg = emphasized ? p.background : p.textPrimary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: isLoading ? (loadingLabel ?? label) : label,
      excludeSemantics: true,
      child: MevoraPressScale(
        enabled: enabled,
        child: SizedBox(
          height: 52,
          child: Material(
            color: bg,
            shape: StadiumBorder(
              side: emphasized
                  ? BorderSide.none
                  : BorderSide(color: p.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
                child: isLoading
                    ? Center(
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Icon(icon, size: 20, color: fg),
                          const SizedBox(width: AppSpacing.s12),
                          Expanded(
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: fg,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s12 + 20),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
