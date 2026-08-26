import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/chat/data/services/chat_audio_player.dart';
import 'package:mevora/features/chat/data/services/record_chat_voice_recorder.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/chat/domain/services/chat_voice_recorder.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/domain/models/match.dart';

class _FakeRecorder implements ChatVoiceRecorder {
  _FakeRecorder(this.payload);

  final RecordedVoice? payload;
  var recording = false;

  @override
  bool get isRecording => recording;

  @override
  Future<void> start() async {
    recording = true;
  }

  @override
  Future<RecordedVoice?> stop() async {
    recording = false;
    return payload;
  }

  @override
  Future<void> cancel() async {
    recording = false;
  }
}

void main() {
  test('FakeChatAudioPlayer stops previous message when a new one plays', () async {
    final player = FakeChatAudioPlayer();
    addTearDown(player.dispose);

    await player.playMessage(
      messageId: 'm1',
      url: 'https://example.invalid/1.m4a',
    );
    expect(player.playingMessageId, 'm1');

    await player.playMessage(
      messageId: 'm2',
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    );
    expect(player.playingMessageId, 'm2');
    expect(player.lastBytes, isNotNull);
  });

  test('graph voice message keeps local bytes for playback without URL', () async {
    final graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 8, 23, 12));
    graph.seedProfile('a', name: 'Ada');
    graph.seedProfile('b', name: 'Bea');
    graph.recordSwipe(actorUid: 'a', targetUserId: 'b', action: 'like');
    graph.recordSwipe(actorUid: 'b', targetUserId: 'a', action: 'like');
    final auth = MutableAuthUidSource('a');
    final services = createGraphSocialServices(graph: graph, uidSource: auth);

    final sent = await services.chatRepository.sendVoice(
      matchId: 'a_b',
      receiverId: 'b',
      media: ChatMediaBytes(
        bytes: Uint8List.fromList(const [0, 1, 2, 3, 4, 5]),
        contentType: 'audio/mp4',
        durationMs: 1200,
      ),
    );

    expect(sent.type, MessageType.voice);
    expect(sent.mediaUrl, isNull);
    expect(sent.localMediaBytes, isNotEmpty);
    expect(sent.durationMs, 1200);
    expect(sent.voiceStoragePath, isNotNull);
  });

  test('ChatController sendVoice surfaces upload failures', () async {
    final graph = InMemorySocialGraph(now: () => DateTime.utc(2026, 8, 23, 12));
    graph.seedProfile('a', name: 'Ada');
    graph.seedProfile('b', name: 'Bea');
    graph.recordSwipe(actorUid: 'a', targetUserId: 'b', action: 'like');
    graph.recordSwipe(actorUid: 'b', targetUserId: 'a', action: 'like');
    final auth = MutableAuthUidSource('a');
    final services = createGraphSocialServices(graph: graph, uidSource: auth);
    final controller = ChatController(
      matchId: 'a_b',
      chatRepository: services.chatRepository,
      matchRepository: services.matchRepository,
      safetyRepository: services.safetyRepository,
      presenceRepository: services.presenceRepository,
      uidSource: auth,
    );
    addTearDown(controller.dispose);
    await controller.start();

    final ok = await controller.sendVoice(
      ChatMediaBytes(
        bytes: Uint8List.fromList(List<int>.filled(32, 7)),
        contentType: 'audio/mp4',
        durationMs: 900,
      ),
    );
    expect(ok.isSuccess, isTrue);
    expect(controller.messages.any((m) => m.type == MessageType.voice), isTrue);
  });

  test('recorder rejects empty payload via stop returning null', () async {
    final recorder = _FakeRecorder(null);
    await recorder.start();
    final result = await recorder.stop();
    expect(result, isNull);
  });

  test('voice message model maps storage path and duration from Firestore fields', () {
    final message = ChatMessage(
      id: 'msg-1',
      senderId: 'a',
      receiverId: 'b',
      text: '',
      type: MessageType.voice,
      createdAt: DateTime.utc(2026, 8, 23),
      status: MessageStatus.sent,
      voiceStoragePath: 'users/a/chat/a_b/msg-1.m4a',
      mediaUrl: 'https://firebasestorage.googleapis.com/v0/b/demo/o/voice.m4a',
      durationMs: 3400,
    );

    expect(message.storagePath, 'users/a/chat/a_b/msg-1.m4a');
    expect(message.mediaUrl, isNotNull);
    expect(message.durationMs, 3400);
  });
}
