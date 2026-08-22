import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/calls/domain/call_state_machine.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/presentation/controllers/call_controller.dart';
import 'package:mevora/features/calls/presentation/video_call_surface.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

class IncomingCallPage extends StatefulWidget {
  const IncomingCallPage({super.key, required this.callId});

  final String callId;

  @override
  State<IncomingCallPage> createState() => _IncomingCallPageState();
}

class _IncomingCallPageState extends State<IncomingCallPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.of(context);
    return AnimatedBuilder(
      animation: social.callController,
      builder: (context, _) {
        final session = social.callController.session;
        final l10n = AppLocalizations.of(context);
        final terminal = CallStateMachine.isTerminal(
          social.callController.lifecycle,
        );
        if (terminal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              context.pop();
            }
          });
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              unawaited(social.callController.decline());
              context.pop();
            }
          },
          child: Scaffold(
            body: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IncomingCallPulse(
                    child: MevoraAvatar(
                      name: session?.remoteName ?? 'Mevora',
                      image: MevoraNetworkImages.provider(
                        session?.remotePhotoUrl,
                      ),
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
                        onPressed: _busy
                            ? null
                            : () {
                                unawaited(social.callController.decline());
                                context.pop();
                              },
                      ),
                      MevoraButton(
                        label: l10n.accept,
                        isExpanded: false,
                        onPressed: _busy
                            ? null
                            : () => unawaited(_accept(social.callController)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _accept(CallController controller) async {
    setState(() => _busy = true);
    await controller.accept();
    if (!mounted) {
      return;
    }
    final mediaOk = await requestCallMedia(context);
    if (!mounted) {
      return;
    }
    if (mediaOk) {
      await controller.connectMedia();
    }
    if (!mounted) {
      return;
    }
    context.go(AppRoutes.videoCallPath(widget.callId));
  }
}

Future<bool> requestCallMedia(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final allowed = await MevoraDialog.show(
    context,
    title: l10n.callPermissionTitle,
    message: l10n.callPermissionBody,
    confirmLabel: l10n.continueAction,
  );
  if (allowed != true || !context.mounted) {
    return false;
  }
  final permissions = PermissionScope.maybeOf(context)?.controller;
  if (permissions == null) {
    return true;
  }
  final camera = await permissions.request(PermissionType.camera);
  final mic = await permissions.request(PermissionType.microphone);
  if (!context.mounted) {
    return false;
  }
  if (!camera.isUsable && camera.isPermanentlyDenied) {
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
  if (!mic.isUsable) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.micDenied)));
  }
  return camera.isUsable || mic.isUsable;
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
      opacity: Tween<double>(
        begin: 0.85,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.03).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: widget.child,
      ),
    );
  }
}

class VideoCallPage extends StatefulWidget {
  const VideoCallPage({super.key, required this.callId});

  final String callId;

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> {
  AppLifecycleListener? _lifecycle;
  bool _connectingMedia = false;
  bool _askedMedia = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        final social = SocialScope.maybeOf(context);
        unawaited(social?.callController.onAppBackgrounded());
      },
      onDetach: () {
        final social = SocialScope.maybeOf(context);
        unawaited(social?.callController.onAppBackgrounded());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _maybeConnect(CallController controller) async {
    if (_askedMedia || _connectingMedia || controller.mediaConnected) {
      return;
    }
    if (controller.lifecycle != CallLifecycle.connecting) {
      return;
    }
    _askedMedia = true;
    _connectingMedia = true;
    final ok = await requestCallMedia(context);
    if (!mounted) {
      return;
    }
    if (ok) {
      await controller.connectMedia();
    }
    _connectingMedia = false;
  }

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.of(context);
    final controller = social.callController;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        final l10n = AppLocalizations.of(context);
        if (controller.lifecycle == CallLifecycle.connecting &&
            !controller.mediaConnected) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_maybeConnect(controller));
          });
        }
        final surface = controller.provider is VideoCallSurface
            ? controller.provider as VideoCallSurface
            : null;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              unawaited(controller.hangUp());
              context.pop();
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child:
                      surface?.remoteVideo() ??
                      (controller.remoteVideo
                          ? const ColoredBox(color: Colors.black)
                          : Center(
                              child: MevoraAvatar(
                                name: session?.remoteName ?? 'Mevora',
                                size: 120,
                              ),
                            )),
                ),
                Positioned(
                  right: 16,
                  top: 48,
                  child: SizedBox(
                    width: 110,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(color: Colors.white24),
                        child:
                            surface?.localVideo() ??
                            (controller.cameraOn
                                ? const SizedBox.expand()
                                : Center(
                                    child: MevoraAvatar(
                                      name: session?.remoteName ?? 'Me',
                                      size: 56,
                                    ),
                                  )),
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
                if (controller.lifecycle == CallLifecycle.connecting ||
                    controller.lifecycle == CallLifecycle.calling ||
                    controller.lifecycle == CallLifecycle.reconnecting)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 120,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MevoraRiveAnimation(
                            asset: MevoraRiveAssets.callConnecting,
                            width: 48,
                            height: 48,
                            fit: BoxFit.contain,
                            fallback: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            controller.lifecycle == CallLifecycle.reconnecting
                                ? l10n.reconnecting
                                : controller.lifecycle == CallLifecycle.calling
                                ? l10n.calling
                                : l10n.connecting,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (controller.lifecycle == CallLifecycle.ended ||
                    controller.lifecycle == CallLifecycle.cancelled ||
                    controller.lifecycle == CallLifecycle.declined)
                  Positioned(
                    top: 120,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        const MevoraRiveAnimation(
                          asset: MevoraRiveAssets.success,
                          width: 64,
                          height: 64,
                          fallback: Icon(
                            Icons.call_end,
                            color: Colors.white70,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          controller.lifecycle == CallLifecycle.declined
                              ? l10n.callRejected
                              : controller.lifecycle == CallLifecycle.cancelled
                              ? l10n.callCancelled
                              : l10n.callEnded,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
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
                    onToggleSpeaker: () =>
                        unawaited(controller.toggleSpeaker()),
                    onSwitchCamera: () => unawaited(controller.switchCamera()),
                    onEnd: () {
                      unawaited(controller.hangUp());
                      context.pop();
                    },
                  ),
                ),
              ],
            ),
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
