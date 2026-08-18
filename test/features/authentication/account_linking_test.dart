import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/authentication/data/mappers/auth_error_mapper.dart';

void main() {
  test('never auto-merges accounts because emails match', () {
    expect(
      AccountLinkingPolicy.shouldAutoMergeByEmail(
        existingEmail: 'ada@gmail.com',
        incomingEmail: 'ada@gmail.com',
      ),
      isFalse,
    );
    expect(
      AccountLinkingPolicy.shouldAutoMergeByEmail(
        existingEmail: 'relay@privaterelay.appleid.com',
        incomingEmail: 'ada@gmail.com',
      ),
      isFalse,
    );
  });
}
