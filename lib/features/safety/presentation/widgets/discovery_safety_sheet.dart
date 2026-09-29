import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

typedef DiscoverySafetyAction = Future<void> Function(String userId);

Future<void> showDiscoverySafetySheet(
  BuildContext context, {
  required String userId,
  Future<void> Function(String userId)? onHide,
  Future<void> Function(String userId)? onBlocked,
}) {
  final l10n = AppLocalizations.of(context);
  final pageContext = context;
  return MevoraBottomSheet.showActions<_SafetyAction>(
    context,
    title: l10n.more,
    actions: [
      MevoraSheetAction(
        value: _SafetyAction.hide,
        label: l10n.hideProfile,
        subtitle: l10n.hideProfileMessage,
        icon: MevoraIcons.hidden,
      ),
      MevoraSheetAction(
        value: _SafetyAction.block,
        label: l10n.block,
        icon: MevoraIcons.block,
        destructive: true,
      ),
      MevoraSheetAction(
        value: _SafetyAction.report,
        label: l10n.report,
        icon: MevoraIcons.report,
        destructive: true,
      ),
    ],
  ).then((action) {
    if (action == null || !pageContext.mounted) {
      return;
    }
    switch (action) {
      case _SafetyAction.hide:
        unawaited(_hide(pageContext, userId, onHide));
      case _SafetyAction.block:
        unawaited(_block(pageContext, userId, onBlocked));
      case _SafetyAction.report:
        unawaited(pageContext.push('${AppRoutes.report}?userId=$userId'));
    }
  });
}

enum _SafetyAction { hide, block, report }

Future<void> _hide(
  BuildContext context,
  String userId,
  Future<void> Function(String userId)? onHide,
) async {
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  final ok = await MevoraDialog.show(
    context,
    title: l10n.hideProfileTitle,
    message: l10n.hideProfileMessage,
    confirmLabel: l10n.hideProfile,
  );
  if (ok != true || !context.mounted) {
    return;
  }
  if (onHide != null) {
    await onHide(userId);
  }
}

Future<void> _block(
  BuildContext context,
  String userId,
  Future<void> Function(String userId)? onBlocked,
) async {
  if (!context.mounted) {
    return;
  }
  final l10n = AppLocalizations.of(context);
  final ok = await MevoraDialog.show(
    context,
    title: l10n.blockConfirmTitle,
    message: l10n.blockConfirmMessage,
    confirmLabel: l10n.block,
    confirmVariant: MevoraButtonVariant.destructive,
  );
  if (ok != true || !context.mounted) {
    return;
  }
  try {
    await SocialScope.of(context).safetyRepository.blockUser(userId: userId);
    await BoostScope.maybeOf(
      context,
    )?.analytics?.logEvent(AnalyticsEvents.userBlocked);
    if (onBlocked != null) {
      await onBlocked(userId);
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
  }
}
