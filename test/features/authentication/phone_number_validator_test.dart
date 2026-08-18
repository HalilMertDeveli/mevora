import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';
import 'package:mevora/features/authentication/domain/services/e164_formatter.dart';
import 'package:mevora/features/authentication/domain/services/phone_number_validator.dart';

void main() {
  group('PhoneNumberValidator', () {
    test('rejects empty input', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '   ',
      );
      expect(result.isValid, isFalse);
      expect(result.issue, PhoneValidationIssue.empty);
    });

    test('rejects letters', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '555abc1234',
      );
      expect(result.issue, PhoneValidationIssue.invalidChars);
    });

    test('rejects wrong length for Turkey', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '555123',
      );
      expect(result.issue, PhoneValidationIssue.invalidLength);
    });

    test('accepts a valid Turkish mobile number as E.164', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '555 111 22 33',
      );
      expect(result.isValid, isTrue);
      expect(result.e164, '+905551112233');
    });

    test('accepts a Turkish number typed with a leading trunk 0', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '0555 111 22 33',
      );
      expect(result.isValid, isTrue);
      expect(result.e164, '+905551112233');
    });

    test('accepts 05321234567 as +905321234567', () {
      final result = PhoneNumberValidator.validate(
        country: CountryCodes.turkey,
        nationalNumber: '05321234567',
      );
      expect(result.isValid, isTrue);
      expect(result.e164, '+905321234567');
    });
  });

  group('E164Formatter', () {
    test('formats TR national groups', () {
      expect(
        E164Formatter.formatNational(CountryCodes.turkey, '5551112233'),
        '555 111 22 33',
      );
    });

    test('builds E.164 and masks without exposing the full number', () {
      const e164 = '+905551112233';
      expect(E164Formatter.toE164(CountryCodes.turkey, '5551112233'), e164);
      expect(E164Formatter.isValidE164(e164), isTrue);
      expect(E164Formatter.mask(e164), contains('••'));
      expect(E164Formatter.mask(e164), isNot(contains('55511122')));
    });
  });
}
