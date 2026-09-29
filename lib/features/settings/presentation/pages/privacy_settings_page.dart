import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/constants/app_spacings.dart';

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
              ? const MevoraLoading.page()
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  children: [
                    MevoraListGroup(
                      children: [
                        MevoraSwitchRow(
                          title: l10n.settingsShowOnlineStatus,
                          icon: MevoraIcons.dot,
                          value: privacy.showOnlineStatus,
                          onChanged: (value) => unawaited(
                            _save(
                              settings,
                              privacy.copyWith(showOnlineStatus: value),
                            ),
                          ),
                        ),
                        MevoraSwitchRow(
                          title: l10n.settingsShowLastSeen,
                          icon: MevoraIcons.pending,
                          value: privacy.showLastSeen,
                          onChanged: (value) => unawaited(
                            _save(
                              settings,
                              privacy.copyWith(showLastSeen: value),
                            ),
                          ),
                        ),
                        MevoraSwitchRow(
                          title: l10n.settingsShowTypingStatus,
                          icon: MevoraIcons.message,
                          value: privacy.showTypingStatus,
                          onChanged: (value) => unawaited(
                            _save(
                              settings,
                              privacy.copyWith(showTypingStatus: value),
                            ),
                          ),
                        ),
                        MevoraSwitchRow(
                          title: l10n.settingsShowDistance,
                          icon: MevoraIcons.location,
                          value: privacy.showDistance,
                          onChanged: (value) => unawaited(
                            _save(
                              settings,
                              privacy.copyWith(showDistance: value),
                            ),
                          ),
                        ),
                        MevoraSwitchRow(
                          title: l10n.settingsShowAge,
                          icon: MevoraIcons.calendar,
                          value: privacy.showAge,
                          onChanged: (value) => unawaited(
                            _save(settings, privacy.copyWith(showAge: value)),
                          ),
                        ),
                        MevoraSwitchRow(
                          title: l10n.settingsShowActivity,
                          icon: MevoraIcons.waveform,
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
