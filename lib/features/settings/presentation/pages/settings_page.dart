import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/settings/presentation/widgets/language_settings_section.dart';
import 'package:mevora/features/settings/presentation/widgets/settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

/// Main settings hub: account, discovery, privacy, notifications, support.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            SettingsSection(
              title: l10n.account,
              children: [
                SettingsNavTile(
                  title: l10n.editProfile,
                  onTap: () => context.push(AppRoutes.editProfile),
                ),
                SettingsNavTile(
                  title: l10n.settingsChangePassword,
                  onTap: () => context.push(AppRoutes.changePassword),
                ),
                ListTile(
                  title: Text(l10n.email),
                  subtitle: Text(user?.email ?? l10n.settingsEmailUnavailable),
                  trailing: Text(l10n.settingsReadOnly),
                ),
              ],
            ),
            SettingsSection(
              title: l10n.discoveryPreferences,
              children: [
                SettingsNavTile(
                  title: l10n.preferences,
                  onTap: () => context.push(AppRoutes.discoveryPreferences),
                ),
              ],
            ),
            SettingsSection(
              title: l10n.settingsPrivacySafety,
              children: [
                SettingsNavTile(
                  title: l10n.blockedUsers,
                  onTap: () => context.push(AppRoutes.blockedUsers),
                ),
                SettingsNavTile(
                  title: l10n.settingsPrivacyControls,
                  onTap: () => context.push(AppRoutes.privacySettings),
                ),
                SettingsNavTile(
                  title: l10n.settingsLocation,
                  onTap: () => context.push(AppRoutes.locationSettings),
                ),
              ],
            ),
            SettingsSection(
              title: l10n.notificationsTitle,
              children: [
                SettingsNavTile(
                  title: l10n.notificationsTitle,
                  onTap: () => context.push(AppRoutes.notificationSettings),
                ),
              ],
            ),
            SettingsSection(
              title: l10n.settingsSupport,
              children: [
                SettingsNavTile(
                  title: l10n.help,
                  onTap: () => unawaited(_openUrl('https://mevora.app/help')),
                ),
                SettingsNavTile(
                  title: l10n.communityGuidelines,
                  onTap: () =>
                      unawaited(_openUrl('https://mevora.app/guidelines')),
                ),
                SettingsNavTile(
                  title: l10n.termsOfService,
                  onTap: () => unawaited(_openUrl('https://mevora.app/terms')),
                ),
                SettingsNavTile(
                  title: l10n.privacyPolicy,
                  onTap: () =>
                      unawaited(_openUrl('https://mevora.app/privacy')),
                ),
              ],
            ),
            const LanguageSettingsSection(),
            const SizedBox(height: AppSpacing.md),
            SettingsSection(
              title: l10n.account,
              children: [
                SettingsNavTile(
                  title: l10n.logOut,
                  destructive: true,
                  trailing: const SizedBox.shrink(),
                  onTap: auth.isBusy ? null : () => unawaited(_confirmLogout(context)),
                ),
                SettingsNavTile(
                  title: l10n.deleteAccount,
                  destructive: true,
                  trailing: const SizedBox.shrink(),
                  onTap: auth.isBusy
                      ? null
                      : () => unawaited(_confirmDelete(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await MevoraDialog.show(
      context,
      title: l10n.settingsLogoutTitle,
      message: l10n.settingsLogoutBody,
      confirmLabel: l10n.logOut,
    );
    if (confirmed == true && context.mounted) {
      await AuthScope.of(context).signOut();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final first = await MevoraDialog.show(
      context,
      title: l10n.deleteAccountTitle,
      message: l10n.deleteAccountBody,
      confirmLabel: l10n.deleteConfirm,
      confirmVariant: MevoraButtonVariant.destructive,
    );
    if (first != true || !context.mounted) {
      return;
    }
    final second = await MevoraDialog.show(
      context,
      title: l10n.settingsDeleteConfirmTitle,
      message: l10n.settingsDeleteConfirmBody,
      confirmLabel: l10n.deleteConfirm,
      confirmVariant: MevoraButtonVariant.destructive,
      barrierDismissible: false,
    );
    if (second != true || !context.mounted) {
      return;
    }
    await _reauthAndDelete(context);
  }

  Future<void> _reauthAndDelete(BuildContext context) async {
    final auth = AuthScope.of(context);
    final settings = SettingsScope.maybeOf(context);
    final providers = auth.user?.authProviders;
    try {
      if (providers?.email == true && settings != null) {
        final password = await _promptPassword(context);
        if (password == null || password.isEmpty || !context.mounted) {
          return;
        }
        await settings.reauthService.reauthenticateWithPassword(password);
      } else if (providers?.google == true && settings != null) {
        await settings.reauthService.reauthenticateWithGoogle();
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).authOauth),
          ),
        );
      }
      return;
    }
    if (context.mounted) {
      await auth.deleteAccount();
    }
  }

  Future<String?> _promptPassword(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.settingsReauthTitle),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.password),
          ),
          actions: [
            MevoraButton(
              label: l10n.cancel,
              variant: MevoraButtonVariant.ghost,
              isExpanded: false,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            MevoraButton(
              label: l10n.confirm,
              isExpanded: false,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (result == true) {
      return controller.text;
    }
    return null;
  }
}
