import 'package:flutter/material.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

/// "This feature is taking a short break" — shown in place of a feature the
/// owner has switched off.
class FeatureUnavailableView extends StatelessWidget {
  const FeatureUnavailableView({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraEmptyState(
      key: const Key('featureUnavailable'),
      art: MevoraArt.generic,
      compact: compact,
      title: l10n.appOpsFeatureUnavailableTitle,
      message: l10n.appOpsFeatureUnavailableMessage,
    );
  }
}

/// Renders [child] while [feature] is on, and a calm unavailable screen
/// otherwise — for a route reached directly (deep link, back stack) after
/// its entry points were hidden.
class AppFeatureGate extends StatelessWidget {
  const AppFeatureGate({super.key, required this.feature, required this.child});

  final AppFeature feature;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppOperationsScope.isFeatureEnabled(context, feature)) {
      return child;
    }
    return Scaffold(
      appBar: AppBar(),
      body: const SafeArea(child: FeatureUnavailableView()),
    );
  }
}
