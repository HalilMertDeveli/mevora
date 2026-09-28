import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

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
    final icon = verificationEntryIcon(
      status,
      accountVerified: accountVerified,
    );

    final verified =
        accountVerified || status == IdentityVerificationStatus.verified;
    return MevoraListRow(
      icon: icon,
      iconTone: verified ? MevoraTone.compatibility : MevoraTone.info,
      title: title,
      subtitle: subtitle,
      trailing: verified ? const VerifiedProfileBadge(compact: true) : null,
      showChevron: !accountVerified,
      onTap: accountVerified
          ? null
          : () => context.push(AppRoutes.verifyProfile),
    );
  }
}
