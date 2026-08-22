import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:mevora/features/chat/domain/services/chat_voice_recorder.dart';

class RecordChatVoiceRecorder implements ChatVoiceRecorder {
  RecordChatVoiceRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _startedAt;
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw const ChatMicDenied();
    }
    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/mevora-voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    _startedAt = DateTime.now();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 48000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: _path!,
    );
    _recording = true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    _recording = false;
    final path = await _recorder.stop() ?? _path;
    final started = _startedAt;
    _path = null;
    _startedAt = null;
    if (path == null) {
      return null;
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final bytes = Uint8List.fromList(await file.readAsBytes());
    try {
      await file.delete();
    } on Object {
      // Temp cleanup is best-effort.
    }
    final duration = started == null
        ? 1000
        : DateTime.now().difference(started).inMilliseconds.clamp(400, 120000);
    return RecordedVoice(
      bytes: bytes,
      contentType: 'audio/mp4',
      durationMs: duration,
    );
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    try {
      await _recorder.stop();
    } on Object {
      // Ignore.
    }
    final path = _path;
    _path = null;
    _startedAt = null;
    if (path != null) {
      try {
        await File(path).delete();
      } on Object {
        // Ignore.
      }
    }
  }
}

class ChatMicDenied implements Exception {
  const ChatMicDenied();
}
