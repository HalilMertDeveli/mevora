import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/services/app_logger.dart';

class NoopAnalyticsProvider implements AnalyticsProvider {
  const NoopAnalyticsProvider({this.logger});

  final AppLogger? logger;

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    logger?.debug('analytics:$name');
  }

  @override
  Future<void> setUserId(String? userId) async {}
}
