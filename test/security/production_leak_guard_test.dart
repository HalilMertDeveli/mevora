import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/build_guards.dart';
import 'package:mevora/core/config/emulator_qa_login.dart';
import 'package:mevora/core/di/discovery_services_factory.dart';
import 'package:mevora/core/di/humor_services_factory.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Production leak guard.
///
/// Mevora keeps its test doubles, demo deck, QA login and emulator tooling in
/// the repository. This file is the promise that none of it reaches a member:
/// for a staging or production configuration every switch below is off, and
/// asking for it to be on — a define, a flag, a missing dependency — does not
/// turn it on.
///
/// It runs with no `--dart-define`, which is how a store build is made. The
/// repository-wide static scan (imports, fallbacks, logging, copy, public
/// pages, backend exports) is `node tool/productionReadiness.cjs`, section
/// "production leak scan"; the backend half is
/// `functions/test/productionSurface.test.cjs`.
void main() {
  const shipped = [AppEnvironment.staging, AppEnvironment.production];

  group('a shipped configuration cannot reach test infrastructure', () {
    test('no emulator, whatever is asked for', () {
      for (final environment in shipped) {
        final config = AppConfig(environment: environment);
        expect(config.useEmulators, isFalse, reason: '$environment');
        expect(config.useAuthEmulator, isFalse, reason: '$environment');
        expect(config.showDebugBanner, isFalse, reason: '$environment');
      }
    });

    test('no QA login and no QA account', () {
      for (final environment in shipped) {
        final config = AppConfig(environment: environment);
        expect(EmulatorQaLogin.isEnabled(config), isFalse);
        expect(EmulatorQaLogin.accountsFor(config), isEmpty);
      }
      expect(
        EmulatorQaLogin.accounts,
        isEmpty,
        reason: 'no QA credential is compiled into a build made without them',
      );
    });

    test('no mock data source, even with the define set', () {
      for (final environment in <AppEnvironment?>[...shipped, null]) {
        expect(
          mockDataSourceAllowed(
            define: true,
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: '$environment',
        );
      }
      for (final environment in shipped) {
        expect(
          resolveUseMockHumor(
            define: 'true',
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: '$environment',
        );
      }
    });

    test('no demo deck, no demo matches, no demo portraits', () {
      for (final environment in <AppEnvironment?>[...shipped, null]) {
        expect(
          demoInfrastructureAllowed(
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: '$environment',
        );
      }
      for (final environment in shipped) {
        expect(
          createDiscoveryServices(
            config: AppConfig(environment: environment),
            backend: _UnusedBackend(),
          ).discoveryRepository,
          isA<DiscoveryRepositoryImpl>(),
          reason: '$environment talks to the backend and nothing else',
        );
      }
      // Until start-up says otherwise, nothing maps to a bundled portrait.
      expect(MevoraPhotoImages.demoPortraitsAvailable, isFalse);
      expect(MevoraNetworkImages.provider('mock://mock-01/0'), isNull);
      expect(
        MevoraNetworkImages.provider('assets/images/portraits/mock-01.jpg'),
        isNull,
      );
    });

    test('no test store, even when asked for', () {
      for (final environment in <AppEnvironment?>[...shipped, null]) {
        expect(
          emulatorStoreAllowed(
            requested: true,
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: '$environment',
        );
      }
    });

    test('Premium is not switched on by the environment', () {
      // Entitlement is the server's; this is only whether the surface shows.
      for (final environment in shipped) {
        expect(resolvePremiumEnabled(environment), isFalse);
      }
    });

    test('a release build of the development flavor is not a demo either', () {
      expect(
        demoInfrastructureAllowed(
          environment: AppEnvironment.development,
          releaseMode: true,
        ),
        isFalse,
      );
      expect(
        mockDataSourceAllowed(
          define: true,
          environment: AppEnvironment.development,
          releaseMode: true,
        ),
        isFalse,
      );
      expect(
        emulatorStoreAllowed(
          requested: true,
          environment: AppEnvironment.development,
          releaseMode: true,
        ),
        isFalse,
      );
    });
  });

  group('developer routes are closed', () {
    const member = AuthUser(id: 'u1', profileCompleted: true);
    const statuses = <AuthStatus>[Unauthenticated(), Authenticated(member)];

    test('the design system gallery', () {
      for (final status in statuses) {
        expect(
          AuthRedirector.redirect(
            status: status,
            location: AppRoutes.designSystem,
          ),
          isNotNull,
          reason: '$status must be sent away',
        );
      }
    });

    test('the QA login page', () {
      for (final status in statuses) {
        expect(
          AuthRedirector.redirect(status: status, location: AppRoutes.qaLogin),
          isNotNull,
          reason: '$status must be sent away',
        );
      }
    });

    test('the router decides both from the environment, not from a flag', () {
      final router = File(
        'lib/core/routing/app_router.dart',
      ).readAsStringSync();
      expect(router, contains('allowDesignSystem: config.showDebugBanner'));
      expect(
        router,
        contains('qaLoginEnabled: EmulatorQaLogin.isEnabled(config)'),
      );
    });
  });

  group('a mis-built app does not start', () {
    test('development-only settings in a shipped build are refused', () {
      for (final environment in shipped) {
        for (final define in developmentDefinesPassed().keys) {
          expect(
            developmentDefinesOutsideDevelopment(
              environment: environment,
              passed: {define: true},
            ),
            contains(define),
            reason: '$define in a $environment build',
          );
        }
      }
    });

    test('a flavor started from another entrypoint is refused', () {
      expect(
        flavorEnvironmentMismatch(
          flavor: 'production',
          environment: AppEnvironment.development,
        ),
        isNotNull,
      );
      expect(
        flavorEnvironmentMismatch(
          flavor: 'development',
          environment: AppEnvironment.production,
        ),
        isNotNull,
      );
    });
  });

  group('product code and test code stay apart', () {
    Iterable<File> productFiles() sync* {
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll(r'\', '/');
        if (path.startsWith('lib/core/testing/') ||
            path.startsWith('lib/l10n/')) {
          continue;
        }
        yield entity;
      }
    }

    test('nothing in lib/ imports lib/core/testing', () {
      final offenders = <String>[];
      final import = RegExp(
        r"^\s*import\s+'[^']*core/testing/[^']*';",
        multiLine: true,
      );
      for (final file in productFiles()) {
        if (import.hasMatch(file.readAsStringSync())) {
          offenders.add(file.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('nothing in lib/ falls back to a stand-in', () {
      // `x ?? FakeThing()` is how a missing dependency turns into invented
      // data in front of a member. The one allowed site is the in-memory
      // factory that only tests call.
      const allowed = {'lib/core/di/social_services_factory.dart'};
      final fallback = RegExp(
        r'\?\?\s*(?:const\s+)?(?:Fake|Mock|Stub|InMemory|Demo)[A-Z]\w*\(',
      );
      final offenders = <String>[];
      for (final file in productFiles()) {
        final path = file.path.replaceAll(r'\', '/');
        if (allowed.contains(path)) {
          continue;
        }
        if (fallback.hasMatch(file.readAsStringSync())) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('lib/core/testing is used by tests', () {
      // If nothing used it, it would be dead weight rather than isolated
      // infrastructure — and a sign the guard above is scanning the wrong tree.
      final used = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .any(
            (file) => file.readAsStringSync().contains(
              'package:mevora/core/testing/',
            ),
          );
      expect(used, isTrue);
    });
  });
}

class _UnusedBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) {
    throw UnsupportedError('the factory must not call the backend');
  }
}
