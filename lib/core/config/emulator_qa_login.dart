import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/config/app_config.dart';

/// One seeded Firebase Emulator account offered as a sign-in shortcut.
class EmulatorQaAccount {
  const EmulatorQaAccount({
    required this.label,
    required this.email,
    required this.password,
  });

  final String label;
  final String email;
  final String password;

  /// Seeded uid. tool/seedEmulatorQaUsers.cjs keys accounts by the local part
  /// of the address, so qa_user_a@mevora.test is uid qa_user_a.
  String get uid => email.split('@').first;
}

/// Emulator-only sign-in shortcuts for two-user runtime QA.
///
/// This is deliberately *not* an authentication path. The shortcut fills the
/// existing email/password form and submits it through the normal
/// `AuthRepository.signInWithEmail`, so the resulting session is an ordinary
/// Firebase Auth session and nothing downstream needs to know QA exists.
///
/// Three independent conditions must all hold before it appears, so a release
/// build can neither show it nor carry the accounts:
///   1. a development build — [AppConfig.useEmulators] is false otherwise;
///   2. `USE_EMULATORS=true` and `USE_AUTH_EMULATOR=true`, so Firebase Auth is
///      actually pointed at the emulator;
///   3. credentials supplied at build time. They default to empty, so a
///      production binary contains no QA account and no QA password at all.
abstract final class EmulatorQaLogin {
  static const String _emailA = String.fromEnvironment('QA_EMAIL_A');
  static const String _emailB = String.fromEnvironment('QA_EMAIL_B');
  static const String _password = String.fromEnvironment('QA_PASSWORD');

  /// Accounts compiled into this build. Empty unless supplied via
  /// `--dart-define`, which is the whole point: nothing to leak otherwise.
  static List<EmulatorQaAccount> get accounts {
    if (_password.isEmpty) {
      return const <EmulatorQaAccount>[];
    }
    return <EmulatorQaAccount>[
      if (_emailA.isNotEmpty)
        const EmulatorQaAccount(label: 'QA User A', email: _emailA, password: _password),
      if (_emailB.isNotEmpty)
        const EmulatorQaAccount(label: 'QA User B', email: _emailB, password: _password),
    ];
  }

  /// The single gate. Checked by the widget before rendering and again before
  /// any shortcut may act, so hiding the button is not the only defence.
  static bool isEnabled(AppConfig config) {
    return config.useAuthEmulator && accounts.isNotEmpty;
  }

  /// Signs in with an unsigned custom token, which the Auth emulator accepts.
  ///
  /// Why this exists: password sign-in runs a reCAPTCHA Enterprise pre-flight
  /// through Google Play Services even when the Auth emulator is configured.
  /// On emulator images with broken Play Services that pre-flight times out and
  /// the app reports "Check your internet connection", so no seeded account can
  /// sign in at all.
  ///
  /// This is still real Firebase Auth: signInWithCustomToken produces a genuine
  /// emulator session with the seeded uid, and reCAPTCHA plays no part in custom
  /// token exchange. It is not a bypass — no state is injected, and the whole
  /// path is behind the same [isEnabled] gate. The emulator ignores the
  /// signature, which is exactly why this can never work against production.
  static Future<UserCredential?> signInWithEmulatorToken(
    AppConfig config,
    String email,
  ) async {
    final account = resolve(config, email);
    if (account == null) {
      return null;
    }
    String segment(Map<String, dynamic> value) => base64Url
        .encode(utf8.encode(jsonEncode(value)))
        .replaceAll('=', '');
    final issuedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final header = segment(<String, dynamic>{'alg': 'none', 'typ': 'JWT'});
    final payload = segment(<String, dynamic>{
      'iss': 'firebase-auth-emulator@example.com',
      'sub': 'firebase-auth-emulator@example.com',
      'aud':
          'https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit',
      'iat': issuedAt,
      'exp': issuedAt + 3600,
      'uid': account.uid,
    });
    return FirebaseAuth.instance.signInWithCustomToken('$header.$payload.');
  }

  /// Resolves a shortcut, refusing outright when QA login is not enabled.
  /// Returns null rather than throwing so a caller can never act on a stale
  /// widget after the flag has been evaluated as false.
  static EmulatorQaAccount? resolve(AppConfig config, String email) {
    if (!isEnabled(config)) {
      return null;
    }
    for (final account in accounts) {
      if (account.email == email) {
        return account;
      }
    }
    return null;
  }
}
