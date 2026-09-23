import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/verification/data/services/identity_verification_launcher.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification_session.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';
import 'package:mevora/features/verification/presentation/controllers/verification_controller.dart';
import 'package:url_launcher/url_launcher.dart';

class _FakeRepository implements VerificationRepository {
  final _states = StreamController<IdentityVerification>.broadcast();
  Result<IdentityVerificationSession>? sessionResult;
  int sessionCalls = 0;
  int refreshCalls = 0;
  String? lastLanguage;
  bool refreshThrows = false;

  void emit(IdentityVerification value) => _states.add(value);

  @override
  Stream<IdentityVerification> watchVerification(String uid) => _states.stream;

  @override
  Future<Result<IdentityVerificationSession>> startVerificationSession({
    String? language,
  }) async {
    sessionCalls += 1;
    lastLanguage = language;
    return sessionResult ??
        const Success(
          IdentityVerificationSession(
            providerSessionId: 'sess_1',
            launchUrl: 'https://verify.example/s/1',
          ),
        );
  }

  @override
  Future<void> refreshState() async {
    refreshCalls += 1;
    if (refreshThrows) {
      throw StateError('offline');
    }
  }

  Future<void> close() => _states.close();
}

class _FakeLauncher extends IdentityVerificationLauncher {
  _FakeLauncher({required this.links})
    : super(
        returnLinks: links.stream,
        launch: (Uri uri, {LaunchMode mode = LaunchMode.platformDefault}) async {
          _opened.add(uri);
          return _openResult;
        },
      );

  final StreamController<Uri> links;

  static final List<Uri> _opened = <Uri>[];
  static bool _openResult = true;

  static void reset({bool openResult = true}) {
    _opened.clear();
    _openResult = openResult;
  }

  static List<Uri> get opened => _opened;
}

