import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/onboarding/data/repositories/onboarding_repository_impl.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

import '../../helpers/fake_profile_repository.dart';

class _Backend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    return {'ok': true};
  }
}

final _born = DateTime(1995, 5, 5);

UserProfile _basicInfo({DateTime? birthDate}) {
  return UserProfile(
    uid: 'u1',
    displayName: 'Halil',
    birthDate: birthDate,
    gender: 'man',
    interestedIn: 'women',
    city: 'İstanbul',
  );
}

void main() {
  group('the public profile write', () {
    test('carries neither the date of birth nor an age', () {
      final map = FirebaseProfileDataSource.publicProfileMap(
        _basicInfo(birthDate: _born).copyWith(age: 31),
      );
      expect(map.containsKey('birthDate'), isFalse);
      expect(map.containsKey('age'), isFalse);
      expect(
        map.values.whereType<Timestamp>(),
        isEmpty,
        reason: 'no date of any kind is written by value',
      );
    });

    test('the date of birth is read only from the account document', () {
      expect(
        FirebaseProfileDataSource.birthDateFrom({
          'birthDate': Timestamp.fromDate(_born),
        }),
        _born,
      );
      expect(FirebaseProfileDataSource.birthDateFrom({'age': 31}), isNull);
      expect(
        FirebaseProfileDataSource.birthDateFrom({'birthDate': '1995-05-05'}),
        isNull,
      );
      expect(FirebaseProfileDataSource.birthDateFrom(null), isNull);
    });
  });

  group('onboarding keeps the date of birth on the private account', () {
    late FakeProfileRepository profiles;
    late OnboardingRepositoryImpl repository;

    setUp(() {
      profiles = FakeProfileRepository();
      repository = OnboardingRepositoryImpl(
        profiles: profiles,
        backend: _Backend(),
      );
    });

    test('the step that collects it saves it there', () async {
      final result = await repository.saveStep(
        profile: _basicInfo(birthDate: _born),
        step: OnboardingStep.basicInfo,
        lastName: 'Develi',
      );
      expect(result.isError, isFalse);
      expect(profiles.birthDates['u1'], _born);
    });

    test('later steps do not write it again', () async {
      await repository.saveStep(
        profile: _basicInfo(
          birthDate: _born,
        ).copyWith(interests: const ['music', 'travel', 'food']),
        step: OnboardingStep.interests,
        lastName: 'Develi',
      );
      expect(profiles.birthDateSaves, isEmpty);
    });

    test('a resumed draft gets it back from the account', () async {
      profiles.profiles['u1'] = _basicInfo();
      profiles.birthDates['u1'] = _born;

      final draft = await repository.loadDraft('u1');
      expect(draft?.birthDate, _born);
    });

    test('a draft from before the move keeps the date it still holds', () async {
      profiles.profiles['u1'] = _basicInfo(birthDate: _born);

      final draft = await repository.loadDraft('u1');
      expect(draft?.birthDate, _born);
    });

    test('the account wins when both hold a date', () async {
      profiles.profiles['u1'] = _basicInfo(birthDate: DateTime(1990, 1, 1));
      profiles.birthDates['u1'] = _born;

      final draft = await repository.loadDraft('u1');
      expect(draft?.birthDate, _born);
    });

    test('no profile yet means no draft', () async {
      profiles.birthDates['u1'] = _born;
      expect(await repository.loadDraft('u1'), isNull);
    });
  });
}
