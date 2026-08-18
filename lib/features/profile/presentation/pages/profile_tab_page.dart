import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/l10n/app_localizations.dart';

class ProfileTabPage extends StatelessWidget {
  const ProfileTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListView(
        children: [
          ListTile(
            title: Text(l10n.account),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.settings),
          ),
          ListTile(
            title: Text(l10n.notificationsTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.notificationSettings),
          ),
        ],
      ),
    );
  }
}
