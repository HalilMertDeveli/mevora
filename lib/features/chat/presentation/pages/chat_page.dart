import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/chat/data/services/chat_audio_player.dart';
import 'package:mevora/features/chat/data/services/record_chat_voice_recorder.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/domain/services/chat_voice_recorder.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/chat/presentation/widgets/chat_widgets.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/match_score/presentation/widgets/match_feedback_prompt.dart';
import 'package:mevora/features/profile/data/services/profile_image_pipeline.dart';
import 'package:mevora/features/safety/presentation/widgets/chat_more_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.matchId,
    this.controller,
    this.voiceRecorder,
    this.audioPlayer,
    this.imagePicker,
  });

  final String matchId;
  final ChatController? controller;
  final ChatVoiceRecorder? voiceRecorder;
  final ChatAudioPlayer? audioPlayer;
  final ImagePicker? imagePicker;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  ChatController? _controller;
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  late final ChatVoiceRecorder _recorder;
  late final ChatAudioPlayer _player;
  late final ImagePicker _picker;
  bool _recording = false;

  ChatController get ctrl => _controller!;

  @override
  void initState() {
    super.initState();
    _recorder = widget.voiceRecorder ?? RecordChatVoiceRecorder();
    _player = widget.audioPlayer ?? AudioplayersChatAudioPlayer();
    _picker = widget.imagePicker ?? ImagePicker();
  }

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
    _scroll.removeListener(_onScroll);
    _composer.dispose();
    _scroll.dispose();
    unawaited(_player.dispose());
    unawaited(_recorder.cancel());
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        body: MevoraLoading.page(asset: MevoraRiveAssets.loading),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context);
        final presence = controller.presence.labelFor(l10n);
        final orderedMessages = controller.messages.reversed.toList();
        return Scaffold(
          resizeToAvoidBottomInset: true,
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
              if (!controller.canChat)
                MatchFeedbackForChat(matchId: controller.matchId),
              if (controller.error != null)
                MevoraErrorView(
                  message: L10nErrors.message(l10n, controller.error),
                ),
              if (controller.uploadProgress != null)
                LinearProgressIndicator(value: controller.uploadProgress),
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
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: orderedMessages.length,
                        itemBuilder: (context, index) {
                          final message = orderedMessages[index];
                          return ChatBubble(
                            message: message,
                            isMine: message.isFrom(controller.uid ?? ''),
                            audioPlayer: _player,
                            onDelete: () => unawaited(_confirmDelete(message)),
                          );
                        },
                      ),
              ),
              if (controller.typingUid != null)
                TypingDots(name: controller.otherName),
              ChatComposer(
                controller: _composer,
                enabled: controller.canChat,
                recording: _recording,
                uploading: controller.sending,
                onChanged: controller.onComposerChanged,
                onAttachPhoto: () => unawaited(_pick(ImageSource.gallery)),
                onAttachCamera: () => unawaited(_pick(ImageSource.camera)),
                onVoiceStart: () => unawaited(_startVoice()),
                onVoiceEnd: () => unawaited(_stopVoice()),
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

  Future<void> _confirmDelete(ChatMessage message) async {
    final l10n = AppLocalizations.of(context);
    final ok = await MevoraDialog.show(
      context,
      title: l10n.deleteMessage,
      message: l10n.deleteMessageConfirm,
      confirmLabel: l10n.deleteMessage,
    );
    if (ok == true) {
      await ctrl.deleteOwn(message);
    }
  }

  Future<bool> _ensurePermission(PermissionType type) async {
    final l10n = AppLocalizations.of(context);
    final permissions = PermissionScope.maybeOf(context)?.controller;
    if (permissions == null) {
      return true;
    }
    final status = await permissions.request(type);
    if (!mounted) {
      return false;
    }
    if (status.isUsable) {
      return true;
    }
    if (status.isPermanentlyDenied) {
      final open = await MevoraDialog.show(
        context,
        title: l10n.permissionDeniedTitle,
        message: l10n.permissionPermanentlyDeniedBody,
        confirmLabel: l10n.openSettings,
      );
      if (open == true) {
        await permissions.openSettings();
      }
    } else {
      final message = type == PermissionType.microphone
          ? l10n.micDeniedChat
          : l10n.photoDeniedChat;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    return false;
  }

  Future<void> _pick(ImageSource source) async {
    final type = source == ImageSource.camera
        ? PermissionType.camera
        : PermissionType.photos;
    final allowed = await _ensurePermission(type);
    if (!allowed || !mounted) {
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: ProfileImagePipeline.maxEdgePx.toDouble(),
        maxHeight: ProfileImagePipeline.maxEdgePx.toDouble(),
        imageQuality: 70,
      );
      if (file == null || !mounted) {
        return;
      }
      final bytes = await file.readAsBytes();
      final preview = await MevoraDialog.show(
        context,
        title: AppLocalizations.of(context).previewPhoto,
        message: AppLocalizations.of(context).send,
        confirmLabel: AppLocalizations.of(context).send,
      );
      if (preview != true || !mounted) {
        return;
      }
      await ctrl.sendImage(
        ChatMediaBytes(
          bytes: Uint8List.fromList(bytes),
          contentType: file.mimeType ?? 'image/jpeg',
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chatGeneric)),
      );
    }
  }

  Future<void> _startVoice() async {
    final allowed = await _ensurePermission(PermissionType.microphone);
    if (!allowed || !mounted) {
      return;
    }
    try {
      await _recorder.start();
      setState(() => _recording = true);
    } on ChatMicDenied {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).micDeniedChat)),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chatGeneric)),
      );
    }
  }

  Future<void> _stopVoice() async {
    if (!_recording) {
      return;
    }
    setState(() => _recording = false);
    try {
      final recorded = await _recorder.stop();
      if (recorded == null || !mounted) {
        return;
      }
      await ctrl.sendVoice(
        ChatMediaBytes(
          bytes: recorded.bytes,
          contentType: recorded.contentType,
          durationMs: recorded.durationMs,
        ),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).chatGeneric)),
      );
    }
  }

  Future<void> _startCall() async {
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
