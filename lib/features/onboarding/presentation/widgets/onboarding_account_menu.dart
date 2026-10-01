import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';

enum _AccountMenuAction { guidelines, terms, privacy, signOut, deleteAccount }

/// The overflow button in the onboarding header.
///
/// Settings is out of reach until onboarding is finished, so the ways out of
/// the account - signing out, deleting it - and the legal pages live here.
class OnboardingAccountMenu extends StatelessWidget {
  const OnboardingAccountMenu({
    super.key,
    required this.onSignOut,
    required this.onDeleteAccount,
    this.enabled = true,
  });

  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppLocalizations.of(context).more,
      onPressed: enabled ? () => unawaited(_open(context)) : null,
      icon: const Icon(MevoraIcons.moreVertical),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        alignment: Alignment.centerRight,
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final action = await MevoraBottomSheet.showActions<_AccountMenuAction>(
      context,
      actions: [
        // Same order and icons as the legal rows in Settings.
        MevoraSheetAction(
          value: _AccountMenuAction.guidelines,
          label: l10n.communityGuidelines,
          icon: MevoraIcons.people,
        ),
        MevoraSheetAction(
          value: _AccountMenuAction.terms,
          label: l10n.termsOfService,
          icon: MevoraIcons.books,
        ),
        MevoraSheetAction(
          value: _AccountMenuAction.privacy,
          label: l10n.privacyPolicy,
          icon: MevoraIcons.safety,
        ),
        MevoraSheetAction(
          value: _AccountMenuAction.signOut,
          label: l10n.logOut,
          icon: MevoraIcons.signOut,
        ),
        // Account-ending: last and in the error colour, as in Settings.
        MevoraSheetAction(
          value: _AccountMenuAction.deleteAccount,
          label: l10n.deleteAccount,
          icon: MevoraIcons.delete,
          destructive: true,
        ),
      ],
    );
    if (action == null || !context.mounted) {
      return;
    }
    switch (action) {
      case _AccountMenuAction.guidelines:
        unawaited(context.push(AppRoutes.legalGuidelines));
      case _AccountMenuAction.terms:
        unawaited(context.push(AppRoutes.legalTerms));
      case _AccountMenuAction.privacy:
        unawaited(context.push(AppRoutes.legalPrivacy));
      case _AccountMenuAction.signOut:
        onSignOut();
      case _AccountMenuAction.deleteAccount:
        onDeleteAccount();
    }
  }
}
