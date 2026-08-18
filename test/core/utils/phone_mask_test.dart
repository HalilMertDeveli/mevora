import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/utils/phone_mask.dart';

void main() {
  test('masks a Turkish mobile number without exposing the middle digits', () {
    expect(PhoneMask.mask('+905551112242'), '+90 5•• ••• •• 42');
    expect(PhoneMask.isValidE164('+905551112242'), isTrue);
    expect(PhoneMask.isValidE164('5551112242'), isFalse);
  });
}
