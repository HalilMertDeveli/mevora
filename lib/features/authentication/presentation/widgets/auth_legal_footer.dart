import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';

class AuthLegalFooter extends StatelessWidget {
  const AuthLegalFooter({
    super.key,
    required this.onTerms,
    required this.onPrivacy,
  });

  final VoidCallback onTerms;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          Text('${l10n.legalPrefix} ', style: style),
          GestureDetector(
            onTap: onTerms,
            child: Text(
              l10n.termsOfService,
              style: style?.copyWith(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(' ${l10n.legalConjunction} ', style: style),
          GestureDetector(
            onTap: onPrivacy,
            child: Text(
              l10n.privacyPolicy,
              style: style?.copyWith(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text('.', style: style),
        ],
      ),
    );
  }
}
