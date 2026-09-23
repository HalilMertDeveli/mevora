import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/presentation/widgets/verified_profile_badge.dart';
import 'package:mevora/features/settings/presentation/widgets/language_settings_section.dart';
import 'package:mevora/features/settings/presentation/widgets/settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

/// Main settings hub: account, discovery, privacy, notifications, support.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _logoutInFlight = false;
  IdentityVerificationStatus _verificationStatus =
      IdentityVerificationStatus.notStarted;
  StreamSubscription<IdentityVerification>? _verificationSub;
  String? _verificationUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = VerificationScope.maybeOf(context);
    if (uid == null || repository == null) {
      return;
    }
    if (uid == _verificationUid && _verificationSub != null) {
      return;
    }
    _verificationUid = uid;
    _verificationSub?.cancel();
    _verificationSub = repository.watchVerification(uid).listen((value) {
      if (!mounted) {
        return;
      }
      setState(() => _verificationStatus = value.status);
    });
  }

  @override
  void dispose() {
    unawaited(_verificationSub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);
    final user = auth.user;
    final logoutLocked = auth.isBusy || _logoutInFlight;
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
                SettingsNavTile(
                  title: l10n.linkedAccounts,
                  onTap: () => context.push(AppRoutes.accountSettings),
                ),
                SettingsNavTile(
                  title: l10n.deleteAccount,
                  destructive: true,
                  onTap: () => context.push(AppRoutes.accountSettings),
                ),
                SettingsNavTile(
                  title: l10n.boostHistoryTitle,
                  onTap: () => context.push(AppRoutes.boost),
                ),
                ListTile(
                  title: Text(l10n.email),
                  subtitle: Text(user?.email ?? l10n.settingsEmailUnavailable),
                  trailing: Text(l10n.settingsReadOnly),
                ),
              ],
            ),
            SettingsSection(
              title: l10n.musicTitle,
              children: [
                SettingsNavTile(
                  title: l10n.settingsConnectSpotify,
                  subtitle: l10n.settingsSpotifySubtitle,
                  onTap: () => context.go(AppRoutes.music),
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
                  title: verificationEntryTitle(
                    l10n,
                    _verificationStatus,
                    accountVerified: user?.isVerified ?? false,
                  ),
                  subtitle: verificationEntrySubtitle(
                    l10n,
                    _verificationStatus,
                    accountVerified: user?.isVerified ?? false,
                  ),
                  trailing: user?.isVerified == true ||
                          _verificationStatus ==
                              IdentityVerificationStatus.verified
                      ? const VerifiedProfileBadge(compact: true)
                      : null,
                  onTap: user?.isVerified == true
                      ? null
                      : () => context.push(AppRoutes.verifyProfile),
                ),
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
                  title: l10n.supportCenterTitle,
                  subtitle: l10n.supportCenterSubtitle,
                  onTap: () => context.push(AppRoutes.supportCenter),
                ),
                SettingsNavTile(
                  title: l10n.communityGuidelines,
                  onTap: () => context.push(AppRoutes.communityGuidelines),
                ),
                SettingsNavTile(
                  title: l10n.termsOfService,
                  onTap: () => context.push(AppRoutes.termsOfService),
                ),
                SettingsNavTile(
                  title: l10n.privacyPolicy,
                  onTap: () => context.push(AppRoutes.privacyPolicy),
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
                  onTap: logoutLocked
                      ? null
                      : () => unawaited(_confirmLogout()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    if (_logoutInFlight || AuthScope.of(context).isBusy) {
      return;
    }
    setState(() => _logoutInFlight = true);
    final l10n = AppLocalizations.of(context);
    final confirmed = await MevoraDialog.show(
      context,
      title: l10n.settingsLogoutTitle,
      message: l10n.settingsLogoutBody,
      confirmLabel: l10n.logOut,
    );
    if (!mounted) {
      return;
    }
    if (confirmed != true) {
      setState(() => _logoutInFlight = false);
      return;
    }
    final auth = AuthScope.of(context);
    final result = await auth.signOut();
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      context.go(AppRoutes.login);
      return;
    }
    setState(() => _logoutInFlight = false);
    final message = result.failureOrNull?.message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          (message != null && message.trim().isNotEmpty)
              ? message
              : l10n.authGeneric,
        ),
      ),
    );
  }
}
