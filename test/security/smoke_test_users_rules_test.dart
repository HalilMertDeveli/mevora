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
    final source = File(
      'functions/src/smoke/smokeTestUsers.ts',
    ).readAsStringSync();
    expect(source.contains('prepareSmokeTestUsers'), isTrue);
    expect(source.contains('cleanupSmokeTestUsers'), isTrue);
    expect(source.contains('SMOKE_TEST_SECRET'), isTrue);
    // Both refuse at call time outside the Functions emulator.
    expect(source.contains('"emulator-only"'), isTrue);
  });

  test('smoke test callables reach a backend only through the emulator-only '
      'gate', () {
    final index = File('functions/src/index.ts').readAsStringSync();
    final emulatorOnly = File(
      'functions/src/emulatorOnly.ts',
    ).readAsStringSync();

    // A deploy loads index.ts without FUNCTIONS_EMULATOR, so a name it exports
    // unconditionally is a deployed function. The entry point must not name
    // the smoke callables or their module at all.
    expect(index.contains('prepareSmokeTestUsers'), isFalse);
    expect(index.contains('cleanupSmokeTestUsers'), isFalse);
    expect(index.contains('smokeTestUsers'), isFalse);

    // They are exported from the emulator-only module...
    expect(
      RegExp(
        r'export \{prepareSmokeTestUsers, cleanupSmokeTestUsers\} from '
        r'"\./smoke/smokeTestUsers\.js"',
      ).hasMatch(emulatorOnly),
      isTrue,
    );
    // ...which the entry point loads only inside the emulator process.
    expect(
      RegExp(
        r'if \(process\.env\.FUNCTIONS_EMULATOR === "true"\) \{\s*'
        r'Object\.assign\(exports, require\("\./emulatorOnly\.js"\)\);\s*\}',
      ).hasMatch(index),
      isTrue,
    );
    expect(
      RegExp(r'''from\s+["']\./emulatorOnly''').hasMatch(index),
      isFalse,
      reason: 'a static import would load the smoke module in every deploy',
    );
  });
}
