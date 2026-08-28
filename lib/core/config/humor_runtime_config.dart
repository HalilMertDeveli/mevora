import 'package:flutter/foundation.dart';
import 'package:mevora/core/config/app_environment.dart';

/// Resolves whether Humor Lab should use [MockHumorDataSource].
///
/// Priority:
/// 1. `--dart-define=USE_MOCK_HUMOR=true|false`
/// 2. Debug **development** builds → mock (local UI safety)
/// 3. Staging / production / QA release → real Cloud Functions
bool resolveUseMockHumor(
  AppEnvironment environment, {
  @visibleForTesting bool debugMode = kDebugMode,
  @visibleForTesting String forcedMockHumor = const String.fromEnvironment(
    'USE_MOCK_HUMOR',
    defaultValue: '',
  ),
}) {
  if (forcedMockHumor == 'true') {
    return true;
  }
  if (forcedMockHumor == 'false') {
    return false;
  }
  return debugMode && environment.isDevelopment;
}

/// Resolves whether Humor Lab surfaces are enabled at bootstrap.
///
/// Priority:
/// 1. `--dart-define=HUMOR_LAB_ENABLED=true|false`
/// 2. Debug development → ON (device QA)
/// 3. Staging → ON (QA / pre-prod)
/// 4. Production → OFF until Remote Config enables (`humorLabEnabled` OR merge)
bool resolveHumorLabEnabled(
  AppEnvironment environment, {
  @visibleForTesting bool debugMode = kDebugMode,
  @visibleForTesting String forcedHumorLab = const String.fromEnvironment(
    'HUMOR_LAB_ENABLED',
    defaultValue: '',
  ),
}) {
  if (forcedHumorLab == 'true') {
    return true;
  }
  if (forcedHumorLab == 'false') {
    return false;
  }
  if (environment.isDevelopment && debugMode) {
    return true;
  }
  if (environment == AppEnvironment.staging) {
    return true;
  }
  return false;
}
