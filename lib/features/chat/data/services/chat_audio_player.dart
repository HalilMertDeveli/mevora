import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Playback port for voice bubbles. UI never imports audioplayers.
abstract class ChatAudioPlayer {
  /// Plays a voice bubble. [messageId] must be stable (Firestore message id).
  /// Either [url] (Firebase) or [bytes] (in-memory demo) must be provided.
  Future<void> playMessage({
    required String messageId,
    String? url,
    Uint8List? bytes,
  });

  Future<void> pause();

  Future<void> stop();

  /// Emits the message id currently playing, or null when idle.
  Stream<String?> watchActiveMessageId();

  Stream<Duration> watchPosition();

  Stream<PlayerComplete> watchComplete();

  Future<void> dispose();
}

class PlayerComplete {
  const PlayerComplete({this.messageId});

  final String? messageId;
}

class AudioplayersChatAudioPlayer implements ChatAudioPlayer {
  AudioplayersChatAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer(),
      _activeMessageId = StreamController<String?>.broadcast(
        onListen: () {},
      );

  final AudioPlayer _player;
  final StreamController<String?> _activeMessageId;
  String? _currentMessageId;
  StreamSubscription<void>? _completeSub;

  @override
  Stream<String?> watchActiveMessageId() => _activeMessageId.stream;

  @override
  Future<void> playMessage({
    required String messageId,
    String? url,
    Uint8List? bytes,
  }) async {
    if (url == null && (bytes == null || bytes.isEmpty)) {
      return;
    }
    if (_currentMessageId != null && _currentMessageId != messageId) {
      await _player.stop();
    }
    _currentMessageId = messageId;
    _activeMessageId.add(messageId);
    await _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) {
      _currentMessageId = null;
      _activeMessageId.add(null);
    });
    if (bytes != null && bytes.isNotEmpty) {
      await _player.play(BytesSource(bytes));
      return;
    }
    await _player.play(UrlSource(url!));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _currentMessageId = null;
    _activeMessageId.add(null);
    await _player.stop();
  }

  @override
  Stream<Duration> watchPosition() => _player.onPositionChanged;

  @override
  Stream<PlayerComplete> watchComplete() {
    return _player.onPlayerComplete.map(
      (_) => PlayerComplete(messageId: _currentMessageId),
    );
  }

  @override
  Future<void> dispose() async {
    await _completeSub?.cancel();
    await _activeMessageId.close();
    await _player.dispose();
  }
}

class FakeChatAudioPlayer implements ChatAudioPlayer {
  FakeChatAudioPlayer() : _active = StreamController<String?>.broadcast();

  String? playingMessageId;
  String? lastUrl;
  Uint8List? lastBytes;
  final StreamController<String?> _active;

  @override
  Stream<String?> watchActiveMessageId() => _active.stream;

  @override
  Future<void> playMessage({
    required String messageId,
    String? url,
    Uint8List? bytes,
  }) async {
    if (playingMessageId != null && playingMessageId != messageId) {
      _active.add(null);
    }
    playingMessageId = messageId;
    lastUrl = url;
    lastBytes = bytes;
    _active.add(messageId);
  }

  @override
  Future<void> pause() async {
    _active.add(null);
  }

  @override
  Future<void> stop() async {
    playingMessageId = null;
    _active.add(null);
  }

  @override
  Stream<Duration> watchPosition() => const Stream.empty();

  @override
  Stream<PlayerComplete> watchComplete() => const Stream.empty();

  @override
  Future<void> dispose() async {
    await _active.close();
  }
}
