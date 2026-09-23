import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/features/verification/data/services/identity_verification_launcher.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

/// What the screen is doing right now, as distinct from what the *backend*
/// says about the user. [VerificationController.verification] is the
/// authority; this is only the local activity indicator.
enum VerificationUiPhase { idle, creatingSession, launching, refreshing, error }

/// Drives the verification screen.
///
/// The one rule this class exists to enforce: nothing here can make a user
/// verified. Opening the provider flow, coming back from it, and refreshing
/// afterwards all end in the same place — re-reading MEVORA's backend state.
/// There is no path through this file that writes
/// [IdentityVerificationStatus.verified].
class VerificationController extends ChangeNotifier {
  VerificationController({
    required VerificationRepository repository,
    required String uid,
    IdentityVerificationLauncher? launcher,
  }) : _repository = repository,
       _uid = uid,
       _launcher = launcher ?? IdentityVerificationLauncher(),
       _ownsLauncher = launcher == null;

  final VerificationRepository _repository;
  final String _uid;
  final IdentityVerificationLauncher _launcher;
  final bool _ownsLauncher;

  StreamSubscription<IdentityVerification>? _subscription;
  StreamSubscription<void>? _returnSubscription;

  IdentityVerification verification = IdentityVerification.notStarted;
  VerificationUiPhase phase = VerificationUiPhase.idle;
  String? errorKey;

  /// True once the user has been sent to the provider and has not yet been
  /// seen to reach a terminal state. Survives a rebuild but not a process
  /// death — which is fine: the backend state does survive, and that is what
  /// the UI actually renders.
  bool awaitingReturn = false;

  bool get isBusy => phase != VerificationUiPhase.idle;

  bool get canStart =>
      !isBusy &&
      verification.status.canStart &&
      verification.retryEligibility().allowed;

  void attach() {
    _subscription ??= _repository.watchVerification(_uid).listen(
      (value) {
        verification = value;
        // The backend has spoken; stop waiting for a return that has already
        // been answered.
        if (value.status.isTerminal) {
          awaitingReturn = false;
        }
        notifyListeners();
      },
      onError: (_, _) {
        // A read failure is not a verdict. Hold the last known state rather
        // than inventing one in either direction.
        notifyListeners();
      },
    );

    // The return link only ever triggers a re-read. It is never evidence.
    _returnSubscription ??= _launcher.returns.listen((_) {
      unawaited(refresh());
    });
  }

  /// Re-reads backend state. Called on return from the provider, on app
  /// resume, and on an explicit pull to refresh.
  ///
  /// Cheap and idempotent. The Firestore stream is the primary path; this is
  /// the belt-and-braces read for the case where the app was killed while the
  /// user was in the provider flow. It never polls on a timer.
  Future<void> refresh() async {
    if (phase == VerificationUiPhase.refreshing) {
      return;
    }
    phase = VerificationUiPhase.refreshing;
    notifyListeners();
    try {
      await _repository.refreshState();
    } on Object {
      // The stream remains the source of truth; a failed nudge changes
      // nothing and must not surface as a verification failure.
    } finally {
      phase = VerificationUiPhase.idle;
      notifyListeners();
    }
  }

  /// Starts (or resumes) verification.
  ///
  /// Guarded against repeated taps by [isBusy] here and by the backend, which
  /// refuses a second session while one is already in flight.
  Future<void> startVerification({Locale? locale}) async {
    if (!canStart) {
      return;
    }
    phase = VerificationUiPhase.creatingSession;
    errorKey = null;
    notifyListeners();

    final result = await _repository.startVerificationSession(
      language: locale?.languageCode,
    );
    final session = result.valueOrNull;
    if (result.isError || session == null) {
      phase = VerificationUiPhase.error;
      errorKey = _errorKeyFromFailure(result.failureOrNull?.message);
      notifyListeners();
      return;
    }

    final url = session.launchUrl;
    if (url == null || url.isEmpty) {
      phase = VerificationUiPhase.error;
      errorKey = 'verification-generic-error';
      notifyListeners();
      return;
    }

    phase = VerificationUiPhase.launching;
    notifyListeners();

    final opened = await _launcher.open(Uri.parse(url));
    if (!opened) {
      phase = VerificationUiPhase.error;
      errorKey = 'verification-generic-error';
      notifyListeners();
      return;
    }

    awaitingReturn = true;
    phase = VerificationUiPhase.idle;
    notifyListeners();
  }

  /// Maps a backend failure code to a UI key.
  ///
  /// Anything unrecognised becomes the generic key on purpose: a provider or
  /// backend message must never reach the screen verbatim.
  String? _errorKeyFromFailure(String? message) {
    return switch (message) {
      'verification-not-configured' => 'verification-not-configured',
      'verification-cooldown' => 'verification-cooldown',
      'verification-attempt-limit' => 'verification-attempt-limit',
      'verification-in-progress' => 'verification-in-progress',
      'already-verified' => 'already-verified',
      'verification-unavailable' => 'verification-unavailable',
      _ => 'verification-generic-error',
    };
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_returnSubscription?.cancel());
    if (_ownsLauncher) {
      unawaited(_launcher.dispose());
    }
    super.dispose();
  }
}
