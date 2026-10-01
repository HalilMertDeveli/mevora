import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/domain/face_anchor_messages.dart';
import 'package:mevora/features/face_anchor/presentation/controllers/face_anchor_controller.dart';
import 'package:mevora/features/face_anchor/presentation/face_anchor_l10n.dart';
import 'package:mevora/features/face_anchor/presentation/pages/face_anchor_verify_page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/presentation/widgets/photo_grid_editor.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_face_anchor.dart';
import '../../helpers/pump_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

const _photo = ProfilePhoto(
  id: 'p1',
  storagePath: 'users/u/profile/photos/p1.jpg',
  moderationStatus: 'approved',
);

class _Harness {
  _Harness() {
    controller = FaceAnchorController(repository: repo, capture: capture);
  }

  final repo = FakeFaceAnchorRepository();
  final capture = FakeLiveSelfieCapture();
  late final FaceAnchorController controller;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    addTearDown(controller.dispose);
    addTearDown(repo.dispose);
    // Tall enough that the whole page is laid out: the list builds lazily and
    // the buttons sit below the photo and the explanation.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.bind('uid');
    await tester.pumpWidget(
      wrapWithApp(
        FaceAnchorVerifyPage(photo: _photo, controller: controller),
        locale: locale,
        scaffold: false,
      ),
    );
    await tester.pump();
  }

  Future<void> consentAndStart(
    WidgetTester tester,
    AppLocalizations l10n,
  ) async {
    await tester.tap(find.byKey(const ValueKey('faceAnchorConsent')));
    await tester.pump();
    await tester.tap(find.text(l10n.faceAnchorTakeSelfie));
    await tester.pump();
  }
}

