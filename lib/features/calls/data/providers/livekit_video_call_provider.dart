import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/video_call_surface.dart';

/// LiveKit is a managed WebRTC SFU. Media never goes through Firestore.
class LiveKitVideoCallProvider implements VideoCallProvider, VideoCallSurface {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  final _events = StreamController<VideoConnectionEvent>.broadcast();
  bool _mic = true;
  bool _camera = true;
  bool _speaker = true;
  bool _remote = false;

  @override
  bool get isMicrophoneEnabled => _mic;

  @override
  bool get isCameraEnabled => _camera;

  @override
  bool get isSpeakerEnabled => _speaker;

  @override
  bool get hasRemoteVideo => _remote;

  @override
  Future<void> connect(VideoConnectParams params) async {
    await disconnect();
    final room = Room();
    final listener = room.createListener();
    listener
      ..on<RoomConnectedEvent>((_) {
        _emit(CallLifecycle.connected);
      })
      ..on<RoomDisconnectedEvent>((_) {
        _remote = false;
        _emit(CallLifecycle.ended);
      })
      ..on<RoomReconnectingEvent>((_) {
        _emit(
          CallLifecycle.reconnecting,
          quality: VideoConnectionQuality.unstable,
        );
      })
      ..on<RoomReconnectedEvent>((_) {
        _emit(CallLifecycle.connected);
      })
      ..on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remote = true;
        }
        _emit(CallLifecycle.connected);
      })
      ..on<TrackUnsubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          _remote = _firstRemoteVideo() != null;
        }
        _emit(CallLifecycle.connected);
      })
      ..on<RoomAttemptReconnectEvent>((_) {
        _emit(
          CallLifecycle.reconnecting,
          quality: VideoConnectionQuality.unstable,
        );
      });
    _listener = listener;
    _room = room;
    try {
      await room.connect(params.url, params.token);
      await room.localParticipant?.setCameraEnabled(_camera);
      await room.localParticipant?.setMicrophoneEnabled(_mic);
      _emit(CallLifecycle.connected);
    } on Object {
      _emit(CallLifecycle.failed, quality: VideoConnectionQuality.lost);
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _remote = false;
    await _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } on Object {
        // Best-effort teardown after network or permission failures.
      }
      await room.dispose();
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    _mic = enabled;
    await _room?.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _camera = enabled;
    await _room?.localParticipant?.setCameraEnabled(enabled);
  }

  @override
  Future<void> switchCamera() async {
    final track = _room?.localParticipant?.videoTrackPublications
        .map((pub) => pub.track)
        .whereType<LocalVideoTrack>()
        .firstOrNull;
    if (track == null) {
      return;
    }
    final options = track.currentOptions;
    final current = options is CameraCaptureOptions
        ? options.cameraPosition
        : CameraPosition.front;
    await track.setCameraPosition(
      current == CameraPosition.front
          ? CameraPosition.back
          : CameraPosition.front,
    );
  }

  @override
  Future<void> setSpeakerEnabled(bool enabled) async {
    _speaker = enabled;
    await Hardware.instance.setSpeakerphoneOn(enabled);
  }

  @override
  Stream<VideoConnectionEvent> watch() => _events.stream;

  @override
  Widget? remoteVideo() {
    final track = _firstRemoteVideo();
    if (track == null) {
      return null;
    }
    return VideoTrackRenderer(track);
  }

  @override
  Widget? localVideo() {
    final track = _room?.localParticipant?.videoTrackPublications
        .map((pub) => pub.track)
        .whereType<VideoTrack>()
        .firstOrNull;
    if (track == null) {
      return null;
    }
    return VideoTrackRenderer(track, mirrorMode: VideoViewMirrorMode.mirror);
  }

  VideoTrack? _firstRemoteVideo() {
    final room = _room;
    if (room == null) {
      return null;
    }
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track is VideoTrack) {
          return track;
        }
      }
    }
    return null;
  }

  void _emit(
    CallLifecycle lifecycle, {
    VideoConnectionQuality quality = VideoConnectionQuality.good,
  }) {
    if (_events.isClosed) {
      return;
    }
    _events.add(
      VideoConnectionEvent(
        lifecycleHint: lifecycle,
        quality: quality,
        remoteVideoAvailable: _remote,
        localVideoEnabled: _camera,
      ),
    );
  }
}
