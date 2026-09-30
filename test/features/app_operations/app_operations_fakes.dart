import 'dart:async';

import 'package:mevora/features/app_operations/data/app_operations_stores.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';
import 'package:mevora/features/app_operations/presentation/controllers/app_operations_controller.dart';

/// A live document the test pushes values and errors into.
class FakeAppOperationsRepository implements AppOperationsRepository {
  StreamController<AppOperationsConfig> _controller =
      StreamController<AppOperationsConfig>.broadcast();
  int watchCalls = 0;
  bool throwOnWatch = false;

  @override
  Stream<AppOperationsConfig> watch() {
    watchCalls++;
    if (throwOnWatch) {
      throw StateError('no Firebase in tests');
    }
    if (_controller.isClosed) {
      _controller = StreamController<AppOperationsConfig>.broadcast();
    }
    return _controller.stream;
  }

  void emit(AppOperationsConfig config) => _controller.add(config);

  void fail(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();
}

class FakeAppVersionProvider implements AppVersionProvider {
  FakeAppVersionProvider({
    this.platform = AppPlatform.android,
    this.version = '1.0.1',
  });

  final AppPlatform platform;
  final String? version;

  @override
  Future<InstalledApp> installed() async =>
      InstalledApp(platform: platform, version: version);
}

AppOperationsController fakeOperationsController({
  AppOperationsConfig? cached,
  FakeAppOperationsRepository? repository,
  AppOperationsStore? store,
  String? version = '1.0.1',
  AppPlatform platform = AppPlatform.android,
  DateTime Function()? clock,
}) {
  return AppOperationsController(
    repository: repository ?? FakeAppOperationsRepository(),
    store: store ?? MemoryAppOperationsStore(config: cached),
    versionProvider: FakeAppVersionProvider(
      platform: platform,
      version: version,
    ),
    clock: clock,
  );
}
