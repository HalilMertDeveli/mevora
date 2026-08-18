import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

Future<void> showChatMoreSheet(
  BuildContext context, {
  required ChatController controller,
}) {
  final l10n = AppLocalizations.of(context);
  return MevoraBottomSheet.show<void>(
    context,
    title: l10n.more,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.heart_broken_outlined),
          title: Text(l10n.unmatch),
          onTap: () {
            Navigator.pop(context);
            unawaited(_unmatch(context, controller));
          },
        ),
        ListTile(
          leading: const Icon(Icons.block),
          title: Text(l10n.block),
          onTap: () {
            Navigator.pop(context);
            unawaited(_block(context, controller));
          },
        ),
        ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: Text(l10n.report),
          onTap: () {
            Navigator.pop(context);
            context.push(
              '${AppRoutes.report}?userId=${controller.otherUid}&matchId=${controller.matchId}',
            );
          },
        ),
      ],
    ),
  );
}

Future<void> _unmatch(BuildContext context, ChatController controller) async {
  final l10n = AppLocalizations.of(context);
  final ok = await MevoraDialog.show(
    context,
    title: l10n.unmatchConfirmTitle,
    message: l10n.unmatchConfirmMessage,
    confirmLabel: l10n.unmatch,
    confirmVariant: MevoraButtonVariant.destructive,
  );
  if (ok == true && context.mounted) {
    final social = SocialScope.of(context);
    await social.safetyRepository.unmatch(matchId: controller.matchId);
    await social.retentionPolicy.scheduleAfterUnmatch(
      matchId: controller.matchId,
    );
  }
}

Future<void> _block(BuildContext context, ChatController controller) async {
  final l10n = AppLocalizations.of(context);
  final ok = await MevoraDialog.show(
    context,
    title: l10n.blockConfirmTitle,
    message: l10n.blockConfirmMessage,
    confirmLabel: l10n.block,
    confirmVariant: MevoraButtonVariant.destructive,
  );
  if (ok == true && context.mounted) {
    await SocialScope.of(context).safetyRepository.blockUser(
      userId: controller.otherUid,
      matchId: controller.matchId,
    );
  }
}
