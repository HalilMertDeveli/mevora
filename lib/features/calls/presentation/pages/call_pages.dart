import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class IncomingCallPage extends StatelessWidget {
  const IncomingCallPage({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.of(context);
    return AnimatedBuilder(
      animation: social.callController,
      builder: (context, _) {
        final session = social.callController.session;
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IncomingCallPulse(
                  child: MevoraAvatar(
                    name: session?.remoteName ?? 'Mevora',
                    image: session?.remotePhotoUrl == null
                        ? null
                        : NetworkImage(session!.remotePhotoUrl!),
                    size: 120,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  session?.remoteName ?? '',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(l10n.incomingCall),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    MevoraButton(
                      label: l10n.decline,
                      variant: MevoraButtonVariant.destructive,
                      isExpanded: false,
                      onPressed: () {
                        unawaited(social.callController.decline());
                        context.pop();
                      },
                    ),
                    MevoraButton(
                      label: l10n.accept,
                      isExpanded: false,
                      onPressed: () {
                        unawaited(social.callController.accept());
                        context.go(AppRoutes.videoCallPath(callId));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class IncomingCallPulse extends StatefulWidget {
  const IncomingCallPulse({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallPulse> createState() => _IncomingCallPulseState();
}

class _IncomingCallPulseState extends State<IncomingCallPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.85, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.03).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: widget.child,
      ),
    );
  }
}

class VideoCallPage extends StatelessWidget {
  const VideoCallPage({super.key, required this.callId});

  final String callId;

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.of(context);
    final controller = social.callController;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: controller.remoteVideo
                    ? const ColoredBox(color: Colors.black)
                    : Center(
                        child: MevoraAvatar(
                          name: session?.remoteName ?? 'Mevora',
                          size: 120,
                        ),
                      ),
              ),
              Positioned(
                right: 16,
                top: 48,
                child: SizedBox(
                  width: 110,
                  height: 160,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: controller.cameraOn
                        ? const SizedBox.expand()
                        : Center(
                            child: MevoraAvatar(
                              name: session?.remoteName ?? 'Me',
                              size: 56,
                            ),
                          ),
                  ),
                ),
              ),
              if (controller.unstable)
                Positioned(
                  top: 56,
                  left: 0,
                  right: 0,
                  child: Text(
                    l10n.connectionUnstable,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              if (controller.error != null)
                Positioned(
                  top: 88,
                  left: 16,
                  right: 16,
                  child: Text(
                    L10nErrors.message(l10n, controller.error),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: CallControls(
                  cameraOn: controller.cameraOn,
                  micOn: controller.micOn,
                  speakerOn: controller.speakerOn,
                  onToggleCamera: () => unawaited(controller.toggleCamera()),
                  onToggleMute: () => unawaited(controller.toggleMute()),
                  onToggleSpeaker: () => unawaited(controller.toggleSpeaker()),
                  onSwitchCamera: () => unawaited(controller.switchCamera()),
                  onEnd: () {
                    unawaited(controller.hangUp());
                    context.pop();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CallControls extends StatelessWidget {
  const CallControls({
    super.key,
    required this.cameraOn,
    required this.micOn,
    required this.speakerOn,
    required this.onToggleCamera,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onSwitchCamera,
    required this.onEnd,
  });

  final bool cameraOn;
  final bool micOn;
  final bool speakerOn;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onSwitchCamera;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton.filledTonal(
          tooltip: l10n.mute,
          onPressed: onToggleMute,
          icon: Icon(micOn ? Icons.mic : Icons.mic_off),
        ),
        IconButton.filledTonal(
          tooltip: l10n.cameraOff,
          onPressed: onToggleCamera,
          icon: Icon(cameraOn ? Icons.videocam : Icons.videocam_off),
        ),
        IconButton.filledTonal(
          tooltip: l10n.switchCamera,
          onPressed: onSwitchCamera,
          icon: const Icon(Icons.cameraswitch_outlined),
        ),
        IconButton.filledTonal(
          tooltip: l10n.speaker,
          onPressed: onToggleSpeaker,
          icon: Icon(speakerOn ? Icons.volume_up : Icons.volume_off),
        ),
        IconButton.filled(
          tooltip: l10n.endCall,
          onPressed: onEnd,
          style: IconButton.styleFrom(backgroundColor: Colors.red),
          icon: const Icon(Icons.call_end),
        ),
      ],
    );
  }
}

Duration get callPulseDuration => AppDurations.long;
