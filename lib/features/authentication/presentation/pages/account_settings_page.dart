import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/link_email_dialog.dart';
import 'package:mevora/features/settings/data/services/data_export_service.dart';
import 'package:mevora/features/settings/data/services/share_plus_file_share.dart';
import 'package:mevora/features/settings/domain/services/file_share_port.dart';
import 'package:mevora/features/settings/presentation/widgets/language_settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _deleteInFlight = false;
  bool _exportInFlight = false;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    final user = auth.user;
    final providers = user?.authProviders;
    final error = localizeAuthError(l10n, auth);
    final actionsLocked = auth.isBusy || _deleteInFlight || _exportInFlight;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.account)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.sm,
          AppSpacing.screenPadding,
          AppSpacing.xl,
        ),
        children: [
          const LanguageSettingsSection(),
          // The section carries its own bottom spacing.
          MevoraListGroup(
            children: [
              MevoraListRow(
                title: l10n.privacyPermissionsTitle,
                icon: MevoraIcons.privacy,
                onTap: () => context.push(AppRoutes.privacyPermissions),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          MevoraListGroup(
            title: l10n.linkedAccounts,
            children: [
              _linkRow(
                label: l10n.email,
                icon: MevoraIcons.email,
                linked: providers?.email ?? false,
                l10n: l10n,
                onLink: () => unawaited(showLinkEmailDialog(context)),
              ),
              // Brand names stay untranslated.
              _linkRow(
                label: 'Google',
                icon: MevoraIcons.google,
                linked: providers?.google ?? false,
                l10n: l10n,
                onLink: () =>
                    unawaited(auth.linkProvider(AuthProviderId.google)),
              ),
              _linkRow(
                label: 'Apple',
                icon: MevoraIcons.apple,
                linked: providers?.apple ?? false,
                l10n: l10n,
                onLink: () =>
                    unawaited(auth.linkProvider(AuthProviderId.apple)),
              ),
              _linkRow(
                label: 'Spotify',
                icon: MevoraIcons.spotify,
                linked: providers?.spotify ?? false,
                l10n: l10n,
                onLink: () =>
                    unawaited(auth.linkProvider(AuthProviderId.spotify)),
              ),
              _linkRow(
                label: l10n.phoneNumber,
                icon: MevoraIcons.phone,
                linked: providers?.phone ?? false,
                l10n: l10n,
                onLink: null,
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AuthErrorBanner(message: error),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_exportInFlight || _deleteInFlight)
            MevoraLoading(
              message: _exportInFlight ? l10n.exportMyData : l10n.deleteAccount,
            )
          else
            MevoraListGroup(
              children: [
                MevoraListRow(
                  title: l10n.exportMyData,
                  icon: MevoraIcons.export,
                  enabled: !actionsLocked,
                  onTap: () => unawaited(_confirmExport(context)),
                ),
                MevoraListRow(
                  title: l10n.logOut,
                  icon: MevoraIcons.signOut,
                  enabled: !actionsLocked,
                  showChevron: false,
                  onTap: () => unawaited(auth.signOut()),
                ),
                MevoraListRow(
                  title: l10n.deleteAccount,
                  icon: MevoraIcons.delete,
                  destructive: true,
                  enabled: !actionsLocked,
                  showChevron: false,
                  onTap: () => unawaited(_confirmDelete(context)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _linkRow({
    required String label,
    required IconData icon,
    required bool linked,
    required AppLocalizations l10n,
    required VoidCallback? onLink,
  }) {
    return MevoraListRow(
      title: label,
      icon: icon,
      iconTone: linked ? MevoraTone.success : MevoraTone.neutral,
      showChevron: false,
      trailing: linked
          ? MevoraPill(
              label: l10n.linked,
              icon: MevoraIcons.check,
              tone: MevoraTone.success,
              dense: true,
            )
          : onLink == null
          ? null
          : MevoraButton(
              label: l10n.link,
              variant: MevoraButtonVariant.ghost,
              isExpanded: false,
              onPressed: onLink,
            ),
    );
  }

  Future<void> _confirmExport(BuildContext context) async {
    if (_exportInFlight || AuthScope.of(context).isBusy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await MevoraDialog.show(
      context,
      title: l10n.exportMyDataTitle,
      message: l10n.exportMyDataBody,
      confirmLabel: l10n.exportMyData,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    setState(() => _exportInFlight = true);
    try {
      final result = await DataExportService(
        FirebaseFunctionsCallable(),
        share: const SharePlusFileShare(),
      ).exportAndShare(subject: l10n.exportMyDataShareSubject);
      if (!context.mounted) {
        return;
      }
      final message = switch (result.outcome) {
        FileShareOutcome.shared => l10n.exportMyDataShared,
        FileShareOutcome.dismissed => l10n.exportMyDataReady,
        FileShareOutcome.unavailable => l10n.exportMyDataShareUnavailable,
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.exportMyDataFailed)));
    } finally {
      if (mounted) {
        setState(() => _exportInFlight = false);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (_deleteInFlight || AuthScope.of(context).isBusy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final confirmed = await MevoraDialog.show(
      context,
      title: l10n.deleteAccountTitle,
      message: l10n.deleteAccountBody,
      confirmLabel: l10n.deleteConfirm,
      confirmVariant: MevoraButtonVariant.destructive,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    setState(() => _deleteInFlight = true);
    final auth = AuthScope.of(context);
    final result = await auth.deleteAccount();
    if (!context.mounted) {
      return;
    }
    if (result.isSuccess) {
      context.go(AppRoutes.login);
      return;
    }
    setState(() => _deleteInFlight = false);
    final message = result.failureOrNull?.message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (message != null && message.trim().isNotEmpty)
              ? message
              : l10n.somethingWentWrong,
        ),
      ),
    );
  }
}
