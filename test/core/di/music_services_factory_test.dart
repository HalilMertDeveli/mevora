import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/di/music_services_factory.dart';
import 'package:mevora/core/network/backend_callable.dart';

/// The music feature used to fall back to invented music when its Spotify
/// dependency was missing. An assert said so in debug; a release build said
/// nothing and showed fixtures. There is no fallback any more.
void main() {
  test('a missing Spotify dependency is an error in every environment', () {
    for (final environment in AppEnvironment.values) {
      expect(
        () => createMusicServices(
          config: AppConfig(environment: environment),
          backend: _UnusedBackend(),
        ),
        throwsStateError,
        reason: '$environment must not serve fixtures instead',
      );
    }
    expect(
      () => createMusicServices(backend: _UnusedBackend()),
      throwsStateError,
      reason: 'no config is not a reason to serve fixtures either',
    );
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
