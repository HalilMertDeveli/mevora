import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// "By continuing you agree to the Terms and Privacy Policy." — the links
/// are real text links, reachable by screen readers.
class AuthLegalFooter extends StatefulWidget {
  const AuthLegalFooter({
    super.key,
    required this.onTerms,
    required this.onPrivacy,
  });

  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  State<AuthLegalFooter> createState() => _AuthLegalFooterState();
}

class _AuthLegalFooterState extends State<AuthLegalFooter> {
  late final _terms = TapGestureRecognizer()..onTap = () => widget.onTerms();
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => widget.onPrivacy();

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    final link = style?.copyWith(
      color: context.palette.textSecondary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: context.palette.borderStrong,
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(text: '${l10n.legalPrefix} '),
            TextSpan(
              text: l10n.termsOfService,
              style: link,
              recognizer: _terms,
            ),
            TextSpan(text: ' ${l10n.legalConjunction} '),
            TextSpan(
              text: l10n.privacyPolicy,
              style: link,
              recognizer: _privacy,
            ),
            const TextSpan(text: '.'),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
