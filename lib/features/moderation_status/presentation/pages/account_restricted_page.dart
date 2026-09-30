import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/moderation_status/presentation/moderation_labels.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Where a suspended member is held (the router sends every other route
/// here). They stay signed in and can see why, appeal, reach support, read
/// the rules, or export / delete their data. When staff restore the account
/// the router releases them on its own.
class AccountRestrictedPage extends StatefulWidget {
  const AccountRestrictedPage({super.key});

  @override
  State<AccountRestrictedPage> createState() => _AccountRestrictedPageState();
}

class _AccountRestrictedPageState extends State<AccountRestrictedPage> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }
    setState(() => _signingOut = true);
    final result = await AuthScope.of(context).signOut();
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      context.go(AppRoutes.login);
      return;
    }
    setState(() => _signingOut = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final until = AuthScope.of(context).user?.suspendedUntil;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.accountRestrictedTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Icon(
                MevoraIcons.safety,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.accountRestrictedHeadline,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.accountRestrictedBody),
              const SizedBox(height: AppSpacing.sm),
              Text(
                until != null
                    ? l10n.accountRestrictedUntil(
                        ModerationLabels.dateTime(context, until),
                      )
                    : l10n.accountRestrictedOpenEnded,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.accountRestrictedReleaseNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              MevoraButton(
                key: const ValueKey('restricted-why'),
                label: l10n.accountRestrictedWhy,
                onPressed: () => context.push(AppRoutes.moderationStatus),
              ),
              const SizedBox(height: AppSpacing.s12),
              MevoraButton(
                label: l10n.accountRestrictedContactSupport,
                variant: MevoraButtonVariant.secondary,
                icon: MevoraIcons.support,
                onPressed: () => context.push(AppRoutes.supportCenter),
              ),
              const SizedBox(height: AppSpacing.s12),
              MevoraButton(
                label: l10n.communityGuidelines,
                variant: MevoraButtonVariant.ghost,
                onPressed: () => context.push(AppRoutes.legalGuidelines),
              ),
              MevoraButton(
                label: l10n.accountRestrictedManageData,
                variant: MevoraButtonVariant.ghost,
                onPressed: () => context.push(AppRoutes.accountSettings),
              ),
              MevoraButton(
                label: l10n.logOut,
                variant: MevoraButtonVariant.ghost,
                icon: MevoraIcons.signOut,
                isLoading: _signingOut,
                onPressed: _signingOut ? null : () => unawaited(_signOut()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
