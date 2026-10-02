import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';

void main() {
  group('PersonNameValidator', () {
    test('a missing or whitespace-only name is required', () {
      for (final value in [null, '', '   ', '\t\n', '-', "'", '123', '🙂']) {
        expect(
          PersonNameValidator.validateFirstName(value),
          PersonNameIssue.required,
          reason: 'first name "$value"',
        );
        expect(
          PersonNameValidator.validateLastName(value),
          PersonNameIssue.required,
          reason: 'last name "$value"',
        );
      }
    });

    test('Turkish and international names are accepted', () {
      const names = [
        'Çağrı',
        'Gökçe',
        'İpek',
        'Işıl',
        'Öykü',
        'Şule',
        'Ümit',
        'Yiğit',
        'José',
        'Zoë',
        'Françoise',
        "O'Brien",
        "D'Angelo",
        'Jean-Luc',
        'Ayşe Nur',
        'de la Cruz',
        'van der Berg',
        'Öztürk-Şahin',
        'Нина',
        'محمد',
        '美咲',
      ];
      for (final name in names) {
        expect(
          PersonNameValidator.validateFirstName(name),
          isNull,
          reason: name,
        );
        expect(
          PersonNameValidator.validateLastName(name),
          isNull,
          reason: name,
        );
      }
    });

    test('surrounding whitespace is trimmed before the rules apply', () {
      expect(PersonNameValidator.normalize('  Halil \n'), 'Halil');
      expect(PersonNameValidator.validateFirstName('  Halil  '), isNull);
      expect(
        PersonNameValidator.validateFirstName(
          '  ${'a' * PersonNameValidator.maxFirstNameLength}  ',
        ),
        isNull,
      );
    });

    test('each name has its own length cap', () {
      expect(
        PersonNameValidator.validateFirstName(
          'a' * (PersonNameValidator.maxFirstNameLength + 1),
        ),
        PersonNameIssue.tooLong,
      );
      expect(
        PersonNameValidator.validateLastName(
          'a' * PersonNameValidator.maxLastNameLength,
        ),
        isNull,
      );
      expect(
        PersonNameValidator.validateLastName(
          'a' * (PersonNameValidator.maxLastNameLength + 1),
        ),
        PersonNameIssue.tooLong,
      );
    });

    test('a provider full name seeds only the first name', () {
      expect(PersonNameValidator.firstNameHint('Halil Develi'), 'Halil');
      expect(PersonNameValidator.firstNameHint('  Ayşe   Nur Yılmaz '), 'Ayşe');
      expect(PersonNameValidator.firstNameHint('Halil'), 'Halil');
      expect(PersonNameValidator.firstNameHint('   '), isNull);
      expect(PersonNameValidator.firstNameHint(null), isNull);
    });
  });
}