void main() {
  late _FakeRepository repository;
  late StreamController<Uri> links;
  late _FakeLauncher launcher;
  late VerificationController controller;

  setUp(() {
    _FakeLauncher.reset();
    repository = _FakeRepository();
    links = StreamController<Uri>.broadcast();
    launcher = _FakeLauncher(links: links);
    controller = VerificationController(
      repository: repository,
      uid: 'uidA',
      launcher: launcher,
    )..attach();
  });

  tearDown(() async {
    controller.dispose();
    await links.close();
    await repository.close();
  });

  group('server authority', () {
    test('a deep-link return does not verify the user', () async {
      links.add(Uri.parse('mevora://verify/identity?status=approved'));
      await pumpEventQueue();

      expect(controller.verification.status.grantsVerifiedBadge, isFalse);
      expect(
        controller.verification.status,
        IdentityVerificationStatus.notStarted,
      );
      // It did exactly one thing: ask the backend.
      expect(repository.refreshCalls, 1);
    });

    test('a deep link claiming success still leaves the user unverified '
        'when the backend says otherwise', () async {
      links.add(Uri.parse('mevora://verify/identity?status=Approved&verified=true'));
      await pumpEventQueue();
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.declined),
      );
      await pumpEventQueue();

      expect(controller.verification.status, IdentityVerificationStatus.declined);
      expect(controller.verification.status.grantsVerifiedBadge, isFalse);
    });

    test('only a backend emission can produce a verified state', () async {
      expect(controller.verification.status.grantsVerifiedBadge, isFalse);
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.verified),
      );
      await pumpEventQueue();
      expect(controller.verification.status.grantsVerifiedBadge, isTrue);
    });

    test('an unrelated deep link is ignored entirely', () async {
      links.add(Uri.parse('mevora://auth/spotify?code=abc'));
      await pumpEventQueue();
      expect(repository.refreshCalls, 0);
    });

    test('a stream error holds the last known state rather than inventing one',
        () async {
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.inReview),
      );
      await pumpEventQueue();
      repository._states.addError(StateError('read failed'));
      await pumpEventQueue();
      expect(controller.verification.status, IdentityVerificationStatus.inReview);
    });
  });

  group('starting verification', () {
    test('opens the hosted URL and passes the locale as a hint', () async {
      await controller.startVerification(locale: const Locale('tr'));

      expect(repository.lastLanguage, 'tr');
      expect(_FakeLauncher.opened.single.toString(), 'https://verify.example/s/1');
      expect(controller.awaitingReturn, isTrue);
      expect(controller.phase, VerificationUiPhase.idle);
    });

    test('a second tap while busy does not create a second session', () async {
      final first = controller.startVerification();
      final second = controller.startVerification();
      await Future.wait([first, second]);
      expect(repository.sessionCalls, 1);
    });

    test('does not start when the backend state is already in flight', () async {
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.inReview),
      );
      await pumpEventQueue();

      await controller.startVerification();
      expect(repository.sessionCalls, 0);
    });

    test('does not start when the user is already verified', () async {
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.verified),
      );
      await pumpEventQueue();

      await controller.startVerification();
      expect(repository.sessionCalls, 0);
    });

    test('does not start while the cooldown is running', () async {
      repository.emit(
        IdentityVerification(
          status: IdentityVerificationStatus.declined,
          attemptCount: 1,
          lastAttemptAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      await pumpEventQueue();

      await controller.startVerification();
      expect(repository.sessionCalls, 0);
    });

    test('maps a backend failure to a UI key without leaking its text', () async {
      repository.sessionResult = const Err(
        ValidationFailure('verification-cooldown'),
      );
      await controller.startVerification();

      expect(controller.phase, VerificationUiPhase.error);
      expect(controller.errorKey, 'verification-cooldown');
      expect(controller.awaitingReturn, isFalse);
    });

    test('an unrecognised backend message becomes the generic key', () async {
      repository.sessionResult = const Err(
        UnexpectedFailure('DiditApiError: 500 workflow wf_abc not found'),
      );
      await controller.startVerification();

      expect(controller.errorKey, 'verification-generic-error');
    });

    test('a session with no launch URL is an error, not a silent no-op',
        () async {
      repository.sessionResult = const Success(
        IdentityVerificationSession(providerSessionId: 'sess_1'),
      );
      await controller.startVerification();

      expect(controller.phase, VerificationUiPhase.error);
      expect(controller.awaitingReturn, isFalse);
    });

    test('a launcher that cannot open the URL surfaces an error', () async {
      _FakeLauncher.reset(openResult: false);
      await controller.startVerification();

      expect(controller.phase, VerificationUiPhase.error);
      expect(controller.awaitingReturn, isFalse);
    });
  });

  group('resume and refresh', () {
    test('a terminal backend state stops the app waiting for a return',
        () async {
      await controller.startVerification();
      expect(controller.awaitingReturn, isTrue);

      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.verified),
      );
      await pumpEventQueue();
      expect(controller.awaitingReturn, isFalse);
    });

    test('an in-flight state keeps the processing affordance', () async {
      await controller.startVerification();
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.inReview),
      );
      await pumpEventQueue();
      expect(controller.awaitingReturn, isTrue);
    });

    test('refresh is not reentrant, so returns do not stack up', () async {
      final calls = <Future<void>>[
        controller.refresh(),
        controller.refresh(),
        controller.refresh(),
      ];
      await Future.wait(calls);
      expect(repository.refreshCalls, 1);
    });

    test('a failed refresh is not a verdict', () async {
      repository.refreshThrows = true;
      repository.emit(
        const IdentityVerification(status: IdentityVerificationStatus.inReview),
      );
      await pumpEventQueue();

      await controller.refresh();

      expect(controller.verification.status, IdentityVerificationStatus.inReview);
      expect(controller.errorKey, isNull);
      expect(controller.phase, VerificationUiPhase.idle);
    });
  });

  group('return link matching', () {
    test('recognises the verification return link only', () {
      expect(
        IdentityVerificationLauncher.isReturnLink(
          Uri.parse('mevora://verify/identity'),
        ),
        isTrue,
      );
      expect(
        IdentityVerificationLauncher.isReturnLink(
          Uri.parse('mevora://verify/identity?session_id=abc'),
        ),
        isTrue,
      );
      expect(
        IdentityVerificationLauncher.isReturnLink(
          Uri.parse('mevora://auth/spotify'),
        ),
        isFalse,
      );
      expect(
        IdentityVerificationLauncher.isReturnLink(
          Uri.parse('mevora://verify/other'),
        ),
        isFalse,
      );
    });
  });
}
