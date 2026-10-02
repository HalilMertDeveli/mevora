import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
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
  final pageContext = context;
  return MevoraBottomSheet.showActions<_ChatAction>(
    context,
    title: l10n.more,
    actions: [
      MevoraSheetAction(
        value: _ChatAction.unmatch,
        label: l10n.unmatch,
        icon: MevoraIcons.unmatch,
      ),
      MevoraSheetAction(
        value: _ChatAction.block,
        label: l10n.block,
        icon: MevoraIcons.block,
        destructive: true,
      ),
      MevoraSheetAction(
        value: _ChatAction.report,
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
      case _ChatAction.unmatch:
        unawaited(_unmatch(pageContext, controller));
      case _ChatAction.block:
        unawaited(_block(pageContext, controller));
      case _ChatAction.report:
        unawaited(
          pageContext.push(
            '${AppRoutes.report}?userId=${controller.otherUid}&matchId=${controller.matchId}',
          ),
        );
    }
  });
}

enum _ChatAction { unmatch, block, report }

Future<void> _unmatch(BuildContext context, ChatController controller) async {
  if (!context.mounted) {
    return;
  }
  try {
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
  } on Object {
    if (context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.somethingWentWrong)));
    }
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
  if (ok != true || !context.mounted) {
    return;
  }
  try {
    await SocialScope.of(context).safetyRepository.blockUser(
      userId: controller.otherUid,
      matchId: controller.matchId,
    );
  } on Object {
    // Said out loud: a member who is told nothing leaves believing the other
    // person is blocked.
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.blockFailedMessage)));
    }
  }
}
