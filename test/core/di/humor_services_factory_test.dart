import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/di/humor_services_factory.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';

/// Records callable names and answers getHumorFeed with an empty page.
class _RecordingBackend implements BackendCallable {
  final List<String> calls = <String>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add(name);
    return <String, dynamic>{
      'items': <Object?>[],
      'nextCursor': null,
      'catalogEmpty': true,
    };
  }
}

void main() {
  group('resolveUseMockHumor', () {
    test('an unset define never selects the mock, in any environment', () {
      for (final environment in AppEnvironment.values) {
        expect(
          resolveUseMockHumor(
            define: '',
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: environment.name,
        );
      }
    });

    test('only the exact value "true" opts in', () {
      for (final define in <String>[
        'false',
        '1',
        'yes',
        'TRUE',
        'True',
        ' true',
        'true ',
      ]) {
        expect(
          resolveUseMockHumor(
            define: define,
            environment: AppEnvironment.development,
            releaseMode: false,
          ),
          isFalse,
          reason: 'define "$define"',
        );
      }
    });

    test('USE_MOCK_HUMOR=true selects the mock in a development build', () {
      expect(
        resolveUseMockHumor(
          define: 'true',
          environment: AppEnvironment.development,
          releaseMode: false,
        ),
        isTrue,
      );
    });

    test('staging and production ignore USE_MOCK_HUMOR=true', () {
      for (final environment in <AppEnvironment>[
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        expect(
          resolveUseMockHumor(
            define: 'true',
            environment: environment,
            releaseMode: false,
          ),
          isFalse,
          reason: environment.name,
        );
      }
    });

    test(
      'a release build ignores USE_MOCK_HUMOR=true, even in development',
      () {
        for (final environment in AppEnvironment.values) {
          expect(
            resolveUseMockHumor(
              define: 'true',
              environment: environment,
              releaseMode: true,
            ),
            isFalse,
            reason: environment.name,
          );
        }
      },
    );
  });

  group('createHumorServices', () {
    const development = AppConfig(environment: AppEnvironment.development);

    Future<List<String>> feedCalls(
      HumorServices services,
      _RecordingBackend backend,
    ) async {
      final result = await services.repository.getFeed();
      expect(result.isSuccess, isTrue);
      return backend.calls;
    }

    test('without the define (as in CI) a development build uses the '
        'backend', () async {
      final backend = _RecordingBackend();
      final services = createHumorServices(
        config: development,
        backend: backend,
      );

      expect(await feedCalls(services, backend), <String>['getHumorFeed']);
    });

    test('an unset define uses the backend in every environment', () async {
      for (final environment in AppEnvironment.values) {
        final backend = _RecordingBackend();
        final services = createHumorServices(
          config: AppConfig(environment: environment),
          backend: backend,
          useMockHumorDefine: '',
        );

        expect(await feedCalls(services, backend), <String>[
          'getHumorFeed',
        ], reason: environment.name);
      }
    });

    test('USE_MOCK_HUMOR=true is ignored outside development', () async {
      for (final environment in <AppEnvironment>[
        AppEnvironment.staging,
        AppEnvironment.production,
      ]) {
        final backend = _RecordingBackend();
        final services = createHumorServices(
          config: AppConfig(environment: environment),
          backend: backend,
          useMockHumorDefine: 'true',
        );

        expect(await feedCalls(services, backend), <String>[
          'getHumorFeed',
        ], reason: environment.name);
      }
    });

    test('a missing config counts as production and never mocks', () async {
      final backend = _RecordingBackend();
      final services = createHumorServices(
        backend: backend,
        useMockHumorDefine: 'true',
      );

      expect(await feedCalls(services, backend), <String>['getHumorFeed']);
    });

    test(
      'USE_MOCK_HUMOR=true in development uses the in-memory mock',
      () async {
        final backend = _RecordingBackend();
        final services = createHumorServices(
          config: development,
          backend: backend,
          useMockHumorDefine: 'true',
        );

        final page = (await services.repository.getFeed()).valueOrNull;

        expect(backend.calls, isEmpty);
        expect(page, isNotNull);
        expect(page!.items, isNotEmpty);
      },
    );

    test('an injected repository always wins', () {
      final injected = HumorRepositoryImpl(dataSource: MockHumorDataSource());
      final backend = _RecordingBackend();

      for (final define in <String>['', 'true']) {
        final services = createHumorServices(
          config: development,
          backend: backend,
          repository: injected,
          useMockHumorDefine: define,
        );

        expect(identical(services.repository, injected), isTrue);
      }
      expect(backend.calls, isEmpty);
    });
  });
}
