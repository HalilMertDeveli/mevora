import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

class DiscoveryPlaceholderPage extends StatelessWidget {
  const DiscoveryPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            tooltip: l10n.account,
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: MevoraEmptyState(
          icon: Icons.favorite_outline_rounded,
          title: l10n.discoveryTitle,
          message: l10n.discoveryMessage,
          actionLabel: l10n.logOut,
          onAction: auth == null || auth.isBusy
              ? null
              : () => unawaited(auth.signOut()),
        ),
      ),
    );
  }
}
