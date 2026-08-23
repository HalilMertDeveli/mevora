import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_idensic_mobile_sdk_plugin/flutter_idensic_mobile_sdk_plugin.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';
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

  StreamSubscription<ProfileVerification>? _subscription;
  ProfileVerification verification = ProfileVerification.notStarted;
  VerificationUiPhase phase = VerificationUiPhase.idle;
  String? errorKey;

  void attach() {
    _subscription ??= _repository.watchVerification(_uid).listen(
      (value) {
        verification = value;
        notifyListeners();
      },
      onError: (_, _) {
        verification = ProfileVerification.notStarted;
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

    final tokenResult = await _repository.createAccessToken();
    if (tokenResult.isError) {
      phase = VerificationUiPhase.error;
      errorKey = _errorKeyFromFailure(tokenResult.failureOrNull?.message);
      notifyListeners();
      return;
    }

    phase = VerificationUiPhase.launchingSdk;
    notifyListeners();

    try {
      final sdk = SNSMobileSDK.init(
        tokenResult.valueOrNull!,
        () async {
          final refresh = await _repository.createAccessToken();
          if (refresh.isError || refresh.valueOrNull == null) {
            throw StateError('token-refresh-failed');
          }
          return refresh.valueOrNull!;
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
