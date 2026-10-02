import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/build_guards.dart';

/// The app refuses to start when a staging or production build was given a
/// development-only `--dart-define` (`developmentDefinesOutsideDevelopment`).
/// The launch configurations people press F5 on must agree with that rule, or
/// the staging and production entries would open on the start-up error
/// screen — which is how this test came to exist.
void main() {
  // launch.json allows comments; a line that is only a comment is dropped.
  final launch =
      jsonDecode(
            File('.vscode/launch.json')
                .readAsStringSync()
                .split('\n')
                .where((line) => !line.trimLeft().startsWith('//'))
                .join('\n'),
          )
          as Map<String, dynamic>;
  final configurations = (launch['configurations'] as List<dynamic>)
      .cast<Map<String, dynamic>>();

  Set<String> defines(Map<String, dynamic> configuration) {
    final arguments = <String>[
      ...?(configuration['args'] as List<dynamic>?)?.cast<String>(),
      ...?(configuration['toolArgs'] as List<dynamic>?)?.cast<String>(),
    ];
    return {
      for (final argument in arguments)
        if (argument.startsWith('--dart-define='))
          argument.substring('--dart-define='.length).split('=').first,
    };
  }

  test('there are launch configurations for each environment', () {
    final programs = configurations.map((c) => c['program']).toSet();
    expect(
      programs,
      containsAll(<String>[
        'lib/main_development.dart',
        'lib/main_staging.dart',
        'lib/main_production.dart',
      ]),
    );
  });

  test('staging and production configurations pass no development-only '
      'define', () {
    final developmentOnly = developmentDefinesPassed().keys.toSet();
    for (final configuration in configurations) {
      if (configuration['program'] == 'lib/main_development.dart') {
        continue;
      }
      expect(
        defines(configuration).intersection(developmentOnly),
        isEmpty,
        reason:
            '"${configuration['name']}" would be refused at start-up: these '
            'defines are for development builds only',
      );
    }
  });

  test('each configuration runs its flavor from its own entrypoint', () {
    for (final configuration in configurations) {
      final arguments = (configuration['args'] as List<dynamic>).cast<String>();
      final flavor = arguments[arguments.indexOf('--flavor') + 1];
      expect(
        configuration['program'],
        'lib/main_$flavor.dart',
        reason: '"${configuration['name']}"',
      );
    }
  });
}
