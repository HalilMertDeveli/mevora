import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/profile/data/services/callable_profile_photo_remover.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/features/settings/presentation/settings_strings.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/fake_profile_photo_remover.dart';
import '../../helpers/fake_settings_hub_repository.dart';

ProfilePhoto _photo(String id, int order, {bool verified = false}) {
  return ProfilePhoto(
    id: id,
    storagePath: 'users/u1/profile/photos/$id.jpg',
    order: order,
    isPrimary: order == 0,
    moderationStatus: 'approved',
    isFaceAnchorVerified: verified,
  );
}

UserProfile _profile(List<ProfilePhoto> photos) =>
    UserProfile(uid: 'u1', displayName: 'Ada', photos: photos);

final _four = [
  _photo('a', 0, verified: true),
  _photo('b', 1),
  _photo('c', 2),
  _photo('d', 3),
];

/// Counts the client-side storage deletes the old path performed.
class _RecordingStorage extends FakeStorageRepository {
  final List<String> deleted = <String>[];

  @override
  Future<Result<void>> deleteProfileImage({
    required String ownerUid,
    required String imageId,
  }) async {
    deleted.add(imageId);
    return const Success(null);
  }
}

class _SavingHub extends FakeSettingsHubRepository {
  int saves = 0;

  @override
  Future<void> saveProfile(UserProfile next) async {
    saves += 1;
    await super.saveProfile(next);
  }
}

({
  ProfilePhotoManager manager,
  FakeProfilePhotoRemover remover,
  _SavingHub hub,
  _RecordingStorage storage,
})
_manager({Failure? failure}) {
  final hub = _SavingHub();
  final storage = _RecordingStorage();
  final remover = FakeProfilePhotoRemover(failure: failure);
  return (
    manager: ProfilePhotoManager(
      settingsHub: hub,
      storage: storage,
      photoRemover: remover,
    ),
    remover: remover,
    hub: hub,
    storage: storage,
  );
}

class _Backend implements BackendCallable {
  _Backend({this.error});

  final Object? error;
  final List<(String, Map<String, dynamic>?)> calls = [];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add((name, data));
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{'removed': true, 'cleanup': 'complete'};
  }
}

FirebaseFunctionsException _functionsError(String code, [String? message]) =>
    FirebaseFunctionsException(code: code, message: message ?? code);

void main() {
  group('deleting a photo goes through the server', () {
    test(
      'the server is asked to delete it; the client writes nothing',
      () async {
        final s = _manager();

        final result = await s.manager.deletePhoto(
          profile: _profile(_four),
          photoId: 'c',
        );

        expect(s.remover.removed, ['c']);
        expect(s.hub.saves, 0, reason: 'the server rewrites the photo list');
        expect(s.storage.deleted, isEmpty);
        expect(
          [for (final p in result.valueOrNull!.photos) p.id],
          ['a', 'b', 'd'],
        );
        expect(
          [for (final p in result.valueOrNull!.photos) p.order],
          [0, 1, 2],
        );
      },
    );

    test('a photo the policy protects never reaches the server', () async {
      final s = _manager();

      final tooFew = await s.manager.deletePhoto(
        profile: _profile(_four.take(3).toList()),
        photoId: 'b',
      );
      final lastAnchor = await s.manager.deletePhoto(
        profile: _profile(_four),
        photoId: 'a',
      );

      expect(tooFew.failureOrNull?.message, PhotoPolicy.minRequired);
      expect(lastAnchor.failureOrNull?.message, PhotoPolicy.lastFaceAnchor);
      expect(s.remover.removed, isEmpty);
    });

    test("the server's refusal is shown, and nothing is written", () async {
      final s = _manager(
        failure: const ValidationFailure(PhotoPolicy.stillProcessing),
      );

      final result = await s.manager.deletePhoto(
        profile: _profile(_four),
        photoId: 'c',
      );

      expect(result.failureOrNull?.message, PhotoPolicy.stillProcessing);
      expect(s.hub.saves, 0);
      expect(s.storage.deleted, isEmpty);
    });

    test('a failed call leaves the photo where it is', () async {
      final s = _manager(failure: const NetworkFailure('offline'));

      final result = await s.manager.deletePhoto(
        profile: _profile(_four),
        photoId: 'c',
      );

      expect(result.isError, isTrue);
      expect(s.hub.saves, 0);
      expect(s.storage.deleted, isEmpty);
    });

    test(
      'a backend without the callable falls back to the list rewrite',
      () async {
        final s = _manager(failure: const NotFoundFailure('not-found'));

        final result = await s.manager.deletePhoto(
          profile: _profile(_four),
          photoId: 'c',
        );

        expect(result.isSuccess, isTrue);
        expect(s.hub.saves, 1);
        expect([for (final p in s.hub.profile!.photos) p.id], ['a', 'b', 'd']);
        expect(s.storage.deleted, ['c']);
      },
    );
  });

  group('CallableProfilePhotoRemover', () {
    test(
      'calls deleteProfilePhoto with the photo id and nothing else',
      () async {
        final backend = _Backend();

        final result = await CallableProfilePhotoRemover(
          backend: backend,
        ).remove('c');

        expect(result.isSuccess, isTrue);
        expect(backend.calls, hasLength(1));
        expect(backend.calls.single.$1, 'deleteProfilePhoto');
        expect(backend.calls.single.$2, {'photoId': 'c'});
      },
    );

    test(
      'a refusal carries the server reason as a validation failure',
      () async {
        for (final reason in [
          PhotoPolicy.minRequired,
          PhotoPolicy.lastFaceAnchor,
          PhotoPolicy.stillProcessing,
        ]) {
          final result = await CallableProfilePhotoRemover(
            backend: _Backend(
              error: _functionsError('failed-precondition', reason),
            ),
          ).remove('c');

          expect(result.failureOrNull, isA<ValidationFailure>());
          expect(result.failureOrNull?.message, reason);
        }
      },
    );

    test('a missing callable is told apart from every other failure', () async {
      Future<Failure?> failureFor(Object error) async {
        final result = await CallableProfilePhotoRemover(
          backend: _Backend(error: error),
        ).remove('c');
        return result.failureOrNull;
      }

      expect(
        await failureFor(_functionsError('not-found')),
        isA<NotFoundFailure>(),
      );
      expect(
        await failureFor(_functionsError('unimplemented')),
        isA<NotFoundFailure>(),
      );
      expect(
        await failureFor(_functionsError('internal')),
        isA<NetworkFailure>(),
      );
      expect(
        await failureFor(_functionsError('unavailable')),
        isA<NetworkFailure>(),
      );
      expect(await failureFor(StateError('boom')), isA<NetworkFailure>());
    });
  });

  test(
    'the still-processing refusal has its own message in both languages',
    () {
      final en = lookupAppLocalizations(const Locale('en'));
      final tr = lookupAppLocalizations(const Locale('tr'));

      expect(
        SettingsStrings.validation(en, PhotoPolicy.stillProcessing),
        en.settingsPhotoStillProcessing,
      );
      expect(
        SettingsStrings.validation(tr, PhotoPolicy.stillProcessing),
        tr.settingsPhotoStillProcessing,
      );
      expect(en.settingsPhotoStillProcessing, isNot(en.somethingWentWrong));
      expect(
        tr.settingsPhotoStillProcessing,
        isNot(en.settingsPhotoStillProcessing),
      );
    },
  );
}
