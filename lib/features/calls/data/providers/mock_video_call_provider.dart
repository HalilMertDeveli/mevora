import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/video_call_surface.dart';

class MockVideoCallProvider implements VideoCallProvider, VideoCallSurface {
  bool _mic = true;
  bool _camera = true;
  bool _speaker = true;
  bool _remote = true;
  final _events = StreamController<VideoConnectionEvent>.broadcast();

  @override
  bool get isMicrophoneEnabled => _mic;

  @override
  bool get isCameraEnabled => _camera;

  @override
  bool get isSpeakerEnabled => _speaker;

  @override
  bool get hasRemoteVideo => _remote && _camera;

  @override
  Future<void> connect(VideoConnectParams params) async {
    _events.add(
      const VideoConnectionEvent(
        lifecycleHint: CallLifecycle.connected,
        quality: VideoConnectionQuality.good,
        remoteVideoAvailable: true,
        localVideoEnabled: true,
      ),
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _mic = enabled;
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _camera = enabled;
  }

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    _speaker = enabled;
  }

  @override
  Stream<VideoConnectionEvent> watch() => _events.stream;

  @override
  Widget? remoteVideo() => _remote ? const ColoredBox(color: Color(0xFF111111)) : null;

  @override
  Widget? localVideo() => _camera ? const ColoredBox(color: Color(0xFF333333)) : null;

  void emitUnstable() {
    _events.add(
      VideoConnectionEvent(
        lifecycleHint: CallLifecycle.reconnecting,
        quality: VideoConnectionQuality.unstable,
        remoteVideoAvailable: _remote,
        localVideoEnabled: _camera,
      ),
    );
  }
}
