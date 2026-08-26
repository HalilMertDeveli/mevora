import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/features/settings/domain/entities/blocked_user_entry.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class BlockedUsersPage extends StatelessWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final uid = AuthScope.of(context).user?.id;
    final settings = SettingsScope.maybeOf(context);
    if (uid == null || settings == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.blockedUsers)),
      body: StreamBuilder<List<BlockedUserEntry>>(
        stream: settings.settingsHub.watchBlockedUsers(uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return MevoraLoading.page(
              message: l10n.blockedUsers,
              size: 72,
            );
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return MevoraEmptyState(
              icon: Icons.block_outlined,
              riveAsset: MevoraRiveAssets.empty,
              title: l10n.settingsBlockedEmptyTitle,
              message: l10n.settingsBlockedEmptyMessage,
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final photo = MevoraNetworkImages.provider(entry.photoUrl);
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: photo,
                  child: photo == null
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                title: Text(entry.displayName),
                trailing: TextButton(
                  onPressed: () => unawaited(
                    settings.settingsHub.unblockUser(
                      uid: uid,
                      blockedUserId: entry.userId,
                    ),
                  ),
                  child: Text(l10n.settingsUnblock),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
