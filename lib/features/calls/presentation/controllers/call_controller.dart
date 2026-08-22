import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/errors/social_error_mapper.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/calls/domain/call_state_machine.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/call_strings.dart';
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
  bool mediaConnected = false;
  bool awaitingRemoteAccept = false;

  VideoCallProvider get provider => _provider;

  StreamSubscription<CallSession>? _incomingSub;
  StreamSubscription<CallSession?>? _sessionSub;
  StreamSubscription<VideoConnectionEvent>? _mediaSub;
  Timer? _ringTimer;

  void watchIncoming(String uid) {
    unawaited(_incomingSub?.cancel());
    _incomingSub = _service.watchIncoming(uid).listen((incoming) {
      if (session != null &&
          session!.id.isNotEmpty &&
          session!.id != incoming.id &&
          !CallStateMachine.isTerminal(lifecycle)) {
        return;
      }
      session = incoming;
      lifecycle = CallStateMachine.transition(
        lifecycle,
        CallEvent.receiveIncoming,
      );
      _watchSession(incoming.id);
      _armTimeout();
      notifyListeners();
    }, onError: (_) {
      // Permission-denied after logout must not crash the app.
    });
  }

  void stopIncoming() {
    unawaited(_incomingSub?.cancel());
    _incomingSub = null;
  }

  Future<void> startCall({
    required String matchId,
    required String receiverId,
  }) async {
    error = null;
    mediaConnected = false;
    awaitingRemoteAccept = true;
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
      _watchSession(session!.id);
      _armTimeout();
      notifyListeners();
    } on Object catch (err) {
      final failure = SocialErrorMapper.map(err);
      error = failure.message;
      lifecycle = failure.message == CallStrings.userBusy
          ? CallLifecycle.busy
          : CallLifecycle.failed;
      awaitingRemoteAccept = false;
      notifyListeners();
    }
  }

  /// Signaling accept only. Camera/mic connect happens in [connectMedia].
  Future<void> accept() async {
    final current = session;
    if (current == null) {
      return;
    }
    lifecycle = CallStateMachine.transition(lifecycle, CallEvent.accept);
    notifyListeners();
    try {
      session = await _service.acceptCall(current.id);
      _watchSession(session!.id);
      notifyListeners();
    } on Object catch (err) {
      error = SocialErrorMapper.map(err).message;
      lifecycle = CallLifecycle.failed;
      notifyListeners();
    }
  }

  Future<void> connectMedia() async {
    if (mediaConnected) {
      return;
    }
    try {
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
      try {
        await _service.declineCall(current.id);
      } on Object {
        // Signaling hang-up is best-effort.
      }
    }
    await _teardownMedia();
  }

  Future<void> hangUp() async {
    final current = session;
    final event = lifecycle == CallLifecycle.calling ||
            lifecycle == CallLifecycle.ringing
        ? CallEvent.cancel
        : CallEvent.end;
    lifecycle = CallStateMachine.transition(lifecycle, event);
    notifyListeners();
    if (current != null) {
      try {
        await _service.endCall(current.id);
      } on Object {
        // Signaling hang-up is best-effort.
      }
    }
    await _teardownMedia();
  }

  Future<void> toggleMute() async {
    micOn = !micOn;
    try {
      await _provider.setMicrophoneEnabled(micOn);
    } on Object {
      micOn = !micOn;
    }
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraOn = !cameraOn;
    try {
      await _provider.setCameraEnabled(cameraOn);
    } on Object {
      cameraOn = !cameraOn;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    try {
      await _provider.switchCamera();
    } on Object {
      // Device without a second camera must not crash.
    }
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    try {
      await _provider.setSpeakerEnabled(speakerOn);
    } on Object {
      speakerOn = !speakerOn;
    }
    notifyListeners();
  }

  Future<void> onAppBackgrounded() async {
    if (CallStateMachine.isTerminal(lifecycle) ||
        lifecycle == CallLifecycle.idle) {
      return;
    }
    await hangUp();
  }

  void _watchSession(String callId) {
    unawaited(_sessionSub?.cancel());
    _sessionSub = _service.watchCall(callId).listen((remote) {
      if (remote == null) {
        return;
      }
      session = session == null
          ? remote
          : remote.copyWith(
              livekitUrl: session?.livekitUrl ?? remote.livekitUrl,
              token: session?.token ?? remote.token,
              roomName: session?.roomName ?? remote.roomName,
            );
      _applyRemoteLifecycle(remote.lifecycle);
    }, onError: (_) {});
  }

  void _applyRemoteLifecycle(CallLifecycle remote) {
    switch (remote) {
      case CallLifecycle.connecting:
      case CallLifecycle.connected:
        if (awaitingRemoteAccept && lifecycle == CallLifecycle.calling) {
          lifecycle = CallStateMachine.transition(
            lifecycle,
            CallEvent.remoteAccepted,
          );
          awaitingRemoteAccept = false;
          _ringTimer?.cancel();
          notifyListeners();
        }
      case CallLifecycle.declined:
        lifecycle = CallStateMachine.transition(
          lifecycle,
          CallEvent.remoteDeclined,
        );
        awaitingRemoteAccept = false;
        unawaited(_teardownMedia());
        notifyListeners();
      case CallLifecycle.cancelled:
      case CallLifecycle.ended:
        if (!CallStateMachine.isTerminal(lifecycle)) {
          lifecycle = CallStateMachine.transition(lifecycle, CallEvent.end);
          unawaited(_teardownMedia());
          notifyListeners();
        }
      case CallLifecycle.failed:
      case CallLifecycle.busy:
        lifecycle = remote;
        awaitingRemoteAccept = false;
        unawaited(_teardownMedia());
        notifyListeners();
      case CallLifecycle.calling:
      case CallLifecycle.ringing:
      case CallLifecycle.idle:
      case CallLifecycle.reconnecting:
        break;
    }
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
    mediaConnected = true;
    unawaited(_mediaSub?.cancel());
    _mediaSub = _provider.watch().listen((event) {
      remoteVideo = event.remoteVideoAvailable;
      cameraOn = event.localVideoEnabled;
      unstable = event.quality == VideoConnectionQuality.unstable;
      if (event.lifecycleHint == CallLifecycle.failed) {
        lifecycle = CallLifecycle.failed;
      } else if (event.lifecycleHint == CallLifecycle.reconnecting) {
        lifecycle = CallStateMachine.transition(
          lifecycle,
          CallEvent.connectionLost,
        );
      } else if (event.lifecycleHint == CallLifecycle.connected) {
        lifecycle = CallStateMachine.transition(
          lifecycle,
          lifecycle == CallLifecycle.reconnecting
              ? CallEvent.reconnected
              : CallEvent.connected,
        );
      } else if (event.lifecycleHint == CallLifecycle.ended &&
          mediaConnected) {
        lifecycle = CallStateMachine.transition(lifecycle, CallEvent.end);
      }
      notifyListeners();
    });
  }

  Future<void> _teardownMedia() async {
    mediaConnected = false;
    awaitingRemoteAccept = false;
    _ringTimer?.cancel();
    unawaited(_mediaSub?.cancel());
    _mediaSub = null;
    try {
      await _provider.disconnect();
    } on Object {
      // Provider teardown must not throw into UI.
    }
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
        unawaited(_teardownMedia());
        notifyListeners();
      }
    });
  }

  bool _closed = false;

  @override
  void notifyListeners() {
    if (_closed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _ringTimer?.cancel();
    unawaited(_incomingSub?.cancel());
    unawaited(_sessionSub?.cancel());
    unawaited(_mediaSub?.cancel());
    unawaited(_provider.disconnect());
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
