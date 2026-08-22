import 'dart:typed_data';

class RecordedVoice {
  const RecordedVoice({
    required this.bytes,
    required this.contentType,
    required this.durationMs,
  });

  final Uint8List bytes;
  final String contentType;
  final int durationMs;
}

/// Hold-to-record port. UI never imports `record`.
abstract class ChatVoiceRecorder {
  Future<void> start();

  Future<RecordedVoice?> stop();

  Future<void> cancel();

  bool get isRecording;
}

class UnsupportedChatVoiceRecorder implements ChatVoiceRecorder {
  @override
  bool get isRecording => false;

  @override
  Future<void> start() async {}

  @override
  Future<RecordedVoice?> stop() async => null;

  @override
  Future<void> cancel() async {}
}
