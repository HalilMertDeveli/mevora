import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/onboarding_messages.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/onboarding_error_l10n.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_photo_grid.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/pump_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

/// The profile document as the server keeps it, pushed to the client.
class _ServerBackedRepository extends FakeOnboardingRepository {
  final _server = StreamController<UserProfile?>.broadcast();

  void serverWrites(List<ProfilePhoto> photos) {
    _server.add(UserProfile(uid: 'user-a', displayName: 'Ada', photos: photos));
  }

  @override
  Stream<UserProfile?> watchDraft(String uid) => _server.stream;

  Future<void> close() => _server.close();
}

Future<({OnboardingController controller, _ServerBackedRepository repo})>
_onPhotoStep({int photos = 3, bool required = true}) async {
  final repo = _ServerBackedRepository();
  addTearDown(repo.close);
  final controller = OnboardingController(
    repository: repo,
    storage: FakeStorageRepository(),
    photoPicker: StubProfilePhotoPicker(
      next: PickedProfilePhoto(
        bytes: List<int>.filled(32, 7),
        contentType: 'image/jpeg',
      ),
    ),
  );
  addTearDown(controller.dispose);
  await controller.initialize(const AuthUser(id: 'user-a'));
  controller
    ..step = OnboardingStep.photos
    ..setFaceAnchorRequired(required);
  for (var i = 0; i < photos; i += 1) {
    await controller.pickPhoto(fromCamera: false);
    // Photo ids are the pick time in microseconds; a real member cannot pick
    // twice within one clock tick, a test loop can.
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
  expect({for (final d in controller.photoDrafts) d.id}, hasLength(photos));
  return (controller: controller, repo: repo);
}

/// What the server knows about each uploaded photo.
List<ProfilePhoto> _serverView(
  OnboardingController controller, {
  Set<int> approved = const {},
  Set<int> verified = const {},
  int? primary,
}) {
  final drafts = controller.photoDrafts;
  return [
    for (var i = 0; i < drafts.length; i += 1)
      ProfilePhoto(
        id: drafts[i].id,
        storagePath: 'users/user-a/profile/photos/${drafts[i].id}.jpg',
        downloadUrl: 'https://cdn.test/${drafts[i].id}.jpg',
        moderationStatus: approved.contains(i) || verified.contains(i)
            ? 'approved'
            : 'pending',
        isFaceAnchorVerified: verified.contains(i),
        order: i,
        isPrimary: primary == i,
      ),
  ];
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('the photo step', () {
    test(
      'three ordinary photos do not complete it when a Face Anchor is required',
      () async {
        final s = await _onPhotoStep();
        expect(s.controller.hasMinPhotos, isTrue);
        expect(s.controller.needsFaceAnchor, isTrue);
        expect(s.controller.canContinuePhotos, isFalse);

        final result = await s.controller.continueStep();
        expect(
          result.failureOrNull?.message,
          OnboardingMessages.faceAnchorRequired,
        );
        expect(s.controller.step, OnboardingStep.photos);
      },
    );

    test('completes once the server reports a verified photo', () async {
      final s = await _onPhotoStep();
      s.repo.serverWrites(
        _serverView(
          s.controller,
          approved: {0, 1, 2},
          verified: {1},
          primary: 1,
        ),
      );
      await _settle();

      expect(s.controller.hasFaceAnchor, isTrue);
      expect(s.controller.canContinuePhotos, isTrue);
      // The verified photo is now the primary one, first in the list.
      expect(s.controller.photoDrafts.first.remote!.isFaceAnchor, isTrue);
      expect(s.controller.profile!.photos.first.isPrimary, isTrue);
      expect(s.controller.profile!.photos.first.isFaceAnchorVerified, isTrue);
      expect((await s.controller.continueStep()).isSuccess, isTrue);
    });

    test(
      'a verified flag the client set itself is not what unlocks it',
      () async {
        // The only way a draft becomes verified is the server's profile stream;
        // the controller exposes no setter for it.
        final s = await _onPhotoStep();
        s.repo.serverWrites(_serverView(s.controller, approved: {0, 1, 2}));
        await _settle();
        expect(s.controller.canContinuePhotos, isFalse);
      },
    );

    test('learns from the server when moderation approves a photo', () async {
      final s = await _onPhotoStep();
      expect(
        s.controller.photoDrafts.first.remote!.moderationStatus,
        'pending',
      );
      s.repo.serverWrites(_serverView(s.controller, approved: {0}));
      await _settle();
      final first = s.controller.photoDrafts.first.remote!;
      expect(first.moderationStatus, 'approved');
      expect(first.storagePath, contains('/profile/photos/'));
      expect(s.controller.photoDrafts[1].remote!.moderationStatus, 'pending');
    });

    test('is not required when the server does not require it', () async {
      final s = await _onPhotoStep(required: false);
      expect(s.controller.needsFaceAnchor, isFalse);
      expect(s.controller.canContinuePhotos, isTrue);
    });

    test(
      'the server stream never adds or removes the member\'s photos',
      () async {
        final s = await _onPhotoStep();
        final ids = [for (final d in s.controller.photoDrafts) d.id];
        s.repo.serverWrites([
          ..._serverView(s.controller, approved: {0}),
          const ProfilePhoto(
            id: 'server-only',
            storagePath: 'x',
            moderationStatus: 'approved',
          ),
        ]);
        await _settle();
        expect([for (final d in s.controller.photoDrafts) d.id], ids);
        s.repo.serverWrites(const []);
        await _settle();
        expect(s.controller.photoDrafts, hasLength(3));
      },
    );
  });

  group('removing and reordering', () {
    test('the only verified photo cannot be removed', () async {
      final s = await _onPhotoStep(photos: 4);
      s.repo.serverWrites(
        _serverView(
          s.controller,
          approved: {0, 1, 2, 3},
          verified: {0},
          primary: 0,
        ),
      );
      await _settle();
      final anchorId = s.controller.photoDrafts.first.id;

      s.controller.removePhoto(anchorId);

      expect(s.controller.photoDrafts, hasLength(4));
      expect(s.controller.errorMessage, PhotoPolicy.lastFaceAnchor);
    });

    test(
      'with two verified photos, the first can go and the other takes over',
      () async {
        final s = await _onPhotoStep(photos: 4);
        s.repo.serverWrites(
          _serverView(
            s.controller,
            approved: {0, 1, 2, 3},
            verified: {0, 2},
            primary: 0,
          ),
        );
        await _settle();
        final first = s.controller.photoDrafts.first.id;

        s.controller.removePhoto(first);

        expect(s.controller.photoDrafts, hasLength(3));
        expect(s.controller.errorMessage, isNull);
        expect(s.controller.photoDrafts.first.remote!.isFaceAnchor, isTrue);
        expect(
          s.controller.profile!.photos.where((p) => p.isPrimary),
          hasLength(1),
        );
        expect(s.controller.profile!.photos.first.isFaceAnchorVerified, isTrue);
      },
    );

    test('an ordinary photo is removed freely', () async {
      final s = await _onPhotoStep(photos: 4);
      s.repo.serverWrites(
        _serverView(
          s.controller,
          approved: {0, 1, 2, 3},
          verified: {0},
          primary: 0,
        ),
      );
      await _settle();
      s.controller.removePhoto(s.controller.photoDrafts.last.id);
      expect(s.controller.photoDrafts, hasLength(3));
    });

    test('an ordinary photo cannot be dragged into first place', () async {
      final s = await _onPhotoStep();
      s.repo.serverWrites(
        _serverView(
          s.controller,
          approved: {0, 1, 2},
          verified: {0},
          primary: 0,
        ),
      );
      await _settle();
      final order = [for (final d in s.controller.photoDrafts) d.id];

      s.controller.reorderPhotos(2, 0);

      expect([for (final d in s.controller.photoDrafts) d.id], order);
      expect(s.controller.errorMessage, PhotoPolicy.primaryRequiresFaceAnchor);
    });

    test('secondary photos still reorder', () async {
      final s = await _onPhotoStep();
      s.repo.serverWrites(
        _serverView(
          s.controller,
          approved: {0, 1, 2},
          verified: {0},
          primary: 0,
        ),
      );
      await _settle();
      final order = [for (final d in s.controller.photoDrafts) d.id];

      s.controller.reorderPhotos(1, 3);

      expect(
        [for (final d in s.controller.photoDrafts) d.id],
        [order[0], order[2], order[1]],
      );
      expect(s.controller.errorMessage, isNull);
    });

    test('before any photo is verified, reordering is unrestricted', () async {
      final s = await _onPhotoStep();
      final order = [for (final d in s.controller.photoDrafts) d.id];
      s.controller.reorderPhotos(2, 0);
      expect(s.controller.photoDrafts.first.id, order[2]);
    });
  });

  group('messages', () {
    test('are in the member\'s language', () {
      expect(
        OnboardingErrorL10n.message(_tr, OnboardingMessages.faceAnchorRequired),
        _tr.faceAnchorRequiredNotice,
      );
      expect(
        OnboardingErrorL10n.message(_tr, PhotoPolicy.lastFaceAnchor),
        'Son doğrulanmış fotoğrafını silemezsin. Önce başka bir fotoğrafını doğrula.',
      );
      expect(
        OnboardingErrorL10n.message(_tr, PhotoPolicy.primaryRequiresFaceAnchor),
        'Bu fotoğrafı ana fotoğraf yapmak için önce doğrula.',
      );
      expect(
        OnboardingErrorL10n.message(
          _en,
          OnboardingMessages.primaryNotFaceAnchor,
        ),
        _en.faceAnchorPrimaryRequiresVerify,
      );
    });
  });

  group('photo grid', () {
    OnboardingPhotoDraft draft(
      String id, {
      String status = 'approved',
      bool verified = false,
    }) {
      return OnboardingPhotoDraft(
        id: id,
        remote: ProfilePhoto(
          id: id,
          storagePath: 'p/$id',
          moderationStatus: status,
          isFaceAnchorVerified: verified,
        ),
      );
    }

    Widget grid({
      required List<OnboardingPhotoDraft> drafts,
      FaceAnchorPhotoStatus Function(OnboardingPhotoDraft)? statusOf,
      ValueChanged<OnboardingPhotoDraft>? onVerify,
      bool needsFaceAnchor = false,
      Locale locale = const Locale('en'),
    }) {
      return wrapWithApp(
        SingleChildScrollView(
          child: OnboardingPhotoGrid(
            drafts: drafts,
            enabled: true,
            onAddCamera: () {},
            onAddGallery: () {},
            onRetry: (_) {},
            onRemove: (_) {},
            onReorder: (_, _) {},
            faceAnchorStatusOf: statusOf,
            onVerify: onVerify,
            needsFaceAnchor: needsFaceAnchor,
          ),
        ),
        locale: locale,
      );
    }

    FaceAnchorPhotoStatus byPhoto(OnboardingPhotoDraft d) =>
        FaceAnchorPhotoStatus.resolve(
          photo: d.remote!,
          state: FaceAnchorState.none,
          available: true,
        );

    testWidgets('explains that only one photo needs to show the member', (
      tester,
    ) async {
      await tester.pumpWidget(
        grid(drafts: const [], locale: const Locale('tr')),
      );
      expect(
        find.textContaining('En az bir fotoğrafta yüzün net görünmeli'),
        findsOneWidget,
      );
      expect(find.textContaining('hobilerini, seyahatlerini'), findsOneWidget);
    });

    testWidgets('offers verification on approved photos only', (tester) async {
      OnboardingPhotoDraft? tapped;
      await tester.pumpWidget(
        grid(
          drafts: [
            draft('a'),
            draft('b', status: 'pending'),
            draft('c'),
          ],
          statusOf: byPhoto,
          onVerify: (d) => tapped = d,
        ),
      );
      expect(find.text(_en.faceAnchorVerifyShort), findsNWidgets(2));
      expect(find.text(_en.faceAnchorPhotoInReview), findsOneWidget);

      await tester.tap(find.text(_en.faceAnchorVerifyShort).first);
      expect(tapped?.id, 'a');
    });

    testWidgets('marks the verified photo and stops offering it', (
      tester,
    ) async {
      await tester.pumpWidget(
        grid(
          drafts: [draft('a', verified: true), draft('b'), draft('c')],
          statusOf: byPhoto,
          onVerify: (_) {},
        ),
      );
      expect(find.text(_en.faceAnchorVerifiedShort), findsOneWidget);
      expect(find.text(_en.faceAnchorVerifyShort), findsNWidgets(2));
    });

    testWidgets('shows a running verification as pending', (tester) async {
      await tester.pumpWidget(
        grid(
          drafts: [draft('a'), draft('b'), draft('c')],
          statusOf: (d) =>
              d.id == 'a' ? FaceAnchorPhotoStatus.verifying : byPhoto(d),
          onVerify: (_) {},
        ),
      );
      expect(find.text(_en.faceAnchorPending), findsOneWidget);
      expect(find.text(_en.faceAnchorVerifyShort), findsNWidgets(2));
    });

    testWidgets('offers a retry after a failed verification', (tester) async {
      await tester.pumpWidget(
        grid(
          drafts: [draft('a'), draft('b'), draft('c')],
          statusOf: (d) =>
              d.id == 'a' ? FaceAnchorPhotoStatus.notVerified : byPhoto(d),
          onVerify: (_) {},
        ),
      );
      expect(find.text(_en.faceAnchorNotVerified), findsOneWidget);
      expect(find.text(_en.faceAnchorRetry), findsOneWidget);
    });

    testWidgets(
      'says what is missing when photos are enough but none is verified',
      (tester) async {
        await tester.pumpWidget(
          grid(
            drafts: [draft('a'), draft('b'), draft('c')],
            statusOf: byPhoto,
            onVerify: (_) {},
            needsFaceAnchor: true,
          ),
        );
        expect(find.text(_en.faceAnchorRequiredNotice), findsOneWidget);
      },
    );

    testWidgets('looks as before where verification is not wired in', (
      tester,
    ) async {
      await tester.pumpWidget(
        grid(drafts: [draft('a'), draft('b'), draft('c')]),
      );
      expect(find.text(_en.faceAnchorVerifyShort), findsNothing);
      expect(find.text(_en.photoUploaded), findsNWidgets(3));
    });
  });
}
