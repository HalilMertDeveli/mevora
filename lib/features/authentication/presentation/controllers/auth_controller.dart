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
import 'package:mevora/features/authentication/domain/entities/restored_session_check.dart';
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
    Duration deletedAccountSettleDelay = const Duration(seconds: 10),
  }) : _authRepository = authRepository,
       _userDocumentRepository = userDocumentRepository,
       _logger = logger,
       _analytics = analytics ?? const NoOpAuthAnalytics(),
       _deletedAccountSettleDelay = deletedAccountSettleDelay {
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

  /// How long after an account document disappears the Auth account is asked
  /// about again, see [_mayCreateAccountDocument].
  final Duration _deletedAccountSettleDelay;
  late final PhoneAuthController phoneAuth;

  /// Set as [errorMessage] when a restored session could not be confirmed.
  /// The login page shows `authSessionUnverified` for it.
  static const String sessionUnverifiedMessage =
      'Oturum doğrulanamadı. Lütfen tekrar giriş yapın.';

  StreamSubscription<AuthSnapshot>? _subscription;
  Timer? _resendTimer;
  bool _actionInFlight = false;
  bool _signingOut = false;

  /// The account being signed out or deleted while [_signingOut] is set.
  /// Only its snapshots are the late echoes that flag guards against; a
  /// snapshot for any other account is a new session.
  String? _closingUid;
  bool _disposed = false;
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
  }

  Future<void> _onSnapshot(AuthSnapshot snapshot) async {
    final generation = ++_generation;
    switch (snapshot) {
      case AuthSignedOut():
        if (!_signingOut &&
            (_actionInFlight ||
                status is PhoneCodeSent ||
                status is PhoneVerificationRequired)) {
          return;
        }
        user = null;
        status = const Unauthenticated();
      case AuthProfilePending(:final uid):
        if (_isClosingSessionEcho(uid)) {
          return;
        }
        if (_actionInFlight) {
          // Sign-in flows already upsert the user document.
          status = const Authenticating();
        } else {
          // Read before the status changes: a member this process already
          // had a document for is one whose document was just deleted.
          final documentVanished = user?.id == uid;
          if (status is Unauthenticated || status is AuthInitializing) {
            status = const Authenticating();
          }
          if (!await _mayCreateAccountDocument(
            uid,
            generation,
            documentVanished: documentVanished,
          )) {
            return;
          }
          try {
            await _userDocumentRepository
                .ensureUserDocument(AuthUser(id: uid))
                .timeout(const Duration(seconds: 20));
            if (generation != _generation) {
              return;
            }
          } on Object catch (error, stackTrace) {
            _logger.error(
              'Failed to resolve pending profile',
              error: error,
              stackTrace: stackTrace,
            );
            if (generation != _generation || _actionInFlight) {
              return;
            }
            // Do not leave Authenticating forever (login buttons stay disabled).
            user = null;
            errorMessage = sessionUnverifiedMessage;
            status = AuthenticationError(errorMessage!);
            notifyListeners();
            unawaited(_authRepository.signOut());
            return;
          }
        }
      case AuthProfileReady(:final user):
        if (_isClosingSessionEcho(user.id)) {
          return;
        }
        // A suspension keeps the session: the member lands on the
        // restricted screen (router) and is released when the account
        // document flips back to active. Everything else that is not active
        // ends the session.
        if (!user.isSuspended && (user.isBanned || !user.isActive)) {
          unawaited(_handleBanned());
          return;
        }
        this.user = user;
        errorMessage = null;
        errorKind = null;
        _actionInFlight = false;
        phoneChallenge = null;
        // Document already exists (Ready). Do not upsert here — writing
        // lastLoginAt would re-trigger users/{uid} snapshots in a loop.
        status = user.shouldOnboard
            ? NeedsOnboarding(user)
            : Authenticated(user);
    }
    notifyListeners();
  }

  /// Whether the missing account document of the session [uid] may be
  /// created. Settles the session itself when it may not.
  ///
  /// This is the path for a session nobody just signed in to — restored from
  /// the device, or already running when its document disappeared. Such a
  /// session can belong to an account that no longer exists: the server
  /// deletes the documents and the Auth account, the device signs out only
  /// afterwards, and if the app dies in between (or the account is deleted
  /// from another device) the cached ID token still passes the security
  /// rules for up to an hour. Creating the document then brings a deleted
  /// account back as an empty one. So Firebase Auth is asked first:
  ///
  ///  * the account exists — create the document, as before;
  ///  * the session is over (account deleted or disabled, tokens revoked) —
  ///    the repository has already cleared this device; end on the sign-in
  ///    screen with no error, since nothing failed from the member's side;
  ///  * no answer (offline, timeout) — create nothing and do not sign out.
  ///    A real member whose document is missing lands on the sign-in screen
  ///    with the "could not verify" message and keeps the session, so the
  ///    next launch with a connection finishes the job without a new
  ///    sign-in. Creating blindly is the one outcome that cannot be undone,
  ///    and signing out would cost a real member the session for being
  ///    offline (it used to: the document write failed and signed them out).
  ///
  /// [documentVanished] is the stricter case: the document was there in this
  /// process and is gone. Only account deletion removes it, and the server
  /// deletes the Auth account last, after calls to outside providers, so
  /// "the account exists" may be seconds out of date. It is asked again
  /// after [_deletedAccountSettleDelay] before the document is re-created.
  Future<bool> _mayCreateAccountDocument(
    String uid,
    int generation, {
    required bool documentVanished,
  }) async {
    var check = await _verifyRestoredSession(uid);
    if (documentVanished && check == RestoredSessionCheck.accountExists) {
      await Future<void>.delayed(_deletedAccountSettleDelay);
      if (_disposed || generation != _generation || _actionInFlight) {
        return false;
      }
      check = await _verifyRestoredSession(uid);
    }
    if (_disposed || generation != _generation || _actionInFlight) {
      // A newer snapshot or a sign-in owns the session now.
      return false;
    }
    switch (check) {
      case RestoredSessionCheck.accountExists:
        return true;
      case RestoredSessionCheck.sessionClosed:
        _resetToLoggedOut();
        notifyListeners();
        return false;
      case RestoredSessionCheck.unverified:
        user = null;
        errorMessage = sessionUnverifiedMessage;
        status = AuthenticationError(errorMessage!);
        notifyListeners();
        return false;
    }
  }

  Future<RestoredSessionCheck> _verifyRestoredSession(String uid) async {
    try {
      return await _authRepository.verifyRestoredSession(uid);
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Failed to verify restored session',
        error: error,
        stackTrace: stackTrace,
      );
      return RestoredSessionCheck.unverified;
    }
  }

  /// Whether a profile snapshot for [uid] must be ignored as a late echo of
  /// the account being signed out.
  ///
  /// A snapshot for a different account means someone signed in after the
  /// sign-out, through a path that never went through [_run] (the emulator
  /// QA shortcut, for one). That ends the guard, so the new session is not
  /// ignored until the next provider sign-in.
  bool _isClosingSessionEcho(String uid) {
    if (!_signingOut) {
      return false;
    }
    final closing = _closingUid;
    if (closing == null || closing == uid) {
      return true;
    }
    _endSignOutGuard();
    return false;
  }

  void _endSignOutGuard() {
    _signingOut = false;
    _closingUid = null;
  }

  /// Call before a sign-in that bypasses this controller and talks to
  /// Firebase directly (the emulator QA shortcut).
  ///
  /// Starting a sign-in is a deliberate new session, so the snapshots that
  /// follow are that session and not late echoes of the account that just
  /// signed out, even when it is the same account. Without this, signing
  /// back in as the same user that way would be ignored until a restart.
  /// Ignored while a sign-out is still running.
  void beginExternalSignIn() {
    if (_actionInFlight) {
      return;
    }
    _endSignOutGuard();
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
      onSuccess: _applyAuthenticatedUser,
    );
  }

  Future<Result<void>> signIn({
    required String email,
    required String password,
  }) {
    return _run(
      () => _authRepository.signInWithEmail(email: email, password: password),
      provider: 'email',
      onSuccess: _applyAuthenticatedUser,
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
      onSuccess: _applyAuthenticatedUser,
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
    return _run(
      _authRepository.signInWithApple,
      provider: 'apple',
      onSuccess: _applyAuthenticatedUser,
    );
  }

  Future<Result<void>> signInWithSpotify() {
    return _run(
      _authRepository.signInWithSpotify,
      provider: 'spotify',
      onSuccess: _applyAuthenticatedUser,
    );
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

  Future<Result<void>> signOut() async {
    if (_disposed) {
      return const Success<void>(null);
    }
    if (_actionInFlight) {
      return const Success<void>(null);
    }
    if (user == null && status is Unauthenticated) {
      return const Success<void>(null);
    }
    _closingUid = user?.id;
    _signingOut = true;
    _generation += 1;
    final result = await _run(
      _authRepository.signOut,
      afterSuccess: _resetUnlessSessionReplaced,
    );
    if (result is Err<void>) {
      _signingOut = false;
    }
    return result;
  }

  Future<Result<void>> deleteAccount() async {
    if (_disposed || _actionInFlight) {
      return const Success<void>(null);
    }
    _closingUid = user?.id;
    _signingOut = true;
    _generation += 1;
    final result = await _run(
      _authRepository.deleteAccount,
      afterSuccess: _resetUnlessSessionReplaced,
    );
    if (result is Err<void>) {
      _signingOut = false;
    }
    return result;
  }

  Future<Result<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _run(
      () => _authRepository.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
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

  Future<void> reportLoginScreenViewed() {
    return _analytics.loginScreenViewed();
  }

  /// Settles a finished sign-out, unless another account's session was
  /// already accepted while it ran (see [_isClosingSessionEcho]).
  void _resetUnlessSessionReplaced() {
    if (_signingOut) {
      _resetToLoggedOut();
    }
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

  /// Keeps redirect rules in sync immediately after onboarding completes.
  void applyOnboardingComplete() {
    final current = user;
    if (current == null) {
      return;
    }
    _applyAuthenticatedUser(
      current.copyWith(
        profileCompleted: true,
        onboardingCompleted: true,
      ),
    );
  }

  Future<Result<void>> _run<T>(
    Future<Result<T>> Function() action, {
    String? provider,
    VoidCallback? afterSuccess,
    void Function(T value)? onSuccess,
  }) async {
    if (provider != null) {
      _signingOut = false;
    }
    _actionInFlight = true;
    errorMessage = null;
    errorKind = null;
    if (provider != null) {
      status = Authenticating(provider: provider);
    }
    notifyListeners();
    final result = await action();
    _actionInFlight = false;
    if (_disposed) {
      return result.when(
        success: (_) => const Success<void>(null),
        err: (failure) => Err<void>(failure),
      );
    }
    switch (result) {
      case Success<T>(:final value):
        onSuccess?.call(value);
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
  void notifyListeners() {
    if (_disposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    phoneAuth.removeListener(_onPhoneAuthChanged);
    phoneAuth.dispose();
    _resendTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
