import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/app_operations_scope.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:mevora/features/app_operations/presentation/pages/update_required_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Puts the owner's announcement and the soft update prompt above every
/// screen. Sits in `MaterialApp.builder`, so it wraps the router's navigator.
///
/// The navigator always keeps the same place in the tree — a banner coming or
/// going only changes the slot above it — so no route loses its state.
/// Hidden on the maintenance and update-required screens, which already say
/// everything there is to say.
class AppOperationsBannerHost extends StatelessWidget {
  const AppOperationsBannerHost({
    super.key,
    required this.child,
    this.launcher = launchExternalUrl,
  });

  final Widget child;
  final ExternalUrlLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final operations = AppOperationsScope.maybeOf(context);
    if (operations == null) {
      return child;
    }
    final l10n = AppLocalizations.of(context);
    final normal = operations.gate == AppOperationsGate.normal;
    final announcement = normal ? operations.activeAnnouncement : null;
    final showUpdate = normal && operations.showUpdateRecommendation;
    final banners = <Widget>[
      if (announcement != null)
        _OperationsBanner(
          key: const Key('appOpsAnnouncementBanner'),
          dismissKey: const Key('appOpsAnnouncementDismiss'),
          tone: announcement.severity == AnnouncementSeverity.warning
              ? MevoraTone.warning
              : MevoraTone.info,
          icon: announcement.severity == AnnouncementSeverity.warning
              ? MevoraIcons.error
              : MevoraIcons.info,
          title: announcement.title.isEmpty ? null : announcement.title,
          message: announcement.message,
          dismissLabel: l10n.close,
          onDismiss: () => unawaited(operations.dismissAnnouncement()),
        ),
      if (showUpdate)
        _OperationsBanner(
          key: const Key('appOpsUpdateBanner'),
          dismissKey: const Key('appOpsUpdateDismiss'),
          tone: MevoraTone.info,
          icon: MevoraIcons.info,
          message: l10n.appOpsUpdateAvailable,
          actionLabel: l10n.appOpsUpdateAction,
          onAction: (bannerContext) => unawaited(
            openAppUpdate(
              bannerContext,
              url: operations.updateUrl,
              platform: operations.platform,
              launcher: launcher,
            ),
          ),
          dismissLabel: l10n.close,
          onDismiss: () => unawaited(operations.dismissUpdateRecommendation()),
        ),
    ];
    final hasBanner = banners.isNotEmpty;
    return Column(
      children: [
        for (var i = 0; i < banners.length; i++)
          MediaQuery.removePadding(
            context: context,
            removeTop: i > 0,
            child: banners[i],
          ),
        Expanded(
          key: const ValueKey('appOpsNavigatorSlot'),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: hasBanner,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _OperationsBanner extends StatelessWidget {
  const _OperationsBanner({
    super.key,
    required this.dismissKey,
    required this.tone,
    required this.icon,
    required this.message,
    required this.dismissLabel,
    required this.onDismiss,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  final Key dismissKey;
  final MevoraTone tone;
  final IconData icon;
  final String? title;
  final String message;
  final String? actionLabel;
  final void Function(BuildContext context)? onAction;
  final String dismissLabel;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = mevoraToneColors(context, tone);
    // No Tooltip here: this sits above the navigator, outside any Overlay.
    return Material(
      color: c.bg,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: c.strong),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(
                          title!,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: c.fg,
                          ),
                        ),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          color: c.fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: () => onAction!(context),
                  style: TextButton.styleFrom(foregroundColor: c.strong),
                  child: Text(actionLabel!),
                ),
              Semantics(
                button: true,
                label: dismissLabel,
                excludeSemantics: true,
                child: InkResponse(
                  key: dismissKey,
                  onTap: onDismiss,
                  radius: AppSpacing.minTouchTarget / 2,
                  child: SizedBox.square(
                    dimension: AppSpacing.minTouchTarget,
                    child: Icon(MevoraIcons.close, size: 18, color: c.fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
