import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A release build must not merely keep developer code switched off: it must
/// not contain it. The compiler removes code only when it can see, from a
/// compile-time constant, that it is never reached — a runtime check such as
/// "is this the development environment" leaves the demo deck, the QA login
/// and the design gallery compiled into a store binary.
///
/// These are the places where `kReleaseMode` does that job. Removing one keeps
/// every other test green and puts the code back into the release build;
/// `node tool/productionBinaryScan.cjs` on a release snapshot is the check on
/// the real output.
void main() {
  String source(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('the demo social layer', () {
    expect(
      source('lib/bootstrap.dart'),
      contains(
        '!kReleaseMode && demoInfrastructureAllowed(environment: environment)',
      ),
    );
  });

  test('the demo deck', () {
    final factory = source('lib/core/di/discovery_services_factory.dart');
    final release = factory.indexOf('if (kReleaseMode) {');
    final demo = factory.indexOf('MockDiscoveryRepository demoDeck()');
    expect(release, greaterThan(0));
    expect(
      release,
      lessThan(demo),
      reason: 'the release return must come before anything names the deck',
    );
  });

  test('the demo portraits', () {
    expect(
      source('lib/shared/images/mevora_photo_images.dart'),
      contains('if (kReleaseMode || !demoPortraitsAvailable'),
    );
  });

  test('the QA login route and the design gallery route', () {
    final router = source('lib/core/routing/app_router.dart');
    for (final route in ['AppRoutes.qaLogin', 'AppRoutes.designSystem']) {
      final guarded = RegExp(
        '${r'if \(!kReleaseMode\)\s+GoRoute\(\s+path: '}'
        '${RegExp.escape(route)},',
      );
      expect(
        guarded.hasMatch(router),
        isTrue,
        reason: '$route must be declared under if (!kReleaseMode)',
      );
    }
  });

  test('the QA panel on the sign-in page', () {
    expect(
      RegExp(r'if \(!kReleaseMode\)\s+EmulatorQaLoginPanel\(').hasMatch(
        source(
          'lib/features/authentication/presentation/pages/login_page.dart',
        ),
      ),
      isTrue,
    );
  });

  test('the demo deck label in Discover', () {
    expect(
      source('lib/features/discovery/presentation/pages/discovery_page.dart'),
      contains('final demoDeck = !kReleaseMode && state.isMockMode;'),
    );
  });
}
