import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/extensions/string_extensions.dart';
import 'package:mevora/core/utils/validators.dart';

void main() {
  group('Validators', () {
    test('requiredField rejects blank values', () {
      expect(Validators.requiredField('  ', field: 'Name'), 'Name is required');
      expect(Validators.requiredField('Ada'), isNull);
    });

    test('email validates format', () {
      expect(Validators.email(''), 'Email is required');
      expect(Validators.email('not-an-email'), 'Enter a valid email');
      expect(Validators.email('user@mevora.app'), isNull);
    });

    test('minLength enforces a minimum', () {
      expect(
        Validators.minLength('ab', 8, field: 'Password'),
        'Password must be at least 8 characters',
      );
      expect(Validators.minLength('abcdefgh', 8, field: 'Password'), isNull);
    });
  });

  group('StringX', () {
    test('initials uses up to two name parts', () {
      expect('Ada Lovelace'.initials, 'AL');
      expect('Mevora'.initials, 'M');
      expect('   '.initials, '');
    });
  });
}
