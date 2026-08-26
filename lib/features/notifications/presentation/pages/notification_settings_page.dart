import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/permissions/presentation/widgets/notification_permission_gate.dart';
import 'package:mevora/l10n/app_localizations.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final social = SocialScope.maybeOf(context);
    final uid = social?.uidSource.currentUid;
    if (social == null || uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.notificationsTitle)),
        body: const SizedBox.shrink(),
      );
    }
    return StreamBuilder<NotificationPrefs>(
      stream: social.notificationRepository.watchPrefs(uid),
      builder: (context, snapshot) {
        final prefs = snapshot.data ?? const NotificationPrefs();
        return Scaffold(
          appBar: AppBar(
            title: Text(
              l10n.notificationsTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: ListView(
            children: [
              const NotificationPermissionGate(),
              SwitchListTile(
                title: Text(l10n.messageNotifications),
                value: prefs.messageNotifications,
                onChanged: (value) {
                  unawaited(
                    social.notificationRepository.savePrefs(
                      uid,
                      prefs.copyWith(messageNotifications: value),
                    ),
                  );
                },
              ),
              SwitchListTile(
                title: Text(l10n.matchNotifications),
                value: prefs.matchNotifications,
                onChanged: (value) {
                  unawaited(
                    social.notificationRepository.savePrefs(
                      uid,
                      prefs.copyWith(matchNotifications: value),
                    ),
                  );
                },
              ),
              SwitchListTile(
                title: Text(l10n.hideOnlineStatus),
                value: prefs.hideOnlineStatus,
                onChanged: (value) {
                  unawaited(
                    social.notificationRepository.savePrefs(
                      uid,
                      prefs.copyWith(hideOnlineStatus: value),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
