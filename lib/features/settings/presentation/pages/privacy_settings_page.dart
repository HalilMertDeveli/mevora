import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/l10n/app_localizations.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  UserPrivacy? _privacy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final uid = AuthScope.of(context).user?.id;
    final settings = SettingsScope.maybeOf(context);
    if (uid == null || settings == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return StreamBuilder<UserPrivacy>(
      stream: settings.settingsHub.watchPrivacy(uid),
      builder: (context, snapshot) {
        final privacy = snapshot.data ?? _privacy;
        if (privacy != null) {
          _privacy = privacy;
        }
        return Scaffold(
          appBar: AppBar(title: Text(l10n.settingsPrivacyControls)),
          body: privacy == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    SwitchListTile(
                      title: Text(l10n.settingsShowOnlineStatus),
                      value: privacy.showOnlineStatus,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showOnlineStatus: value),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsShowLastSeen),
                      value: privacy.showLastSeen,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showLastSeen: value),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsShowTypingStatus),
                      value: privacy.showTypingStatus,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showTypingStatus: value),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsShowDistance),
                      value: privacy.showDistance,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showDistance: value),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsShowAge),
                      value: privacy.showAge,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showAge: value),
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsShowActivity),
                      value: privacy.showActivity,
                      onChanged: (value) => unawaited(
                        _save(
                          settings,
                          privacy.copyWith(showActivity: value),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _save(SettingsServices settings, UserPrivacy privacy) async {
    await settings.settingsHub.savePrivacy(privacy);
  }
}
