import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/safety/presentation/widgets/chat_more_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.matchId, this.controller});

  final String matchId;
  final ChatController? controller;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  ChatController? _controller;
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  ChatController get ctrl => _controller!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final social = SocialScope.of(context);
    _controller = widget.controller ??
        ChatController(
          matchId: widget.matchId,
          chatRepository: social.chatRepository,
          matchRepository: social.matchRepository,
          safetyRepository: social.safetyRepository,
          presenceRepository: social.presenceRepository,
          uidSource: social.uidSource,
        );
    _scroll.addListener(_onScroll);
    unawaited(ctrl.start());
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 40) {
      unawaited(ctrl.loadOlder());
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Scaffold(body: MevoraLoading.page());
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final presence = controller.presence.labelFor(l10n);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(controller.otherName),
                if (presence.isNotEmpty)
                  Text(
                    presence,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: l10n.videoCall,
                onPressed: controller.canCall
                    ? () => unawaited(_startCall())
                    : null,
                icon: const Icon(Icons.videocam_outlined),
              ),
              IconButton(
                tooltip: l10n.more,
                onPressed: () => unawaited(
                  showChatMoreSheet(context, controller: controller),
                ),
                icon: const Icon(Icons.more_vert),
              ),
            ],
          ),
          body: Column(
            children: [
              if (!controller.canChat)
                MaterialBanner(
                  content: Text(l10n.unmatchedBanner),
                  actions: const [SizedBox.shrink()],
                ),
              if (controller.error != null)
                MevoraErrorView(
                  message: L10nErrors.message(l10n, controller.error),
                ),
              Expanded(
                child: controller.messages.isEmpty
                    ? MevoraEmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        riveAsset: MevoraRiveAssets.chatEmpty,
                        title: l10n.chatEmptyTitle,
                        message: l10n.chatEmptyMessage,
                      )
                    : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: controller.messages.length,
                  itemBuilder: (context, index) {
                    final ordered = controller.messages.reversed.toList();
                    final message = ordered[index];
                    return ChatBubble(
                      message: message,
                      isMine: message.isFrom(controller.uid ?? ''),
                    );
                  },
                ),
              ),
              if (controller.typingUid != null)
                TypingDots(name: controller.otherName),
              ChatComposer(
                controller: _composer,
                enabled: controller.canChat,
                onChanged: controller.onComposerChanged,
                onSend: () {
                  final text = _composer.text;
                  _composer.clear();
                  unawaited(controller.send(text));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startCall() async {
    final l10n = AppLocalizations.of(context);
    final allowed = await MevoraDialog.show(
      context,
      title: l10n.callPermissionTitle,
      message: l10n.callPermissionBody,
      confirmLabel: l10n.continueAction,
    );
    if (allowed != true || !mounted) {
      return;
    }
    final permissions = PermissionScope.maybeOf(context)?.controller;
    if (permissions != null) {
      final camera = await permissions.request(PermissionType.camera);
      if (!mounted) {
        return;
      }
      if (!camera.isUsable) {
        if (camera.isPermanentlyDenied) {
          final open = await MevoraDialog.show(
            context,
            title: l10n.permissionDeniedTitle,
            message: l10n.permissionPermanentlyDeniedBody,
            confirmLabel: l10n.openSettings,
          );
          if (open == true) {
            await permissions.openSettings();
          }
        }
        return;
      }
      final mic = await permissions.request(PermissionType.microphone);
      if (!mounted) {
        return;
      }
      if (!mic.isUsable) {
        if (mic.isPermanentlyDenied) {
          final open = await MevoraDialog.show(
            context,
            title: l10n.permissionDeniedTitle,
            message: l10n.permissionPermanentlyDeniedBody,
            confirmLabel: l10n.openSettings,
          );
          if (open == true) {
            await permissions.openSettings();
          }
        }
        return;
      }
    }
    final social = SocialScope.of(context);
    await social.callController.startCall(
      matchId: widget.matchId,
      receiverId: ctrl.otherUid,
    );
    if (!mounted) {
      return;
    }
    final callId = social.callController.session?.id;
    if (callId != null) {
      context.push(AppRoutes.videoCallPath(callId));
    }
  }
}
