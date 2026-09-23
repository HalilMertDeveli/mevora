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
