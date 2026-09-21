import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/domain/entities/auth_providers.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';
import 'package:mevora/features/support/presentation/pages/support_ticket_detail_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

const _ownerUid = 'self';

SupportTicket _ticket({String id = 'ticket-1', String userId = _ownerUid}) {
  return SupportTicket(
    id: id,
    userId: userId,
    category: 'account',
    subject: 'Cannot upload a photo',
    message: 'The upload fails at 80%.',
    attachments: const [],
    status: SupportTicketStatus.open,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
  );
}

/// In-memory repository keyed by ticket id. Stored tickets keep their real
/// owner so ownership filtering can be exercised.
class _FakeSupportRepository implements SupportRepository {
  _FakeSupportRepository({
    Map<String, SupportTicket> tickets = const {},
    this.throwOnGet = false,
  }) : _tickets = Map.of(tickets);

  final Map<String, SupportTicket> _tickets;
  bool throwOnGet;
  int getCalls = 0;

  @override
  Stream<List<SupportTicket>> watchTickets(String userId) {
    return Stream.value([
      for (final ticket in _tickets.values)
        if (ticket.userId == userId) ticket,
    ]);
  }

  @override
  Future<SupportTicket?> getTicket({
    required String userId,
    required String ticketId,
  }) async {
    getCalls += 1;
    if (throwOnGet) {
      throw StateError('backend unavailable');
    }
    final ticket = _tickets[ticketId];
    if (ticket == null || ticket.userId != userId) {
      return null;
    }
    return ticket;
  }

  @override
  Future<SupportTicket> createTicket({
    required String userId,
    required SupportTicketDraft draft,
  }) {
    throw UnimplementedError();
  }
}

AuthController _authenticatedAuth() {
  const user = AuthUser(
    id: _ownerUid,
    email: 'ada@mevora.app',
    authProviders: AuthProviders(email: true),
  );
  final auth = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: FakeUserDocumentRepository(),
    logger: const AppLogger(environment: AppEnvironment.development),
  );
  auth.user = user;
  auth.status = const Authenticated(user);
  return auth;
}

Future<Widget> _harness({
  required AuthController auth,
  required SupportRepository repository,
  required String ticketId,
  SupportTicket? extra,
}) async {
  final language = LanguageController(
    repository: LanguageRepository(local: MemoryLanguageDataSource()),
    deviceLocale: const Locale('en'),
  );
  await language.load();
  final router = GoRouter(
    initialLocation: '/ticket',
    routes: [
      GoRoute(
        path: '/ticket',
        builder: (_, _) =>
            SupportTicketDetailPage(ticketId: ticketId, ticket: extra),
      ),
    ],
  );
  return AppScope(
    config: const AppConfig(environment: AppEnvironment.development),
    logger: const AppLogger(environment: AppEnvironment.development),
    child: LanguageScope(
      controller: language,
      child: AuthScope(
        controller: auth,
        child: SupportScope(
          repository: repository,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: language.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('router never fabricates a blank support ticket', () {
    final source = File('lib/core/routing/app_router.dart').readAsStringSync();
    expect(
      source.contains('SupportTicketDetailPage('),
      isTrue,
      reason: 'ticket detail route must still exist',
    );
    expect(
      source.contains('ticketId: ticket?.id ?? ticketId'),
      isTrue,
      reason: 'route must forward the path ticketId for deep links',
    );
    expect(
      RegExp(r'SupportTicket\(\s*[\r\n]\s*id: state\.pathParameters')
          .hasMatch(source),
      isFalse,
      reason: 'route must not construct a placeholder SupportTicket',
    );
  });

  testWidgets('renders the ticket handed over through extra without a fetch', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    final repository = _FakeSupportRepository();
    await tester.pumpWidget(
      await _harness(
        auth: auth,
        repository: repository,
        ticketId: 'ticket-1',
        extra: _ticket(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cannot upload a photo'), findsOneWidget);
    expect(find.text('The upload fails at 80%.'), findsOneWidget);
    expect(repository.getCalls, 0);
    auth.dispose();
  });

  testWidgets('resolves the ticket by id on direct navigation without extra', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    final repository = _FakeSupportRepository(tickets: {'ticket-1': _ticket()});
    await tester.pumpWidget(
      await _harness(
        auth: auth,
        repository: repository,
        ticketId: 'ticket-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.getCalls, 1);
    expect(find.text('Cannot upload a photo'), findsOneWidget);
    expect(find.byType(MevoraErrorView), findsNothing);
    auth.dispose();
  });

  testWidgets('shows a not-found state for an unknown ticket id', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    final repository = _FakeSupportRepository();
    await tester.pumpWidget(
      await _harness(
        auth: auth,
        repository: repository,
        ticketId: 'missing-ticket',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.supportTicketNotFoundTitle), findsOneWidget);
    expect(find.text(_l10n.supportTicketNotFoundMessage), findsOneWidget);
    // A fabricated ticket would have rendered blank subject/message rows.
    expect(find.text(_l10n.supportTicketSubject), findsNothing);
    auth.dispose();
  });

  testWidgets('shows a not-found state for a ticket owned by someone else', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    final repository = _FakeSupportRepository(
      tickets: {'ticket-9': _ticket(id: 'ticket-9', userId: 'other-user')},
    );
    await tester.pumpWidget(
      await _harness(
        auth: auth,
        repository: repository,
        ticketId: 'ticket-9',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.supportTicketNotFoundTitle), findsOneWidget);
    expect(find.text('Cannot upload a photo'), findsNothing);
    auth.dispose();
  });

  testWidgets('backend failure shows a retryable error, not a blank ticket', (
    tester,
  ) async {
    final auth = _authenticatedAuth();
    final repository = _FakeSupportRepository(
      tickets: {'ticket-1': _ticket()},
      throwOnGet: true,
    );
    await tester.pumpWidget(
      await _harness(
        auth: auth,
        repository: repository,
        ticketId: 'ticket-1',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.somethingWentWrong), findsOneWidget);
    expect(find.text(_l10n.supportTicketNotFoundTitle), findsNothing);

    repository.throwOnGet = false;
    await tester.tap(find.text(_l10n.retry));
    await tester.pumpAndSettle();

    expect(find.text('Cannot upload a photo'), findsOneWidget);
    auth.dispose();
  });
}
