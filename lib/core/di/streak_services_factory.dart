import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/streak/data/callable_daily_streak_repository.dart';
import 'package:mevora/features/streak/data/streak_analytics.dart';
import 'package:mevora/features/streak/domain/repositories/daily_streak_repository.dart';
import 'package:mevora/features/streak/presentation/controllers/daily_streak_controller.dart';

class StreakServices {
  const StreakServices({required this.repository, required this.controller});

  final DailyStreakRepository repository;
  final DailyStreakController controller;
}

/// Wires the daily streak: a callable-backed repository and the controller
/// that checks in on sign-in and on resume. The app binds it to the signed-in
/// member; nothing here fires until then.
StreakServices createStreakServices({
  DailyStreakRepository? repository,
  BackendCallable? backend,
  AnalyticsProvider? analytics,
  AppLogger? logger,
}) {
  final resolved =
      repository ??
      CallableDailyStreakRepository(
        backend: backend ?? FirebaseFunctionsCallable(),
      );
  return StreakServices(
    repository: resolved,
    controller: DailyStreakController(
      repository: resolved,
      analytics: StreakAnalytics(analytics),
      logger: logger,
    ),
  );
}
