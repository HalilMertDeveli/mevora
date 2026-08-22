import 'package:audioplayers/audioplayers.dart';

/// Playback port for voice bubbles. UI never imports audioplayers.
abstract class ChatAudioPlayer {
  Future<void> play(String url);

  Future<void> pause();

  Future<void> stop();

  Stream<Duration> watchPosition();

  Stream<PlayerComplete> watchComplete();

  Future<void> dispose();
}

class PlayerComplete {
  const PlayerComplete();
}

class AudioplayersChatAudioPlayer implements ChatAudioPlayer {
  AudioplayersChatAudioPlayer({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> play(String url) {
    return _player.play(UrlSource(url));
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Stream<Duration> watchPosition() => _player.onPositionChanged;

  @override
  Stream<PlayerComplete> watchComplete() {
    return _player.onPlayerComplete.map((_) => const PlayerComplete());
  }

  @override
  Future<void> dispose() => _player.dispose();
}

class FakeChatAudioPlayer implements ChatAudioPlayer {
  bool playing = false;

  @override
  Future<void> play(String url) async {
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Stream<Duration> watchPosition() => const Stream.empty();

  @override
  Stream<PlayerComplete> watchComplete() => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
