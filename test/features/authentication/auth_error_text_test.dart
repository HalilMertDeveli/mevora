import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

/// What the sign-in screens show for an auth error is copy in the member's
/// language, chosen by the kind of error — not whatever string the data layer
/// happened to attach to the failure.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tr = lookupAppLocalizations(const Locale('tr'));

  AuthController controller() {
    final auth = AuthController(
      authRepository: FakeAuthRepository(),
      userDocumentRepository: FakeUserDocumentRepository(),
      logger: const AppLogger(environment: AppEnvironment.development),
    );
    addTearDown(auth.dispose);
    return auth;
  }

  test('no error, no text', () {
    expect(localizeAuthError(en, controller()), isNull);
  });

  test('an error with a kind is shown in the member language', () {
    final auth = controller()
      ..errorKind = AuthErrorKind.billingNotEnabled
      ..errorMessage = 'anything the data layer wrote';
    expect(localizeAuthError(en, auth), en.authBillingNotEnabled);
    expect(localizeAuthError(tr, auth), tr.authBillingNotEnabled);
  });

  test('an unconfirmed session is not shown in Turkish to everyone', () {
    final auth = controller()
      ..errorMessage = AuthController.sessionUnverifiedMessage;
    expect(localizeAuthError(en, auth), en.authSessionUnverified);
    expect(localizeAuthError(tr, auth), tr.authSessionUnverified);
    expect(
      localizeAuthError(en, auth),
      isNot(AuthController.sessionUnverifiedMessage),
    );
  });

  test('the generic failure text is localized too', () {
    final auth = controller()..errorMessage = FailureMapper.unexpectedMessage;
    expect(localizeAuthError(en, auth), en.somethingWentWrong);
    expect(localizeAuthError(tr, auth), tr.somethingWentWrong);
  });

  test('sign-in errors say nothing about how the app is built or hosted', () {
    // These four used to name Firebase, a billing plan, "this build" and
    // "a physical device" — a developer's diagnosis, shown to members.
    for (final l10n in [en, tr]) {
      for (final text in [
        l10n.authNotConfigured,
        l10n.authBillingNotEnabled,
        l10n.authAppVerification,
        l10n.musicNotConfigured,
      ]) {
        expect(
          text,
          isNot(
            matches(
              RegExp(
                'firebase|blaze|billing|faturaland|build|sürümde|'
                'physical device|gerçek bir cihaz|configured|yapılandır',
                caseSensitive: false,
              ),
            ),
          ),
          reason: text,
        );
      }
    }
  });
}
