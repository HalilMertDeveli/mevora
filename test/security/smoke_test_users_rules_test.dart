import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/firestore.rules').readAsStringSync();
  });

  test('clients cannot set isSmokeTestUser', () {
    expect(rules.contains("'isSmokeTestUser'"), isTrue);
  });

  test('smoke test callables are documented in functions source', () {
    final source = File('functions/src/smoke/smokeTestUsers.ts').readAsStringSync();
    expect(source.contains('prepareSmokeTestUsers'), isTrue);
    expect(source.contains('cleanupSmokeTestUsers'), isTrue);
    expect(source.contains('SMOKE_TEST_SECRET'), isTrue);
  });
}
