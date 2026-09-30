import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/identity/account_status.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/moderation_status/presentation/pages/account_restricted_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/l10n_harness.dart';

final _l10n = l10nEn();

const _active = AuthUser(
  id: 'user-1',
  email: 'ada@mevora.app',
  profileCompleted: true,
  onboardingCompleted: true,
);

Widget _placeholder(String label) => Scaffold(body: Center(child: Text(label)));

/// The real redirect rules over stand-in pages, driven by the real
/// AuthController listening to a fake account stream.
Future<FakeAuthRepository> _pumpApp(
  WidgetTester tester, {
  required AuthUser user,
}) async {
  final repository = FakeAuthRepository(user: user);
  final auth = AuthController(
    authRepository: repository,
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: const AppLogger(environment: AppEnvironment.development),
  );
  addTearDown(() {
    auth.dispose();
    repository.dispose();
  });
  auth.start();
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: auth,
    redirect: (context, state) => AuthRedirector.redirect(
      status: auth.status,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => _placeholder('splash'),
      ),
      GoRoute(path: AppRoutes.login, builder: (_, _) => _placeholder('login')),
      GoRoute(
        path: AppRoutes.discovery,
        builder: (_, _) => _placeholder('discovery'),
      ),
      GoRoute(
        path: AppRoutes.accountRestricted,
        builder: (_, _) => const AccountRestrictedPage(),
      ),
      GoRoute(
        path: AppRoutes.moderationStatus,
        builder: (_, _) => _placeholder('moderation status'),
      ),
      GoRoute(
        path: AppRoutes.supportCenter,
        builder: (_, _) => _placeholder('support center'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('a suspended member lands on the restricted screen', (
    tester,
  ) async {
    final until = DateTime.utc(2030, 1, 1, 12);
    await _pumpApp(
      tester,
      user: _active.copyWith(
        isActive: false,
        accountStatus: AccountStatus.suspended,
        suspendedUntil: until,
      ),
    );

    expect(find.text(_l10n.accountRestrictedHeadline), findsOneWidget);
    expect(find.text('discovery'), findsNothing);
    final context = tester.element(find.byType(AccountRestrictedPage));
    final material = MaterialLocalizations.of(context);
    final local = until.toLocal();
    expect(
      find.text(
        _l10n.accountRestrictedUntil(
          '${material.formatMediumDate(local)} '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('restricted-why')));
    await tester.pumpAndSettle();
    expect(find.text('moderation status'), findsOneWidget);
  });

  testWidgets('an open-ended suspension says it lasts until review', (
    tester,
  ) async {
    await _pumpApp(
      tester,
      user: _active.copyWith(
        isActive: false,
        accountStatus: AccountStatus.suspended,
      ),
    );

    expect(find.text(_l10n.accountRestrictedOpenEnded), findsOneWidget);
    await tester.tap(find.text(_l10n.accountRestrictedContactSupport));
    await tester.pumpAndSettle();
    expect(find.text('support center'), findsOneWidget);
  });

  testWidgets('restoring the account releases the member automatically', (
    tester,
  ) async {
    final repository = await _pumpApp(
      tester,
      user: _active.copyWith(
        isActive: false,
        accountStatus: AccountStatus.suspended,
      ),
    );
    expect(find.text(_l10n.accountRestrictedHeadline), findsOneWidget);

    // Staff restore: users/{uid} flips back to active.
    repository.emit(_active);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.accountRestrictedHeadline), findsNothing);
    expect(find.text('discovery'), findsOneWidget);
    expect(repository.signOutCalls, 0);
  });
}
