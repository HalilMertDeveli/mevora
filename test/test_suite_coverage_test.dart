import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Flutter side of "full test suite" the way
/// `functions/test/testSuiteCoverage.test.cjs` guards the backend side.
///
/// `flutter test` collects `test/**/*_test.dart` itself and hands the files to
/// the runner explicitly, so a top-level `paths:` key in `dart_test.yaml` never
/// reaches it. The repository carried such a key anyway, together with a
/// comment claiming the later-phase suites were "not executed here". That was
/// wrong — every suite was running — but the config was one runner change, or
/// one `dart test` invocation, away from becoming true silently.
///
/// These assertions keep the gate honest: nothing may re-narrow discovery, and
/// CI must keep naming the whole `test/` tree.
void main() {
  group('flutter test discovery', () {
    test('no config narrows the default test paths', () {
      final config = File('dart_test.yaml');
      if (!config.existsSync()) {
        return;
      }
      final lines = config
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'));

      expect(
        lines.any((line) => line == 'paths:' || line.startsWith('paths:')),
        isFalse,
        reason:
            'dart_test.yaml must not declare `paths:`. It restricts `dart test` '
            'and misrepresents what the suite covers; `flutter test` already '
            'defaults to the whole test/ directory.',
      );
    });

    test('every feature directory contributes to the suite', () {
      final features = Directory('test/features');
      expect(features.existsSync(), isTrue);

      final withoutTests = <String>[];
      for (final entry in features.listSync().whereType<Directory>()) {
        final hasTest = entry
            .listSync(recursive: true)
            .whereType<File>()
            .any((file) => file.path.endsWith('_test.dart'));
        if (!hasTest) {
          withoutTests.add(entry.uri.pathSegments.where((s) => s.isNotEmpty).last);
        }
      }

      expect(
        withoutTests,
        isEmpty,
        reason:
            'these test/features directories hold no *_test.dart file, so they '
            'contribute nothing to the gate: $withoutTests',
      );
    });
  });

  group('CI gate', () {
    late String workflow;

    setUpAll(() {
      final file = File('.github/workflows/ci.yml');
      expect(
        file.existsSync(),
        isTrue,
        reason: '.github/workflows/ci.yml is the regression gate',
      );
      workflow = file.readAsStringSync();
    });

    test('runs the whole test tree explicitly', () {
      expect(
        RegExp(r'flutter test\s+test\b').hasMatch(workflow),
        isTrue,
        reason:
            'CI must run `flutter test test` so the gate names the directory '
            'rather than relying on the runner default.',
      );
    });

    test('does not pass a narrower path than the test directory', () {
      final invocations = RegExp(
        r'flutter test([^\n]*)',
      ).allMatches(workflow).map((m) => m.group(1)!.trim());

      for (final args in invocations) {
        final paths = args
            .split(RegExp(r'\s+'))
            .where((token) => token.startsWith('test/'));
        expect(
          paths,
          isEmpty,
          reason:
              'CI passes a narrowed test path ($paths); the full-suite job must '
              'gate the entire test/ tree.',
        );
      }
    });

    test('still runs the analyzer', () {
      expect(workflow.contains('flutter analyze'), isTrue);
    });
  });
}
