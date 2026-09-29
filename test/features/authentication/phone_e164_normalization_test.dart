import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';
import 'package:mevora/features/authentication/domain/services/e164_formatter.dart';
import 'package:mevora/features/authentication/domain/services/phone_number_validator.dart';
import 'package:mevora/features/authentication/domain/usecases/auth_usecases.dart';
import 'package:mevora/features/authentication/presentation/controllers/phone_auth_controller.dart';

import '../../helpers/fake_auth.dart';

/// Firebase Phone Auth only accepts E.164. Synthetic numbers only; real
/// numbers never belong in fixtures.
void main() {
  const expected = '+905421234567';
  const typedForms = [
    '0542 123 4567',
    '5421234567',
    '542 123 45 67',
    '(542) 123 45 67',
    '05421234567',
  ];

  group('Turkey (+90) national input → E.164', () {
    for (final typed in typedForms) {
      test('"$typed" → $expected', () {
        final result = PhoneNumberValidator.validate(
          country: CountryCodes.turkey,
          nationalNumber: typed,
        );
        expect(result.isValid, isTrue);
        expect(result.e164, expected);
        // Neither the trunk 0 nor a doubled country code may survive.
        expect(result.e164, isNot(startsWith('+900')));
        expect(result.e164, isNot(startsWith('+9090')));
        expect(E164Formatter.isValidE164(result.e164!), isTrue);
      });
    }
  });

  test(
    'the controller hands Firebase the E.164 string, never local format',
    () async {
      final repo = FakeAuthRepository();
      final controller = PhoneAuthController(
        sendPhoneVerificationCode: SendPhoneVerificationCode(repo),
        verifyPhoneCode: VerifyPhoneCode(repo),
        resendPhoneVerificationCode: ResendPhoneVerificationCode(repo),
        authRepository: repo,
        logger: const AppLogger(environment: AppEnvironment.development),
      );
      for (final typed in typedForms) {
        controller
          ..resetToPhoneEntry()
          ..updateNationalNumber(typed);
        expect(await controller.sendCode(), isTrue, reason: typed);
        expect(repo.lastE164Phone, expected, reason: typed);
      }
      controller.dispose();
    },
  );
}
