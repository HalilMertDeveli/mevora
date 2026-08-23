import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/chat/data/services/chat_audio_player.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_press_scale.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.onDelete,
    this.audioPlayer,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback? onDelete;
  final ChatAudioPlayer? audioPlayer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    return Align(
      alignment: alignment,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: AppDurations.short,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, (1 - value) * 8),
              child: child,
            ),
          );
        },
        child: GestureDetector(
          onLongPress: isMine && !message.deleted ? onDelete : null,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isMine ? colors.primary : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _body(context, l10n, colors),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timeLabel(message.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isMine
                            ? colors.onPrimary.withValues(alpha: 0.8)
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (isMine && !message.deleted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.status == MessageStatus.read
                            ? Icons.done_all
                            : Icons.done,
                        size: 14,
                        color: message.status == MessageStatus.read
                            ? colors.tertiaryContainer
                            : colors.onPrimary.withValues(alpha: 0.8),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, ColorScheme colors) {
    final textColor = isMine ? colors.onPrimary : colors.onSurface;
    if (message.deleted) {
      return Text(
        l10n.messageDeleted,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: textColor.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (message.type == MessageType.image) {
      return ChatImageBody(
        url: message.mediaUrl,
        bytes: message.localMediaBytes,
        textColor: textColor,
      );
    }
    if (message.type == MessageType.voice) {
      return ChatVoiceBody(
        url: message.mediaUrl,
        durationMs: message.durationMs ?? 0,
        textColor: textColor,
        player: audioPlayer,
      );
    }
    return Text(
      message.text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: textColor),
    );
  }

  static String _timeLabel(DateTime at) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class ChatImageBody extends StatelessWidget {
  const ChatImageBody({
    super.key,
    required this.url,
    required this.textColor,
    this.bytes,
  });

  final String? url;
  final List<int>? bytes;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final local = bytes;
    final ImageProvider? provider;
    if (local != null && local.isNotEmpty) {
      provider = MemoryImage(Uint8List.fromList(local));
    } else {
      provider = MevoraNetworkImages.provider(url);
    }
    if (provider == null) {
      return Icon(Icons.image_outlined, color: textColor);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Image(
        image: provider,
        width: 220,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) {
          return SizedBox(
            width: 220,
            height: 120,
            child: Icon(Icons.broken_image_outlined, color: textColor),
          );
        },
      ),
    );
  }
}

class ChatVoiceBody extends StatefulWidget {
  const ChatVoiceBody({
    super.key,
    required this.url,
    required this.durationMs,
    required this.textColor,
    this.player,
  });

  final String? url;
  final int durationMs;
  final Color textColor;
  final ChatAudioPlayer? player;

  @override
  State<ChatVoiceBody> createState() => _ChatVoiceBodyState();
}

class _ChatVoiceBodyState extends State<ChatVoiceBody> {
  bool _playing = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerComplete>? _doneSub;

  @override
  void dispose() {
    unawaited(_posSub?.cancel());
    unawaited(_doneSub?.cancel());
    super.dispose();
  }

  Future<void> _toggle() async {
    final player = widget.player;
    final url = widget.url;
    if (player == null || url == null || url.isEmpty) {
      return;
    }
    if (_playing) {
      await player.pause();
      setState(() => _playing = false);
      return;
    }
    await player.play(url);
    setState(() => _playing = true);
    unawaited(_doneSub?.cancel());
    _doneSub = player.watchComplete().listen((_) {
      if (mounted) {
        setState(() => _playing = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final seconds = (widget.durationMs / 1000).ceil().clamp(1, 180);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.url == null ? null : () => unawaited(_toggle()),
          tooltip: _playing
              ? AppLocalizations.of(context).pauseVoice
              : AppLocalizations.of(context).playVoice,
          icon: Icon(
            _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: widget.textColor,
          ),
        ),
        Icon(Icons.graphic_eq, color: widget.textColor, size: 18),
        const SizedBox(width: 8),
        Text(
          '$seconds″',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: widget.textColor,
          ),
        ),
      ],
    );
  }
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.name});

  final String name;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Text('${widget.name} ${AppLocalizations.of(context).typing}'),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Row(
                children: List.generate(3, (index) {
                  final active =
                      (_controller.value * 3).floor() % 3 == index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: active ? 1 : 0.3,
                      child: const CircleAvatar(radius: 3),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Bottom message bar: compact attach | wide multiline field | mic or send.
///
/// Keeps photo, camera, voice, and send callbacks — only the layout changes.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onSend,
    this.onAttachPhoto,
    this.onAttachCamera,
    this.onVoiceStart,
    this.onVoiceEnd,
    this.recording = false,
    this.uploading = false,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback? onAttachPhoto;
  final VoidCallback? onAttachCamera;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceEnd;
  final bool recording;
  final bool uploading;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  static const double _actionSize = 44;
  static const int _maxInputLines = 5;

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Material(
      color: colors.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm + bottomInset,
          ),
          // While recording, listen for pointer-up on the whole bar so ending
          // the long-press still works after the mic button is swapped out.
          child: widget.recording
              ? Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerUp: (_) => widget.onVoiceEnd?.call(),
                  onPointerCancel: (_) => widget.onVoiceEnd?.call(),
                  child: _RecordingBar(label: l10n.holdToRecord),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _AttachMenuButton(
                      enabled: widget.enabled && !widget.uploading,
                      onAttachPhoto: widget.onAttachPhoto,
                      onAttachCamera: widget.onAttachCamera,
                      attachPhotoLabel: l10n.attachPhoto,
                      takePhotoLabel: l10n.takePhoto,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: _buildInput(context, l10n, colors)),
                    const SizedBox(width: AppSpacing.xs),
                    if (_hasText)
                      _SendButton(
                        enabled: widget.enabled && !widget.uploading,
                        uploading: widget.uploading,
                        tooltip: l10n.send,
                        onSend: widget.onSend,
                      )
                    else
                      _VoiceButton(
                        enabled: widget.enabled && !widget.uploading,
                        recording: widget.recording,
                        tooltip: l10n.recordVoice,
                        onVoiceStart: widget.onVoiceStart,
                        onVoiceEnd: widget.onVoiceEnd,
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildInput(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme colors,
  ) {
    final radius = BorderRadius.circular(AppRadii.lg);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _actionSize),
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled && !widget.uploading,
        minLines: 1,
        maxLines: _maxInputLines,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        textCapitalization: TextCapitalization.sentences,
        onChanged: widget.onChanged,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: l10n.chatHint,
          isDense: true,
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
              color: colors.primary.withValues(alpha: 0.45),
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _AttachMenuButton extends StatelessWidget {
  const _AttachMenuButton({
    required this.enabled,
    required this.onAttachPhoto,
    required this.onAttachCamera,
    required this.attachPhotoLabel,
    required this.takePhotoLabel,
  });

  final bool enabled;
  final VoidCallback? onAttachPhoto;
  final VoidCallback? onAttachCamera;
  final String attachPhotoLabel;
  final String takePhotoLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ChatComposerState._actionSize,
      height: _ChatComposerState._actionSize,
      child: PopupMenuButton<String>(
        key: const ValueKey('chat-attach'),
        enabled: enabled && (onAttachPhoto != null || onAttachCamera != null),
        tooltip: attachPhotoLabel,
        padding: EdgeInsets.zero,
        offset: const Offset(0, -8),
        position: PopupMenuPosition.under,
        icon: Icon(
          Icons.photo_outlined,
          color: enabled
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).disabledColor,
        ),
        onSelected: (value) {
          if (value == 'photo') {
            onAttachPhoto?.call();
          } else if (value == 'camera') {
            onAttachCamera?.call();
          }
        },
        itemBuilder: (context) => [
          if (onAttachPhoto != null)
            PopupMenuItem<String>(
              key: const ValueKey('chat-attach-photo'),
              value: 'photo',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_outlined),
                title: Text(attachPhotoLabel),
              ),
            ),
          if (onAttachCamera != null)
            PopupMenuItem<String>(
              key: const ValueKey('chat-attach-camera'),
              value: 'camera',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(takePhotoLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.enabled,
    required this.uploading,
    required this.tooltip,
    required this.onSend,
  });

  final bool enabled;
  final bool uploading;
  final String tooltip;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MevoraPressScale(
      enabled: enabled,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: enabled ? colors.primary : colors.surfaceContainerHighest,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onSend : null,
            child: SizedBox(
              width: _ChatComposerState._actionSize,
              height: _ChatComposerState._actionSize,
              child: Center(
                child: uploading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.onPrimary,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        size: 20,
                        color: enabled
                            ? colors.onPrimary
                            : colors.onSurfaceVariant,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.enabled,
    required this.recording,
    required this.tooltip,
    required this.onVoiceStart,
    required this.onVoiceEnd,
  });

  final bool enabled;
  final bool recording;
  final String tooltip;
  final VoidCallback? onVoiceStart;
  final VoidCallback? onVoiceEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: enabled && onVoiceStart != null
          ? (_) => onVoiceStart!()
          : null,
      onLongPressEnd: enabled && onVoiceEnd != null
          ? (_) => onVoiceEnd!()
          : null,
      child: Tooltip(
        message: tooltip,
        child: SizedBox(
          key: const ValueKey('chat-record-voice'),
          width: _ChatComposerState._actionSize,
          height: _ChatComposerState._actionSize,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: recording
                  ? colors.errorContainer
                  : colors.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.mic_none_rounded,
              color: recording
                  ? colors.error
                  : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: _ChatComposerState._actionSize + 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppSpacing.md),
            const _RecordingPulse(),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Icon(
                Icons.mic_rounded,
                color: colors.error,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingPulse extends StatefulWidget {
  const _RecordingPulse();

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 10 + t * 2,
          height: 10 + t * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.55 + t * 0.45),
          ),
        );
      },
    );
  }
}
