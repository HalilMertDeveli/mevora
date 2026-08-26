import 'dart:async';
import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';
import 'package:mevora/features/authentication/data/pkce.dart';
import 'package:mevora/features/authentication/data/services/spotify_pending_store.dart';
import 'package:mevora/features/authentication/domain/auth_messages.dart';
import 'package:mevora/features/authentication/domain/entities/auth_provider_id.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:url_launcher/url_launcher.dart';

class _PendingSpotifyAuth {
  const _PendingSpotifyAuth({
    required this.pkce,
    required this.state,
    required this.linkToCurrentUser,
    required this.purpose,
    this.loginCompleter,
    this.musicCompleter,
  });

  final PkcePair pkce;
  final String state;
  final bool linkToCurrentUser;
  final SpotifyOAuthPurpose purpose;
  final Completer<AuthSession>? loginCompleter;
  final Completer<void>? musicCompleter;

  bool get isOpen {
    final login = loginCompleter;
    if (login != null && !login.isCompleted) {
      return true;
    }
    final music = musicCompleter;
    if (music != null && !music.isCompleted) {
      return true;
    }
    return login == null && music == null;
  }
}

class SpotifyAuthService {
  SpotifyAuthService({
    required this.config,
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? functions,
    AppLinks? appLinks,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launch,
    SpotifyPendingStore? pendingStore,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: config.functionsRegion),
       _appLinks = appLinks ?? AppLinks(),
       _launch = launch ?? launchUrl,
       _pendingStore = pendingStore ?? StaticSpotifyPendingStore() {
    _linkSubscription = _appLinks.uriLinkStream.listen(_onUri);
  }

  final AppConfig config;
  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions _functions;
  final AppLinks _appLinks;
  final Future<bool> Function(Uri uri, {LaunchMode mode}) _launch;
  final SpotifyPendingStore _pendingStore;

  StreamSubscription<Uri>? _linkSubscription;
  _PendingSpotifyAuth? _pending;

  /// Identity-only scopes. Playback and library scopes stay off the login path.
  static const loginScopes = 'user-read-private';

  /// Taste analysis only. No streaming, playback, or playlist modification.
  static const musicScopes =
      'user-top-read user-read-recently-played playlist-read-private';

  Future<AuthSession> signIn({required bool linkToCurrentUser}) async {
    final completer = Completer<AuthSession>();
    await _beginOAuth(
      purpose: SpotifyOAuthPurpose.login,
      scopes: loginScopes,
      linkToCurrentUser: linkToCurrentUser,
      loginCompleter: completer,
    );
    try {
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw const AuthException(
            AuthMessages.cancelled,
            kind: AuthErrorKind.cancelled,
            isCancelled: true,
          );
        },
      );
    } finally {
      if (_pending?.loginCompleter == completer) {
        _pending = null;
      }
    }
  }

  /// Account linking for the Spotify Web API. Does not replace Firebase Auth.
  Future<void> linkMusicAccount() async {
    if (_firebaseAuth.currentUser == null) {
      throw const AuthException(
        AuthMessages.sessionExpired,
        kind: AuthErrorKind.sessionExpired,
      );
    }
    final completer = Completer<void>();
    await _beginOAuth(
      purpose: SpotifyOAuthPurpose.musicLink,
      scopes: musicScopes,
      linkToCurrentUser: true,
      musicCompleter: completer,
    );
    try {
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw const AuthException(
            AuthMessages.cancelled,
            kind: AuthErrorKind.cancelled,
            isCancelled: true,
          );
        },
      );
    } finally {
      if (_pending?.musicCompleter == completer) {
        _pending = null;
      }
    }
  }

  Future<void> _beginOAuth({
    required SpotifyOAuthPurpose purpose,
    required String scopes,
    required bool linkToCurrentUser,
    Completer<AuthSession>? loginCompleter,
    Completer<void>? musicCompleter,
  }) async {
    if (config.spotifyClientId.isEmpty) {
      throw const AuthException(
        AuthMessages.notConfigured,
        kind: AuthErrorKind.notConfigured,
      );
    }

    final pkce = PkcePair.generate();
    final state = _randomState();
    _pending = _PendingSpotifyAuth(
      pkce: pkce,
      state: state,
      linkToCurrentUser: linkToCurrentUser,
      purpose: purpose,
      loginCompleter: loginCompleter,
      musicCompleter: musicCompleter,
    );
    await _pendingStore.save(
      SpotifyPendingAuth(
        state: state,
        verifier: pkce.verifier,
        linkToCurrentUser: linkToCurrentUser,
        purpose: purpose,
      ),
    );

    final authorizeUri = Uri.https('accounts.spotify.com', '/authorize', {
      'client_id': config.spotifyClientId,
      'response_type': 'code',
      'redirect_uri': config.spotifyRedirectUri,
      'code_challenge_method': 'S256',
      'code_challenge': pkce.challenge,
      'state': state,
      'scope': scopes,
    });

    final launched = await _launch(
      authorizeUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched) {
      _pending = null;
      await _pendingStore.clear();
      throw const AuthException(
        AuthMessages.oauth,
        kind: AuthErrorKind.oauth,
      );
    }
  }

  Future<void> handleInitialUri() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        await _onUri(uri);
      }
    } on Object {
      // Cold-start without a pending PKCE session is ignored.
    }
  }

  Future<void> _onUri(Uri uri) async {
    if (!SpotifyAuthService.isSpotifyCallback(uri)) {
      return;
    }

    final pending = await _resolvePending();
    if (pending == null) {
      return;
    }

    final error = uri.queryParameters['error'];
    if (error != null) {
      await _failPending(
        pending,
        const AuthException(
          AuthMessages.cancelled,
          kind: AuthErrorKind.cancelled,
          isCancelled: true,
        ),
      );
      return;
    }

    final state = uri.queryParameters['state'];
    final code = uri.queryParameters['code'];
    if (state != pending.state || code == null || code.isEmpty) {
      await _failPending(
        pending,
        const AuthException(
          AuthMessages.spotifyCallbackExpired,
          kind: AuthErrorKind.oauth,
        ),
      );
      return;
    }

    try {
      if (pending.purpose == SpotifyOAuthPurpose.musicLink) {
        await _exchangeMusic(code: code, verifier: pending.pkce.verifier);
        await _pendingStore.clear();
        _pending = null;
        final completer = pending.musicCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final session = await _exchangeLogin(
        code: code,
        verifier: pending.pkce.verifier,
      );
      await _pendingStore.clear();
      _pending = null;
      final completer = pending.loginCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(session);
      }
    } on Object catch (error) {
      await _failPending(pending, AuthErrorMapper.map(error));
    }
  }

  Future<_PendingSpotifyAuth?> _resolvePending() async {
    final inMemory = _pending;
    if (inMemory != null && inMemory.isOpen) {
      return inMemory;
    }
    final stored = await _pendingStore.read();
    if (stored == null) {
      return null;
    }
    return _PendingSpotifyAuth(
      pkce: PkcePair(verifier: stored.verifier, challenge: ''),
      state: stored.state,
      linkToCurrentUser: stored.linkToCurrentUser,
      purpose: stored.purpose,
    );
  }

  Future<void> _failPending(
    _PendingSpotifyAuth pending,
    AuthException error,
  ) async {
    await _pendingStore.clear();
    _pending = null;
    final login = pending.loginCompleter;
    if (login != null && !login.isCompleted) {
      login.completeError(error);
    }
    final music = pending.musicCompleter;
    if (music != null && !music.isCompleted) {
      music.completeError(error);
    }
  }

  Future<void> _exchangeMusic({
    required String code,
    required String verifier,
  }) async {
    try {
      final callable = _functions.httpsCallable('spotifyLinkMusic');
      await callable.call<Map<String, dynamic>>({
        'code': code,
        'codeVerifier': verifier,
        'redirectUri': config.spotifyRedirectUri,
      });
    } on FirebaseFunctionsException catch (error) {
      throw AuthErrorMapper.fromCode(
        error.details is Map &&
                (error.details as Map)['mevoraCode'] is String
            ? (error.details as Map)['mevoraCode'] as String
            : (error.message ?? error.code),
        cause: error,
      );
    }
  }

  Future<AuthSession> _exchangeLogin({
    required String code,
    required String verifier,
  }) async {
    try {
      final callable = _functions.httpsCallable('spotifyCompleteAuth');
      final response = await callable.call<Map<String, dynamic>>({
        'code': code,
        'codeVerifier': verifier,
        'redirectUri': config.spotifyRedirectUri,
      });
      final data = response.data;
      final customToken = data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) {
        final alreadyLinked = data['alreadyLinked'] == true;
        final uid = _firebaseAuth.currentUser?.uid;
        if (alreadyLinked && uid != null) {
          return AuthSession(
            uid: uid,
            provider: AuthProviderId.spotify,
            email: data['email'] as String?,
            displayName: data['displayName'] as String?,
            photoUrl: data['photoUrl'] as String?,
            persistDisplayName: true,
            persistEmail: true,
          );
        }
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }

      final result = await _firebaseAuth.signInWithCustomToken(customToken);
      final user = result.user;
      if (user == null) {
        throw const AuthException(
          AuthMessages.oauth,
          kind: AuthErrorKind.oauth,
        );
      }
      return AuthSession(
        uid: user.uid,
        provider: AuthProviderId.spotify,
        email: data['email'] as String? ?? user.email,
        displayName: data['displayName'] as String? ?? user.displayName,
        photoUrl: data['photoUrl'] as String? ?? user.photoURL,
        persistDisplayName: true,
        persistEmail: true,
        isNewUser: data['isNewUser'] == true,
      );
    } on FirebaseFunctionsException catch (error) {
      throw AuthErrorMapper.fromCode(
        error.details is Map &&
                (error.details as Map)['mevoraCode'] is String
            ? (error.details as Map)['mevoraCode'] as String
            : error.code,
        cause: error,
      );
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthErrorMapper.map(error);
    }
  }

  static bool isSpotifyCallback(Uri uri) {
    if (uri.scheme == 'mevora' &&
        uri.host == 'auth' &&
        uri.path.startsWith('/spotify')) {
      return true;
    }
    if (uri.host.endsWith('mevora.app') &&
        uri.path.startsWith('/auth/spotify')) {
      return true;
    }
    return false;
  }

  String _randomState() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> dispose() async {
    await _linkSubscription?.cancel();
  }
}
