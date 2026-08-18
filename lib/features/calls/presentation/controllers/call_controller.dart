import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/errors/social_error_mapper.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/calls/domain/call_state_machine.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/call_strings.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/safety/presentation/safety_strings.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';

class CallController extends ChangeNotifier {
  CallController({
    required VideoCallService service,
    required VideoCallProvider provider,
  }) : _service = service,
       _provider = provider;

  final VideoCallService _service;
  final VideoCallProvider _provider;

  CallSession? session;
  CallLifecycle lifecycle = CallLifecycle.idle;
  String? error;
  bool cameraOn = true;
  bool micOn = true;
  bool speakerOn = true;
  bool remoteVideo = false;
  bool unstable = false;

  VideoCallProvider get provider => _provider;

  StreamSubscription<CallSession>? _incomingSub;
  StreamSubscription<VideoConnectionEvent>? _mediaSub;
  Timer? _ringTimer;

  void watchIncoming(String uid) {
    _incomingSub?.cancel();
    _incomingSub = _service.watchIncoming(uid).listen((incoming) {
      session = incoming;
      lifecycle = CallStateMachine.transition(
        lifecycle,
        CallEvent.receiveIncoming,
      );
      notifyListeners();
    });
  }

  Future<void> startCall({
    required String matchId,
    required String receiverId,
  }) async {
    error = null;
    lifecycle = CallStateMachine.transition(
      lifecycle,
      CallEvent.startOutgoing,
    );
    notifyListeners();
    try {
      session = await _service.startCall(
        matchId: matchId,
        receiverId: receiverId,
      );
      _armTimeout();
      notifyListeners();
    } on Object catch (err) {
      final failure = SocialErrorMapper.map(err);
      error = failure.message;
      lifecycle = failure.message == CallStrings.userBusy
          ? CallLifecycle.busy
          : CallLifecycle.failed;
      notifyListeners();
    }
  }

  Future<void> accept() async {
    final current = session;
    if (current == null) {
      return;
    }
    lifecycle = CallStateMachine.transition(lifecycle, CallEvent.accept);
    notifyListeners();
    try {
      session = await _service.acceptCall(current.id);
      await _connect();
    } on Object catch (err) {
      error = SocialErrorMapper.map(err).message;
      lifecycle = CallLifecycle.failed;
      notifyListeners();
    }
  }

  Future<void> decline() async {
    final current = session;
    lifecycle = CallStateMachine.transition(lifecycle, CallEvent.decline);
    notifyListeners();
    if (current != null) {
      await _service.declineCall(current.id);
    }
    await _provider.disconnect();
  }

  Future<void> hangUp() async {
    final current = session;
    lifecycle = CallStateMachine.transition(lifecycle, CallEvent.end);
    notifyListeners();
    if (current != null) {
      await _service.endCall(current.id);
    }
    await _provider.disconnect();
  }

  Future<void> toggleMute() async {
    micOn = !micOn;
    await _provider.setMicrophoneEnabled(micOn);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraOn = !cameraOn;
    await _provider.setCameraEnabled(cameraOn);
    notifyListeners();
  }

  Future<void> switchCamera() => _provider.switchCamera();

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await _provider.setSpeakerEnabled(speakerOn);
    notifyListeners();
  }

  Future<void> _connect() async {
    final current = session;
    if (current?.token == null || current?.livekitUrl == null) {
      error = CallStrings.notConfigured;
      lifecycle = CallLifecycle.failed;
      notifyListeners();
      return;
    }
    lifecycle = CallLifecycle.connecting;
    notifyListeners();
    await _provider.connect(
      VideoConnectParams(
        url: current!.livekitUrl!,
        token: current.token!,
        roomName: current.roomName ?? current.id,
      ),
    );
    _mediaSub = _provider.watch().listen((event) {
      remoteVideo = event.remoteVideoAvailable;
      cameraOn = event.localVideoEnabled;
      unstable = event.quality == VideoConnectionQuality.unstable;
      lifecycle = event.lifecycleHint;
      notifyListeners();
    });
  }

  void _armTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(CallPolicy.ringTimeout, () {
      if (lifecycle == CallLifecycle.calling ||
          lifecycle == CallLifecycle.ringing) {
        lifecycle = CallStateMachine.transition(lifecycle, CallEvent.timeout);
        final id = session?.id;
        if (id != null) {
          unawaited(_service.expireCall(id));
        }
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    unawaited(_incomingSub?.cancel());
    unawaited(_mediaSub?.cancel());
    super.dispose();
  }
}

Future<void> confirmUnmatch(BuildContext context, VoidCallback onConfirm) async {
  final ok = await MevoraDialog.show(
    context,
    title: SafetyStrings.unmatchConfirmTitle,
    message: SafetyStrings.unmatchConfirmMessage,
    confirmLabel: SafetyStrings.unmatch,
    confirmVariant: MevoraButtonVariant.destructive,
  );
  if (ok == true) {
    onConfirm();
  }
}

void openVideoCall(BuildContext context, String callId) {
  context.push(AppRoutes.videoCallPath(callId));
}
