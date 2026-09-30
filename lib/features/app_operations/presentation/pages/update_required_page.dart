import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app; true when something handled it.
typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> launchExternalUrl(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The store name for [platform], for "update from …" copy.
String storeNameFor(AppLocalizations l10n, AppPlatform platform) {
  return switch (platform) {
    AppPlatform.android => 'Google Play',
    AppPlatform.ios => 'App Store',
    AppPlatform.other => l10n.appOpsGenericStore,
  };
}

/// Opens the published store link, or says where to update when there is
/// none or it cannot be opened.
Future<void> openAppUpdate(
  BuildContext context, {
  required String? url,
  required AppPlatform platform,
  ExternalUrlLauncher launcher = launchExternalUrl,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final fallback = l10n.appOpsUpdateFromStore(storeNameFor(l10n, platform));
  final uri = url == null ? null : Uri.tryParse(url);
  var opened = false;
  if (uri != null) {
    try {
      opened = await launcher(uri);
    } on Object {
      opened = false;
    }
  }
  if (!opened) {
    messenger?.showSnackBar(SnackBar(content: Text(fallback)));
  }
}

/// Shown when this build is older than the published minimum. Everything
/// but the legal pages leads here until the app is updated.
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({super.key, this.launcher = launchExternalUrl});

  final ExternalUrlLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final operations = AppOperationsScope.maybeOf(context);
    final platform = operations?.platform ?? AppPlatform.other;
    final url = operations?.updateUrl;
    final message = url == null
        ? '${l10n.appOpsUpdateRequiredMessage}\n\n'
              '${l10n.appOpsUpdateFromStore(storeNameFor(l10n, platform))}'
        : l10n.appOpsUpdateRequiredMessage;
    return Scaffold(
      body: SafeArea(
        child: MevoraEmptyState(
          key: const Key('updateRequiredPage'),
          art: MevoraArt.generic,
          title: l10n.appOpsUpdateRequiredTitle,
          message: message,
          actionLabel: url == null ? null : l10n.appOpsUpdateAction,
          onAction: url == null
              ? null
              : () => unawaited(
                  openAppUpdate(
                    context,
                    url: url,
                    platform: platform,
                    launcher: launcher,
                  ),
                ),
        ),
      ),
    );
  }
}
