import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/face_anchor/data/repositories/face_anchor_repository_impl.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/features/face_anchor/presentation/controllers/face_anchor_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';

import '../../helpers/fake_face_anchor.dart';

const _approved = ProfilePhoto(
  id: 'p1',
  storagePath: 'users/u/profile/photos/p1.jpg',
  moderationStatus: 'approved',
);

({
  FaceAnchorController controller,
  FakeFaceAnchorRepository repo,
  FakeLiveSelfieCapture capture,
})
_setup() {
  final repo = FakeFaceAnchorRepository();
  final capture = FakeLiveSelfieCapture();
  final controller = FaceAnchorController(repository: repo, capture: capture);
  addTearDown(controller.dispose);
  addTearDown(repo.dispose);
  return (controller: controller, repo: repo, capture: capture);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('a verification run', () {
    test(
      'opens an attempt, captures, uploads, then asks for the verdict',
      () async {
        final s = _setup();
        s.controller.bind('uid');
        await _settle();

        final outcome = await s.controller.verify(
          photoId: 'p1',
          consentGiven: true,
        );

        expect(outcome, FaceAnchorRunOutcome.verified);
        expect(s.repo.calls, ['start', 'upload', 'submit']);
        expect(s.repo.started.single.photoId, 'p1');
        expect(s.repo.uploads.single.path, 'face-anchor/pending/uid/attempt-1');
        expect(s.repo.submitted.single, 'attempt-1');
        expect(s.controller.state.status, FaceAnchorStatus.verified);
        expect(s.controller.isBusy, isFalse);
        expect(s.controller.errorKey, isNull);
      },
    );

    test('sends the consent version the server announced', () async {
      final s = _setup();
      s.repo.requirements = const FaceAnchorRequirements(
        required: true,
        available: true,
        consentVersion: 7,
      );
      s.controller.bind('uid');
      await _settle();
      await s.controller.verify(photoId: 'p1', consentGiven: true);
      expect(s.repo.started.single.consentVersion, 7);
    });

    test(
      'without consent nothing is opened and the camera never shows',
      () async {
        final s = _setup();
        s.controller.bind('uid');
        await _settle();

        final outcome = await s.controller.verify(
          photoId: 'p1',
          consentGiven: false,
        );

        expect(outcome, FaceAnchorRunOutcome.failed);
        expect(s.controller.errorKey, FaceAnchorMessages.consentRequired);
        expect(s.repo.calls, isEmpty);
        expect(s.capture.captures, 0);
      },
    );

    test(
      'the verdict is the server\'s: a decline is reported as a decline',
      () async {
        final s = _setup();
        s.repo.nextResult = const FaceAnchorState(
          status: FaceAnchorStatus.failed,
          reason: FaceAnchorReason.faceMismatch,
        );
        s.controller.bind('uid');
        await _settle();

        final outcome = await s.controller.verify(
          photoId: 'p1',
          consentGiven: true,
        );

        expect(outcome, FaceAnchorRunOutcome.notVerified);
        expect(s.controller.state.reason, FaceAnchorReason.faceMismatch);
        expect(
          s.controller.statusFor(_approved),
          FaceAnchorPhotoStatus.notVerified,
        );
      },
    );

    test(
      'closing the camera cancels quietly: nothing uploaded, nothing submitted',
      () async {
        final s = _setup();
        s.capture.next = null;
        s.controller.bind('uid');
        await _settle();

        final outcome = await s.controller.verify(
          photoId: 'p1',
          consentGiven: true,
        );

        expect(outcome, FaceAnchorRunOutcome.cancelled);
        expect(s.repo.calls, ['start']);
        expect(s.controller.errorKey, isNull);
        expect(s.controller.isBusy, isFalse);
      },
    );

    test('a refusal to open the attempt stops before the camera', () async {
      final s = _setup();
      s.repo.startFailure = const ValidationFailure(
        FaceAnchorMessages.attemptLimit,
      );
      s.controller.bind('uid');
      await _settle();

      final outcome = await s.controller.verify(
        photoId: 'p1',
        consentGiven: true,
      );

      expect(outcome, FaceAnchorRunOutcome.failed);
      expect(s.controller.errorKey, FaceAnchorMessages.attemptLimit);
      expect(s.capture.captures, 0);
    });

    test('a failed upload is reported and never submitted', () async {
      final s = _setup();
      s.repo.uploadFailure = const NetworkFailure(
        FaceAnchorMessages.uploadFailed,
      );
      s.controller.bind('uid');
      await _settle();

      final outcome = await s.controller.verify(
        photoId: 'p1',
        consentGiven: true,
      );

      expect(outcome, FaceAnchorRunOutcome.failed);
      expect(s.controller.errorKey, FaceAnchorMessages.uploadFailed);
      expect(s.repo.calls, ['start', 'upload']);
    });

    test('a camera failure is reported', () async {
      final s = _setup();
      s.capture.failure = const ValidationFailure(
        FaceAnchorMessages.cameraDenied,
      );
      s.controller.bind('uid');
      await _settle();

      await s.controller.verify(photoId: 'p1', consentGiven: true);

      expect(s.controller.errorKey, FaceAnchorMessages.cameraDenied);
      expect(s.repo.calls, ['start']);
    });

    test('a second tap while one is running starts nothing', () async {
      final s = _setup();
      s.repo.submitGate = Completer<void>();
      s.controller.bind('uid');
      await _settle();

      final first = s.controller.verify(photoId: 'p1', consentGiven: true);
      await _settle();
      expect(s.controller.phase, FaceAnchorPhase.verifying);
      expect(
        s.controller.statusFor(_approved),
        FaceAnchorPhotoStatus.verifying,
      );

      final second = await s.controller.verify(
        photoId: 'p1',
        consentGiven: true,
      );
      expect(second, FaceAnchorRunOutcome.pending);
      expect(s.repo.calls.where((c) => c == 'start'), hasLength(1));

      s.repo.submitGate!.complete();
      expect(await first, FaceAnchorRunOutcome.verified);
    });

    test('a lost answer leaves a pending run, not a guess', () async {
      final s = _setup();
      s.repo.submitFailure = const NetworkFailure(FaceAnchorMessages.network);
      s.controller.bind('uid');
      await _settle();

      final outcome = await s.controller.verify(
        photoId: 'p1',
        consentGiven: true,
      );

      expect(outcome, FaceAnchorRunOutcome.failed);
      expect(s.controller.state.status, isNot(FaceAnchorStatus.verified));
      // The server later reports what actually happened.
      s.repo.emit(
        const FaceAnchorState(
          status: FaceAnchorStatus.verified,
          photoId: 'p1',
          attemptId: 'attempt-1',
        ),
      );
      await _settle();
      expect(s.controller.state.status, FaceAnchorStatus.verified);
    });
  });

  group('state comes from the server', () {
    test(
      'after a restart the screen is rebuilt from the stored state',
      () async {
        final s = _setup();
        // The app was closed mid-verification; the server finished meanwhile.
        s.repo.emit(
          const FaceAnchorState(
            status: FaceAnchorStatus.failed,
            reason: FaceAnchorReason.livenessFailed,
            photoId: 'p1',
            attemptId: 'attempt-9',
          ),
        );
        s.controller.bind('uid');
        await _settle();

        expect(s.controller.phase, FaceAnchorPhase.idle);
        expect(s.controller.state.reason, FaceAnchorReason.livenessFailed);
        expect(
          s.controller.statusFor(_approved),
          FaceAnchorPhotoStatus.notVerified,
        );
        expect(s.repo.calls, isEmpty);
      },
    );

    test(
      'a processing state shows as verifying without any local run',
      () async {
        final s = _setup();
        s.repo.emit(
          const FaceAnchorState(
            status: FaceAnchorStatus.processing,
            photoId: 'p1',
            attemptId: 'attempt-9',
          ),
        );
        s.controller.bind('uid');
        await _settle();

        expect(
          s.controller.statusFor(_approved),
          FaceAnchorPhotoStatus.verifying,
        );
        expect(s.controller.isBusy, isFalse);
      },
    );

    test(
      'a processing state that never resolves is asked about once',
      () async {
        final repo = FakeFaceAnchorRepository();
        addTearDown(repo.dispose);
        final controller = FaceAnchorController(
          repository: repo,
          capture: FakeLiveSelfieCapture(),
          recoveryDelay: const Duration(milliseconds: 60),
        );
        addTearDown(controller.dispose);
        repo.emit(
          const FaceAnchorState(
            status: FaceAnchorStatus.processing,
            photoId: 'p1',
            attemptId: 'attempt-9',
          ),
        );
        controller.bind('uid');
        await _settle();

        expect(repo.submitted, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(repo.submitted, ['attempt-9']);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(repo.submitted, hasLength(1));
      },
    );

    test('no recovery call when the server resolves in time', () async {
      final repo = FakeFaceAnchorRepository();
      addTearDown(repo.dispose);
      final controller = FaceAnchorController(
        repository: repo,
        capture: FakeLiveSelfieCapture(),
        recoveryDelay: const Duration(milliseconds: 80),
      );
      addTearDown(controller.dispose);
      repo.emit(
        const FaceAnchorState(
          status: FaceAnchorStatus.processing,
          photoId: 'p1',
          attemptId: 'attempt-9',
        ),
      );
      controller.bind('uid');
      await _settle();
      repo.emit(
        const FaceAnchorState(
          status: FaceAnchorStatus.verified,
          photoId: 'p1',
          attemptId: 'attempt-9',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(repo.submitted, isEmpty);
    });

    test('an unrecognised status is nothing in progress, never verified', () {
      for (final wire in ['Verified', 'approved', 'success', true, 1, null]) {
        expect(
          FaceAnchorStatus.fromWire(wire),
          FaceAnchorStatus.none,
          reason: '$wire',
        );
      }
      expect(FaceAnchorState.fromMap(null).status, FaceAnchorStatus.none);
      expect(
        FaceAnchorState.fromMap({'status': 'verified'}).status,
        FaceAnchorStatus.verified,
      );
    });
  });

  group('how a photo presents itself', () {
    FaceAnchorPhotoStatus resolve(
      ProfilePhoto photo, {
      FaceAnchorState state = FaceAnchorState.none,
      bool available = true,
    }) {
      return FaceAnchorPhotoStatus.resolve(
        photo: photo,
        state: state,
        available: available,
      );
    }

    test('approved and unverified: verification is offered', () {
      expect(resolve(_approved), FaceAnchorPhotoStatus.canVerify);
    });

    test('nothing is offered while verification is unavailable', () {
      expect(resolve(_approved, available: false), FaceAnchorPhotoStatus.none);
    });

    test('a photo still in moderation is in review', () {
      for (final status in ['pending', 'processing', 'manual_review']) {
        expect(
          resolve(_approved.copyWith(moderationStatus: status)),
          FaceAnchorPhotoStatus.inReview,
          reason: status,
        );
      }
    });

    test('a rejected photo is offered nothing', () {
      expect(
        resolve(_approved.copyWith(moderationStatus: 'rejected')),
        FaceAnchorPhotoStatus.none,
      );
    });

    test('verified needs both the flag and approval', () {
      expect(
        resolve(_approved.copyWith(isFaceAnchorVerified: true)),
        FaceAnchorPhotoStatus.verified,
      );
      expect(
        resolve(
          _approved.copyWith(
            isFaceAnchorVerified: true,
            moderationStatus: 'manual_review',
          ),
        ),
        FaceAnchorPhotoStatus.inReview,
      );
    });

    test('a failed attempt marks only the photo it was about', () {
      const state = FaceAnchorState(
        status: FaceAnchorStatus.failed,
        reason: FaceAnchorReason.faceMismatch,
        photoId: 'other',
      );
      expect(resolve(_approved, state: state), FaceAnchorPhotoStatus.canVerify);
    });
  });

  group('server refusals', () {
    String key(Object error) =>
        FaceAnchorRepositoryImpl.mapCallableError(error).message;

    test('map onto known identifiers', () {
      expect(
        key(Exception('[failed-precondition] face-anchor-unavailable')),
        FaceAnchorMessages.unavailable,
      );
      expect(
        key(Exception('photo-not-approved')),
        FaceAnchorMessages.photoNotApproved,
      );
      expect(
        key(Exception('already-verified')),
        FaceAnchorMessages.alreadyVerified,
      );
      expect(
        key(Exception('verification-in-progress')),
        FaceAnchorMessages.inProgress,
      );
      expect(
        key(Exception('[resource-exhausted] face-anchor-cooldown')),
        FaceAnchorMessages.cooldown,
      );
      expect(
        key(Exception('face-anchor-attempt-limit')),
        FaceAnchorMessages.attemptLimit,
      );
      expect(
        key(Exception('consent-required')),
        FaceAnchorMessages.consentRequired,
      );
      expect(key(Exception('selfie-missing')), FaceAnchorMessages.uploadFailed);
      expect(
        key(Exception('attempt-not-found')),
        FaceAnchorMessages.attemptExpired,
      );
      expect(key(TimeoutException('slow')), FaceAnchorMessages.network);
    });

    test('never surface raw error text', () {
      final failure = FaceAnchorRepositoryImpl.mapCallableError(
        Exception(
          'INTERNAL: provider said score=0.31 at https://internal.example/x',
        ),
      );
      expect(failure.message, FaceAnchorMessages.generic);
    });
  });
}
