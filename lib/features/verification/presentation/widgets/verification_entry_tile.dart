import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';

class VerificationEntryTile extends StatelessWidget {
  const VerificationEntryTile({
    super.key,
    required this.status,
    required this.accountVerified,
  });

  final IdentityVerificationStatus status;
  final bool accountVerified;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = verificationEntryTitle(
      l10n,
      status,
      accountVerified: accountVerified,
    );
    final subtitle = verificationEntrySubtitle(
      l10n,
      status,
      accountVerified: accountVerified,
    );
    final icon = verificationEntryIcon(status, accountVerified: accountVerified);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: accountVerified || status == IdentityVerificationStatus.verified
              ? const VerifiedProfileBadge(compact: true)
              : const Icon(Icons.chevron_right),
          onTap: accountVerified
              ? null
              : () => context.push(AppRoutes.verifyProfile),
        ),
      ),
    );
  }
}
