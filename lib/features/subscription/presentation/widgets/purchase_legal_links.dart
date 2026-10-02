import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Terms of Service and Privacy Policy, for every screen that takes money.
///
/// Opens the same in-app legal pages the sign-in footer does. Each link is its
/// own semantics node with a full-height tap target, so a screen reader meets
/// two links rather than one sentence.
class PurchaseLegalLinks extends StatelessWidget {
  const PurchaseLegalLinks({super.key, this.onTerms, this.onPrivacy});

  static const Key termsKey = Key('purchaseLegalTerms');
  static const Key privacyKey = Key('purchaseLegalPrivacy');

  /// Defaults to pushing [AppRoutes.legalTerms].
  final VoidCallback? onTerms;

  /// Defaults to pushing [AppRoutes.legalPrivacy].
  final VoidCallback? onPrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LegalLink(
          key: termsKey,
          label: l10n.termsOfService,
          onTap:
              onTerms ??
              () => unawaited(context.push<void>(AppRoutes.legalTerms)),
        ),
        ExcludeSemantics(
          child: Text('·', style: Theme.of(context).textTheme.bodySmall),
        ),
        _LegalLink(
          key: privacyKey,
          label: l10n.privacyPolicy,
          onTap:
              onPrivacy ??
              () => unawaited(context.push<void>(AppRoutes.legalPrivacy)),
        ),
      ],
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: p.textSecondary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: p.borderStrong,
    );
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Center(
              widthFactor: 1,
              child: Text(label, style: style, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
