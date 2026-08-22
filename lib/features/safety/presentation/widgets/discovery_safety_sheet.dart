import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  return MevoraBottomSheet.show<void>(
    context,
    title: l10n.more,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.visibility_off_outlined),
          title: Text(l10n.hideProfile),
          subtitle: Text(l10n.hideProfileMessage),
          onTap: () {
            Navigator.pop(context);
            unawaited(_hide(pageContext, userId, onHide));
          },
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: Text(l10n.block),
          onTap: () {
            Navigator.pop(context);
            unawaited(_block(pageContext, userId, onBlocked));
          },
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(l10n.report),
          onTap: () {
            Navigator.pop(context);
            pageContext.push('${AppRoutes.report}?userId=$userId');
          },
        ),
      ],
    ),
  );
}

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
    await BoostScope.maybeOf(context)?.analytics?.logEvent(
      AnalyticsEvents.userBlocked,
    );
    if (onBlocked != null) {
      await onBlocked(userId);
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.somethingWentWrong)),
      );
    }
  }
}
