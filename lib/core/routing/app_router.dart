import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/presentation/pages/design_system_page.dart';
import 'package:mevora/core/routing/app_routes.dart';

GoRouter createAppRouter({required AppConfig config}) {
  return GoRouter(
    initialLocation: AppRoutes.root,
    routes: [
      GoRoute(
        path: AppRoutes.root,
        builder: (context, state) => DesignSystemPage(config: config),
      ),
    ],
  );
}
