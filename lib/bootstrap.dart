import 'package:flutter/material.dart';
import 'package:mevora/app.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/errors/error_handler.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/firebase/firebase_bootstrap.dart';
import 'package:mevora/core/services/firebase/firebase_crash_reporter.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';

Future<void> bootstrap(AppEnvironment environment) async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig(environment: environment);
  final logger = AppLogger(environment: environment);

  await FirebaseBootstrap(logger: logger).initialize(config);

  ErrorHandler.register(
    logger: logger,
    crashReporter: const FirebaseCrashReporter(),
  );
  ErrorWidget.builder = (details) {
    return Theme(
      data: AppTheme.light(),
      child: const MevoraErrorView(),
    );
  };

  logger.info('Starting ${config.appName}');
  runApp(MevoraApp(config: config, logger: logger));
}
