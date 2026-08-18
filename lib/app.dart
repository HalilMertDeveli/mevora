import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/routing/app_router.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';

class MevoraApp extends StatefulWidget {
  const MevoraApp({
    super.key,
    required this.config,
    required this.logger,
    this.router,
  });

  final AppConfig config;
  final AppLogger logger;
  final GoRouter? router;

  @override
  State<MevoraApp> createState() => _MevoraAppState();
}

class _MevoraAppState extends State<MevoraApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = widget.router ?? createAppRouter(config: widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      config: widget.config,
      logger: widget.logger,
      child: MaterialApp.router(
        title: widget.config.appName,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routerConfig: _router,
        debugShowCheckedModeBanner: widget.config.showDebugBanner,
      ),
    );
  }
}
