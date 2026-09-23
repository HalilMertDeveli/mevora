import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_idensic_mobile_sdk_plugin/flutter_idensic_mobile_sdk_plugin.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

enum VerificationUiPhase { idle, loadingToken, launchingSdk, error }

class VerificationController extends ChangeNotifier {
  VerificationController({
    required VerificationRepository repository,
    required String uid,
  }) : _repository = repository,
       _uid = uid;

  final VerificationRepository _repository;
  final String _uid;

  StreamSubscription<IdentityVerification>? _subscription;
  IdentityVerification verification = IdentityVerification.notStarted;
  VerificationUiPhase phase = VerificationUiPhase.idle;
  String? errorKey;

  void attach() {
    _subscription ??= _repository.watchVerification(_uid).listen(
      (value) {
        verification = value;
        notifyListeners();
      },
      onError: (_, _) {
        verification = IdentityVerification.notStarted;
        notifyListeners();
      },
    );
  }

  Future<void> startVerification({required Locale locale}) async {
    if (!verification.status.canStart || phase != VerificationUiPhase.idle) {
      return;
    }
    phase = VerificationUiPhase.loadingToken;
    errorKey = null;
    notifyListeners();

    final sessionResult = await _repository.startVerificationSession();
    final session = sessionResult.valueOrNull;
    if (sessionResult.isError || session == null) {
      phase = VerificationUiPhase.error;
      errorKey = _errorKeyFromFailure(sessionResult.failureOrNull?.message);
      notifyListeners();
      return;
    }

    final launchToken = session.launchToken;
    if (launchToken == null || launchToken.isEmpty) {
      // A hosted-flow session (launchUrl) is Phase 4's job. Until then this
      // controller only drives the native SDK path.
      phase = VerificationUiPhase.error;
      errorKey = 'verification-generic-error';
      notifyListeners();
      return;
    }

    phase = VerificationUiPhase.launchingSdk;
    notifyListeners();

    try {
      final sdk = SNSMobileSDK.init(
        launchToken,
        () async {
          final refresh = await _repository.startVerificationSession();
          final token = refresh.valueOrNull?.launchToken;
          if (refresh.isError || token == null || token.isEmpty) {
            throw StateError('token-refresh-failed');
          }
          return token;
        },
      )
          .withLocale(locale)
          .withDebug(kDebugMode)
          .build();
      await sdk.launch();
    } on Object {
      errorKey = 'verification-sdk-error';
    } finally {
      phase = VerificationUiPhase.idle;
      notifyListeners();
    }
  }

  String? _errorKeyFromFailure(String? message) {
    return switch (message) {
      'verification-not-configured' => 'verification-not-configured',
      'verification-cooldown' => 'verification-cooldown',
      'verification-attempt-limit' => 'verification-attempt-limit',
      'already-verified' => 'already-verified',
      _ => 'verification-generic-error',
    };
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
