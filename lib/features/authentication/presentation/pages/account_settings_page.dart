import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/link_email_dialog.dart';
import 'package:mevora/features/settings/data/services/data_export_service.dart';
import 'package:mevora/features/settings/presentation/widgets/language_settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

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
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          const LanguageSettingsSection(),
          const SizedBox(height: AppSpacing.xl),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.privacyPermissionsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.privacyPermissions),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            l10n.linkedAccounts,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          _linkTile(
            context,
            label: l10n.email,
            linked: providers?.email ?? false,
            linkedLabel: l10n.linked,
            linkLabel: l10n.link,
            onLink: () => unawaited(showLinkEmailDialog(context)),
          ),
          _linkTile(
            context,
            label: l10n.continueWithGoogle,
            linked: providers?.google ?? false,
            linkedLabel: l10n.linked,
            linkLabel: l10n.link,
            onLink: () => unawaited(
              auth.linkProvider(AuthProviderId.google),
            ),
          ),
          _linkTile(
            context,
            label: l10n.continueWithApple,
            linked: providers?.apple ?? false,
            linkedLabel: l10n.linked,
            linkLabel: l10n.link,
            onLink: () => unawaited(
              auth.linkProvider(AuthProviderId.apple),
            ),
          ),
          _linkTile(
            context,
            label: l10n.continueWithSpotify,
            linked: providers?.spotify ?? false,
            linkedLabel: l10n.linked,
            linkLabel: l10n.link,
            onLink: () => unawaited(
              auth.linkProvider(AuthProviderId.spotify),
            ),
          ),
          _linkTile(
            context,
            label: l10n.continueWithPhone,
            linked: providers?.phone ?? false,
            linkedLabel: l10n.linked,
            linkLabel: l10n.link,
            onLink: null,
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            AuthErrorBanner(message: error),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (_exportInFlight)
            MevoraLoading(message: l10n.exportMyData)
          else
            MevoraButton(
              label: l10n.exportMyData,
              variant: MevoraButtonVariant.secondary,
              onPressed: actionsLocked
                  ? null
                  : () => unawaited(_confirmExport(context)),
            ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            label: l10n.logOut,
            variant: MevoraButtonVariant.secondary,
            onPressed: actionsLocked ? null : () => unawaited(auth.signOut()),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_deleteInFlight)
            MevoraLoading(message: l10n.deleteAccount)
          else
            MevoraButton(
              label: l10n.deleteAccount,
              variant: MevoraButtonVariant.destructive,
              onPressed: actionsLocked
                  ? null
                  : () => unawaited(_confirmDelete(context)),
            ),
        ],
      ),
    );
  }

  Widget _linkTile(
    BuildContext context, {
    required String label,
    required bool linked,
    required String linkedLabel,
    required String linkLabel,
    required VoidCallback? onLink,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: linked
          ? Text(linkedLabel)
          : MevoraButton(
              label: linkLabel,
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
      final path =
          await DataExportService(FirebaseFunctionsCallable()).exportToFile();
      await Clipboard.setData(ClipboardData(text: path));
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.exportMyDataSuccess(path))),
      );
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.exportMyDataFailed)),
      );
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
