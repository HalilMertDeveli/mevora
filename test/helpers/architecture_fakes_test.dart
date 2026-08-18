import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/core/testing/fake_video_call_provider.dart';
import 'package:mevora/features/chat/domain/usecases/chat_usecases.dart';
import 'package:mevora/features/location/domain/entities/stored_user_location.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/swipe_action.dart';
import 'package:mevora/features/onboarding/domain/usecases/complete_onboarding.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/video/domain/usecases/video_call_use_cases.dart';

import 'fake_chat_repository.dart';
import 'fake_match_repository.dart';
import 'fake_profile_repository.dart';

void main() {
  test('FakeChatRepository send, paginate, read, and typing', () async {
    final chat = FakeChatRepository();
    addTearDown(chat.dispose);
    final sent = await chat.sendText(
      matchId: 'm1',
      receiverId: 'user-2',
      text: 'hello',
    );
    expect(sent.text, 'hello');

    final latest = await chat.watchLatest('m1').first;
    expect(latest, hasLength(1));

    await chat.markRead('m1', latest);
    expect(chat.messages['m1']!.first.isRead, isTrue);

    await chat.setTyping(matchId: 'm1', isTyping: true);
    final typing = await chat.watchTyping('m1').first;
    expect(typing.containsKey('user-1'), isTrue);

    final older = await chat.loadOlder(matchId: 'm1', before: sent);
    expect(older.messages, isEmpty);
    expect(older.hasMore, isFalse);
  });

  test('FakeMatchRepository records a like as a match', () async {
    final matches = FakeMatchRepository();
    addTearDown(matches.dispose);
    final result = await matches.recordSwipe(
      targetUserId: 'user-2',
      action: SwipeAction.like.wireValue,
    );
    expect(result.matched, isTrue);
    expect(result.match?.isParticipant('user-1'), isTrue);
    expect(await matches.getMatch(result.match!.id), isNotNull);
  });

  test('FakeLocationRepository never exposes another user GPS', () async {
    final location = FakeLocationRepository();
    final label = await location.distanceLabelTo('user-2');
    expect(label, isA<Success<DistanceLabel>>());
    expect((label as Success<DistanceLabel>).value.text, 'Nearby');
  });

  test('SendChatText rejects empty and unmatched conversations', () async {
    final chat = FakeChatRepository();
    addTearDown(chat.dispose);
    final useCase = SendChatText(chat);
    final match = Match(
      id: 'm1',
      userIds: const ['user-1', 'user-2'],
      createdAt: DateTime.utc(2026, 8, 18),
      isActive: true,
    );

    final empty = await useCase.call(
      match: match,
      senderId: 'user-1',
      receiverId: 'user-2',
      text: '   ',
      blocked: false,
    );
    expect(empty.isError, isTrue);

    final blocked = await useCase.call(
      match: match,
      senderId: 'user-1',
      receiverId: 'user-2',
      text: 'hi',
      blocked: true,
    );
    expect(blocked.isError, isTrue);

    final ok = await useCase.call(
      match: match,
      senderId: 'user-1',
      receiverId: 'user-2',
      text: 'hi',
      blocked: false,
    );
    expect(ok.isSuccess, isTrue);
  });

  test('video use cases honor the feature flag', () async {
    final provider = FakeVideoCallProvider();
    addTearDown(provider.dispose);
    const off = FeatureFlags();
    final startOff = StartVideoCall(provider, featureFlags: off);
    final denied = await startOff.call(
      matchId: 'm1',
      callerId: 'a',
      calleeId: 'b',
    );
    expect(denied.isError, isTrue);
    expect(denied.failureOrNull, isA<PermissionFailure>());

    const on = FeatureFlags(videoCallsEnabled: true);
    final startOn = StartVideoCall(provider, featureFlags: on);
    final allowed = await startOn.call(
      matchId: 'm1',
      callerId: 'a',
      calleeId: 'b',
    );
    expect(allowed.isSuccess, isTrue);
  });

  test('CompleteOnboarding requires age, name, and a photo', () async {
    final profiles = FakeProfileRepository();
    final useCase = CompleteOnboarding(profiles);
    final young = await useCase(
      const UserProfile(uid: 'u1', displayName: 'Ada', age: 16),
    );
    expect(young.isError, isTrue);

    final ready = await useCase(
      const UserProfile(
        uid: 'u1',
        displayName: 'Ada',
        age: 24,
        photos: [
          ProfilePhoto(id: 'p1', storagePath: 'users/u1/photos/p1.jpg'),
        ],
      ),
    );
    expect(ready.isSuccess, isTrue);
    expect(profiles.profiles['u1']?.profileCompleted, isTrue);
    expect(profiles.profiles['u1']?.onboardingCompleted, isTrue);
  });
}
