import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_snapshot.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/entities/phone_challenge.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/data/services/auth_analytics.dart';
import 'package:mevora/features/authentication/domain/repositories/auth_repository.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';
import 'package:mevora/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:mevora/features/authentication/presentation/controllers/phone_auth_controller.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository authRepository,
    required UserDocumentRepository userDocumentRepository,
    required AppLogger logger,
    AuthAnalytics? analytics,
  }) : _authRepository = authRepository,
       _userDocumentRepository = userDocumentRepository,
       _logger = logger,
       _analytics = analytics ?? const NoOpAuthAnalytics() {
    phoneAuth = PhoneAuthController(
      sendPhoneVerificationCode: SendPhoneVerificationCode(_authRepository),
      verifyPhoneCode: VerifyPhoneCode(_authRepository),
      resendPhoneVerificationCode: ResendPhoneVerificationCode(
        _authRepository,
      ),
      authRepository: _authRepository,
      logger: _logger,
      analytics: _analytics,
    );
    phoneAuth.addListener(_onPhoneAuthChanged);
  }

  final AuthRepository _authRepository;
  final UserDocumentRepository _userDocumentRepository;
  final AppLogger _logger;
  final AuthAnalytics _analytics;
  late final PhoneAuthController phoneAuth;

  StreamSubscription<AuthSnapshot>? _subscription;
  Timer? _resendTimer;
  bool _actionInFlight = false;
  int _generation = 0;

  AuthStatus status = const AuthInitializing();
  AuthUser? user;
  String? errorMessage;
  AuthErrorKind? errorKind;
  PhoneChallenge? phoneChallenge;
  int resendSeconds = 0;

  bool get isBusy =>
      _actionInFlight ||
      status is AuthInitializing ||
      status is Authenticating;

  bool get isReady => status is! AuthInitializing;

  void start() {
    _subscription ??= _authRepository.watchAuth().listen(
      (snapshot) {
        unawaited(_onSnapshot(snapshot));
      },
      onError: (Object error, StackTrace stackTrace) {
        _logger.error(
          'Auth state stream failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (_actionInFlight) {
          return;
        }
        user = null;
        status = const Unauthenticated();
        notifyListeners();
      },
    );
    unawaited(_authRepository.restorePendingOAuth());
  }

  Future<void> _onSnapshot(AuthSnapshot snapshot) async {
    final generation = ++_generation;
    switch (snapshot) {
      case AuthSignedOut():
        if (_actionInFlight ||
            status is PhoneCodeSent ||
            status is PhoneVerificationRequired) {
          return;
        }
        user = null;
        status = const Unauthenticated();
      case AuthProfilePending(:final uid):
        if (status is Unauthenticated || status is AuthInitializing) {
          status = const Authenticating();
        }
        try {
          await _userDocumentRepository.ensureUserDocument(AuthUser(id: uid));
          if (generation != _generation) {
            return;
          }
        } on Object catch (error, stackTrace) {
          _logger.error(
            'Failed to resolve pending profile',
            error: error,
            stackTrace: stackTrace,
          );
        }
      case AuthProfileReady(:final user):
        if (user.isBanned || !user.isActive) {
          unawaited(_handleBanned());
          return;
        }
        this.user = user;
        errorMessage = null;
        errorKind = null;
        _actionInFlight = false;
        phoneChallenge = null;
        try {
          await _userDocumentRepository.ensureUserDocument(user);
          if (generation != _generation) {
            return;
          }
          status = user.shouldOnboard
              ? NeedsOnboarding(user)
              : Authenticated(user);
        } on Object catch (error, stackTrace) {
          _logger.error(
            'Failed to resolve profile completeness',
            error: error,
            stackTrace: stackTrace,
          );
          if (generation != _generation) {
            return;
          }
          status = NeedsOnboarding(user);
        }
    }
    notifyListeners();
  }

  Future<void> _handleBanned() async {
    try {
      await _authRepository.signOut();
    } on Object {
      // Surface banned even if sign-out fails.
    }
    user = null;
    errorKind = AuthErrorKind.banned;
    errorMessage = AuthMessages.banned;
    status = const AuthenticationError(AuthMessages.banned);
    notifyListeners();
  }

  Future<Result<void>> register({
    required String email,
    required String password,
  }) {
    return _run(
      () => _authRepository.registerWithEmail(
        email: email,
        password: password,
      ),
      provider: 'email',
    );
  }

  Future<Result<void>> signIn({
    required String email,
    required String password,
  }) {
    return _run(
      () => _authRepository.signInWithEmail(email: email, password: password),
      provider: 'email',
    );
  }

  Future<Result<void>> sendPasswordReset(String email) async {
    final result = await _run(
      () => _authRepository.sendPasswordResetEmail(email),
    );
    if (result case Err<void>(:final failure)) {
      if (failure is AuthFailure &&
          failure.kind == AuthErrorKind.userNotFound) {
        errorMessage = null;
        errorKind = null;
        if (status is AuthenticationError) {
          status = const Unauthenticated();
        }
        notifyListeners();
        return const Success<void>(null);
      }
    }
    return result;
  }

  Future<Result<void>> signInWithGoogle() async {
    await _analytics.googleLoginStarted();
    final result = await _run(
      _authRepository.signInWithGoogle,
      provider: 'google',
    );
    switch (result) {
      case Success<void>():
        await _analytics.googleLoginSuccess();
      case Err<void>(:final failure):
        if (failure is AuthFailure &&
            (failure.isCancelled || failure.kind == AuthErrorKind.cancelled)) {
          await _analytics.googleLoginCancelled();
        } else {
          await _analytics.googleLoginFailed();
        }
    }
    return result;
  }

  Future<Result<void>> signInWithApple() {
    return _run(_authRepository.signInWithApple, provider: 'apple');
  }

  Future<Result<void>> signInWithSpotify() {
    return _run(_authRepository.signInWithSpotify, provider: 'spotify');
  }

  Future<Result<void>> sendPhoneCode(String e164Phone) async {
    _actionInFlight = true;
    errorMessage = null;
    errorKind = null;
    status = const Authenticating(provider: 'phone');
    notifyListeners();
    final result = await _authRepository.sendPhoneVerificationCode(e164Phone);
    switch (result) {
      case Success<PhoneChallenge>(:final value):
        phoneChallenge = value;
        if (value.autoVerified) {
          final auto = await _authRepository.completePhoneAutoVerification();
          _actionInFlight = false;
          return auto.when(
            success: (next) {
              _applyAuthenticatedUser(next);
              notifyListeners();
              return const Success<void>(null);
            },
            err: (failure) {
              _setFailure(failure);
              return Err(failure);
            },
          );
        }
        _actionInFlight = false;
        status = PhoneCodeSent(value);
        _startResendTimer();
        notifyListeners();
        return const Success<void>(null);
      case Err<PhoneChallenge>(:final failure):
        _actionInFlight = false;
        _setFailure(failure);
        return Err(failure);
    }
  }

  Future<Result<void>> verifyPhoneCode(String smsCode) async {
    final challenge = phoneChallenge;
    if (challenge == null) {
      return const Err(AuthFailure(AuthMessages.invalidOtp));
    }
    final validation = OtpValidator.validate(smsCode);
    if (validation != null) {
      errorKind = AuthErrorKind.invalidOtp;
      errorMessage = validation;
      notifyListeners();
      return Err(ValidationFailure(validation));
    }
    _actionInFlight = true;
    errorMessage = null;
    status = PhoneVerificationRequired(challenge);
    notifyListeners();
    final result = await _authRepository.verifyPhoneCode(
      challenge: challenge,
      smsCode: smsCode,
    );
    _actionInFlight = false;
    return result.when(
      success: (next) {
        _applyAuthenticatedUser(next);
        notifyListeners();
        return const Success<void>(null);
      },
      err: (failure) {
        status = PhoneVerificationRequired(challenge);
        errorKind = failure is AuthFailure ? failure.kind : AuthErrorKind.invalidOtp;
        errorMessage = failure.message;
        notifyListeners();
        return Err(failure);
      },
    );
  }

  Future<Result<void>> resendPhoneCode() async {
    final challenge = phoneChallenge;
    if (challenge == null || resendSeconds > 0 || _actionInFlight) {
      return const Success<void>(null);
    }
    _actionInFlight = true;
    notifyListeners();
    final result = await _authRepository.resendPhoneVerificationCode(challenge);
    _actionInFlight = false;
    return result.when(
      success: (next) {
        phoneChallenge = next;
        status = PhoneCodeSent(next);
        errorMessage = null;
        _startResendTimer();
        notifyListeners();
        return const Success<void>(null);
      },
      err: (failure) {
        errorKind = failure is AuthFailure ? failure.kind : null;
        errorMessage = failure.message;
        notifyListeners();
        return Err(failure);
      },
    );
  }

  Future<Result<void>> linkProvider(AuthProviderId provider) {
    return _run(() => _authRepository.linkProvider(provider));
  }

  Future<Result<void>> linkEmail({
    required String email,
    required String password,
  }) {
    return _run(
      () => _authRepository.linkEmail(email: email, password: password),
    );
  }

  Future<Result<void>> signOut() {
    return _run(_authRepository.signOut, afterSuccess: _resetToLoggedOut);
  }

  Future<Result<void>> deleteAccount() {
    return _run(
      _authRepository.deleteAccount,
      afterSuccess: _resetToLoggedOut,
    );
  }

  void returnToLogin() {
    phoneChallenge = null;
    _resendTimer?.cancel();
    resendSeconds = 0;
    errorMessage = null;
    errorKind = null;
    if (status is! Authenticated) {
      status = const Unauthenticated();
    }
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null &&
        errorKind == null &&
        status is! AuthenticationError) {
      return;
    }
    errorMessage = null;
    errorKind = null;
    if (status is AuthenticationError) {
      status = const Unauthenticated();
    }
    notifyListeners();
  }

  void _resetToLoggedOut() {
    user = null;
    phoneChallenge = null;
    errorMessage = null;
    errorKind = null;
    status = const Unauthenticated();
  }

  void _applyAuthenticatedUser(AuthUser next) {
    user = next;
    phoneChallenge = null;
    errorMessage = null;
    errorKind = null;
    status = next.shouldOnboard ? NeedsOnboarding(next) : Authenticated(next);
  }

  Future<Result<void>> _run<T>(
    Future<Result<T>> Function() action, {
    String? provider,
    VoidCallback? afterSuccess,
  }) async {
    _actionInFlight = true;
    errorMessage = null;
    errorKind = null;
    if (provider != null) {
      status = Authenticating(provider: provider);
    }
    notifyListeners();
    final result = await action();
    _actionInFlight = false;
    switch (result) {
      case Success<T>():
        afterSuccess?.call();
        notifyListeners();
        return const Success<void>(null);
      case Err<T>(:final failure):
        if (failure is AuthFailure &&
            (failure.isCancelled || failure.kind == AuthErrorKind.cancelled)) {
          if (status is Authenticating) {
            status = const Unauthenticated();
          }
          errorMessage = null;
          errorKind = null;
          notifyListeners();
          return Err(failure);
        }
        _setFailure(failure);
        return Err(failure);
    }
  }

  void _setFailure(Failure failure) {
    errorKind = failure is AuthFailure ? failure.kind : null;
    errorMessage = failure.message;
    if (status is PhoneCodeSent ||
        status is PhoneVerificationRequired ||
        status is Authenticated ||
        status is NeedsOnboarding) {
      notifyListeners();
      return;
    }
    status = AuthenticationError(failure.message);
    notifyListeners();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    resendSeconds = OtpValidator.resendSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (resendSeconds <= 1) {
        timer.cancel();
        resendSeconds = 0;
      } else {
        resendSeconds -= 1;
      }
      notifyListeners();
    });
  }

  /// Keeps [AuthStatus] / redirect rules aligned with [PhoneAuthController]
  /// so OTP success is not bounced back to `/phone` before the auth stream
  /// emits a profile-ready snapshot.
  void _onPhoneAuthChanged() {
    switch (phoneAuth.state) {
      case SendingOtp():
        if (status is Unauthenticated ||
            status is AuthenticationError ||
            status is PhoneCodeSent) {
          status = const Authenticating(provider: 'phone');
        }
      case OtpSent(:final challenge):
        final sameChallenge =
            phoneChallenge?.verificationId == challenge.verificationId &&
            phoneChallenge?.resendAttempt == challenge.resendAttempt &&
            status is PhoneCodeSent;
        phoneChallenge = challenge;
        if (!sameChallenge &&
            (status is Unauthenticated ||
                status is AuthenticationError ||
                status is Authenticating ||
                status is PhoneCodeSent ||
                status is PhoneVerificationRequired)) {
          status = PhoneCodeSent(challenge);
          _startResendTimer();
        }
      case VerifyingOtp(:final challenge):
        phoneChallenge = challenge;
        if (status is! PhoneVerificationRequired) {
          status = PhoneVerificationRequired(challenge);
        }
      case PhoneAuthenticated(:final user):
        if (status is! Authenticated && status is! NeedsOnboarding) {
          _applyAuthenticatedUser(user);
        }
      case PhoneNumberEntering() || SmsSendError() || TooManyAttempts():
        if (status is PhoneCodeSent ||
            status is PhoneVerificationRequired ||
            (status is Authenticating &&
                (status as Authenticating).provider == 'phone')) {
          phoneChallenge = null;
          _resendTimer?.cancel();
          resendSeconds = 0;
          status = const Unauthenticated();
        }
      case OtpError(:final challenge):
        phoneChallenge = challenge;
        status = PhoneVerificationRequired(challenge);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    phoneAuth.removeListener(_onPhoneAuthChanged);
    phoneAuth.dispose();
    _resendTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