void main() {
  testWidgets('explains why a selfie is asked for and what happens to it', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester, locale: const Locale('tr'));

    expect(
      find.text(
        'Fotoğrafının gerçekten sana ait olduğundan emin olmak için kısa bir selfie kontrolü yapıyoruz.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('kontrol bitince silinir'), findsOneWidget);
    expect(find.text(_tr.faceAnchorConsent), findsOneWidget);
    // No provider name, no technical vocabulary.
    for (final jargon in ['Didit', 'liveness', 'biometri', 'skor', 'API']) {
      expect(find.textContaining(jargon), findsNothing, reason: jargon);
    }
  });

  testWidgets('the camera cannot be opened before the member agrees', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.tap(find.text(_en.faceAnchorTakeSelfie));
    await tester.pump();
    expect(h.capture.captures, 0);
    expect(h.repo.calls, isEmpty);

    await h.consentAndStart(tester, _en);
    await tester.pumpAndSettle();
    expect(h.capture.captures, 1);
  });

  testWidgets('shows progress while the server is verifying', (tester) async {
    final h = _Harness();
    h.repo.submitGate = Completer<void>();
    await h.pump(tester);

    await h.consentAndStart(tester, _en);
    await tester.pump();
    await tester.pump();

    expect(find.text(_en.faceAnchorVerifying), findsOneWidget);
    expect(find.text(_en.faceAnchorTakeSelfie), findsNothing);

    h.repo.submitGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('success: says so and returns to the photo list', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    await h.consentAndStart(tester, _en);
    await tester.pumpAndSettle();

    expect(find.text(_en.faceAnchorVerified), findsOneWidget);
    expect(find.text(_en.faceAnchorSuccessBody), findsOneWidget);
    expect(find.text(_en.faceAnchorDone), findsOneWidget);
    expect(find.text(_en.faceAnchorTakeSelfie), findsNothing);
  });

  testWidgets('face mismatch: a plain explanation, a retry and another photo', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.nextResult = const FaceAnchorState(
      status: FaceAnchorStatus.failed,
      reason: FaceAnchorReason.faceMismatch,
    );
    await h.pump(tester, locale: const Locale('tr'));

    await h.consentAndStart(tester, _tr);
    await tester.pumpAndSettle();

    expect(
      find.text('Bu fotoğraf çektiğin selfie ile eşleşmedi.'),
      findsOneWidget,
    );
    expect(find.text(_tr.faceAnchorRetry), findsOneWidget);
    expect(find.text(_tr.faceAnchorChooseAnother), findsOneWidget);
    expect(find.text(_tr.faceAnchorVerified), findsNothing);
  });

  testWidgets('liveness failure is explained without detail', (tester) async {
    final h = _Harness();
    h.repo.nextResult = const FaceAnchorState(
      status: FaceAnchorStatus.failed,
      reason: FaceAnchorReason.livenessFailed,
    );
    await h.pump(tester, locale: const Locale('tr'));

    await h.consentAndStart(tester, _tr);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Canlılık doğrulaması tamamlanamadı.'),
      findsOneWidget,
    );
    expect(find.text(_tr.faceAnchorRetry), findsOneWidget);
  });

  testWidgets('a provider outage is a temporary error, never a verification', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.nextResult = const FaceAnchorState(
      status: FaceAnchorStatus.error,
      reason: FaceAnchorReason.technicalError,
    );
    await h.pump(tester);

    await h.consentAndStart(tester, _en);
    await tester.pumpAndSettle();

    expect(find.text(_en.faceAnchorTechnicalError), findsOneWidget);
    expect(find.text(_en.faceAnchorVerified), findsNothing);
    expect(find.text(_en.faceAnchorRetry), findsOneWidget);
  });

  testWidgets('a refusal to start is shown, and can be retried', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.startFailure = const ValidationFailure(
      FaceAnchorMessages.attemptLimit,
    );
    await h.pump(tester);

    await h.consentAndStart(tester, _en);
    await tester.pumpAndSettle();

    expect(find.text(_en.faceAnchorErrorAttemptLimit), findsOneWidget);
    expect(find.text(_en.faceAnchorRetry), findsOneWidget);
    expect(h.capture.captures, 0);
  });

  testWidgets(
    'reopened mid-verification: shows the server state, starts nothing',
    (tester) async {
      final h = _Harness();
      h.repo.emit(
        const FaceAnchorState(
          status: FaceAnchorStatus.processing,
          photoId: 'p1',
          attemptId: 'attempt-9',
        ),
      );
      await h.pump(tester);
      await tester.pump();

      expect(find.text(_en.faceAnchorVerifying), findsOneWidget);
      expect(h.repo.calls, isEmpty);

      h.repo.emit(
        const FaceAnchorState(
          status: FaceAnchorStatus.verified,
          photoId: 'p1',
          attemptId: 'attempt-9',
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(_en.faceAnchorVerified), findsOneWidget);
    },
  );

  testWidgets('another photo\'s result does not show on this one', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.emit(
      const FaceAnchorState(
        status: FaceAnchorStatus.verified,
        photoId: 'someone-else',
        attemptId: 'attempt-9',
      ),
    );
    await h.pump(tester);
    await tester.pump();
    expect(find.text(_en.faceAnchorVerified), findsNothing);
    expect(find.text(_en.faceAnchorTakeSelfie), findsOneWidget);
  });

  group('wording', () {
    test('every outcome has a sentence in both languages, none technical', () {
      for (final l10n in [_tr, _en]) {
        for (final reason in [...FaceAnchorReason.values, null]) {
          final text = FaceAnchorL10n.reason(l10n, reason);
          expect(text, isNotEmpty);
          expect(text.toLowerCase(), isNot(contains('didit')));
          expect(text.toLowerCase(), isNot(contains('score')));
        }
        for (final key in [
          FaceAnchorMessages.unavailable,
          FaceAnchorMessages.cooldown,
          FaceAnchorMessages.attemptLimit,
          FaceAnchorMessages.cameraDenied,
          FaceAnchorMessages.uploadFailed,
          FaceAnchorMessages.inProgress,
          FaceAnchorMessages.photoNotApproved,
          'something-unknown',
          null,
        ]) {
          expect(FaceAnchorL10n.error(l10n, key), isNotEmpty);
        }
      }
    });

    test('the Turkish strings the product asked for', () {
      expect(_tr.faceAnchorVerifyAction, 'Fotoğrafını doğrula');
      expect(_tr.faceAnchorVerified, 'Bu fotoğraf doğrulandı');
      expect(_tr.faceAnchorPending, 'Doğrulama bekleniyor');
      expect(
        _tr.faceAnchorMismatch,
        'Bu fotoğraf çektiğin selfie ile eşleşmedi.',
      );
      expect(
        _tr.faceAnchorPrimaryRequiresVerify,
        'Bu fotoğrafı ana fotoğraf yapmak için önce doğrula.',
      );
      expect(
        _tr.faceAnchorLastAnchorDelete,
        startsWith('Son doğrulanmış fotoğrafını silemezsin.'),
      );
      expect(
        _tr.faceAnchorLastAnchorDelete,
        endsWith('Önce başka bir fotoğrafını doğrula.'),
      );
    });
  });

  group('edit profile photo list', () {
    const photos = [
      ProfilePhoto(
        id: 'me',
        storagePath: 'p/me',
        isPrimary: true,
        moderationStatus: 'approved',
        isFaceAnchorVerified: true,
      ),
      ProfilePhoto(
        id: 'dog',
        storagePath: 'p/dog',
        order: 1,
        moderationStatus: 'approved',
      ),
      ProfilePhoto(id: 'new', storagePath: 'p/new', order: 2),
    ];

    Widget editor({
      ValueChanged<ProfilePhoto>? onVerify,
      ValueChanged<String>? onSetPrimary,
      bool available = true,
    }) {
      return wrapWithApp(
        SingleChildScrollView(
          child: PhotoGridEditor(
            photos: photos,
            onAdd: () {},
            onDelete: (_) {},
            onReorder: (_, _) {},
            onSetPrimary: onSetPrimary ?? (_) {},
            onVerify: onVerify,
            faceAnchorStatusOf: (photo) => FaceAnchorPhotoStatus.resolve(
              photo: photo,
              state: FaceAnchorState.none,
              available: available,
            ),
          ),
        ),
      );
    }

    testWidgets(
      'marks the verified photo, offers the approved one, waits on the pending one',
      (tester) async {
        ProfilePhoto? verify;
        await tester.pumpWidget(editor(onVerify: (p) => verify = p));

        expect(find.text(_en.faceAnchorVerifiedShort), findsOneWidget);
        expect(find.text(_en.faceAnchorVerifyShort), findsOneWidget);
        expect(find.text(_en.faceAnchorPhotoInReview), findsOneWidget);

        await tester.tap(find.text(_en.faceAnchorVerifyShort));
        expect(verify?.id, 'dog');
      },
    );

    testWidgets(
      'the menu offers verification for an unverified approved photo',
      (tester) async {
        ProfilePhoto? verify;
        await tester.pumpWidget(editor(onVerify: (p) => verify = p));

        await tester.tap(find.byTooltip(_en.more).at(1));
        await tester.pumpAndSettle();
        expect(find.text(_en.faceAnchorVerifyAction), findsOneWidget);

        await tester.tap(find.text(_en.faceAnchorVerifyAction));
        await tester.pumpAndSettle();
        expect(verify?.id, 'dog');
      },
    );

    testWidgets('offers nothing while verification is unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(editor(onVerify: (_) {}, available: false));
      expect(find.text(_en.faceAnchorVerifyShort), findsNothing);
      // What is already verified still shows as verified.
      expect(find.text(_en.faceAnchorVerifiedShort), findsOneWidget);
    });
  });
}
