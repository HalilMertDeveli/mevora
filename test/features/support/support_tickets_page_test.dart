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
import 'package:mevora/features/support/domain/models/support_message.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';
import 'package:mevora/features/support/presentation/pages/support_tickets_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

SupportTicket _ticket(
  String id, {
  int replies = 0,
  bool unread = false,
  DateTime? lastReplyAt,
}) {
  return SupportTicket(
    id: id,
    userId: 'self',
    category: 'account',
    subject: 'Subject $id',
    message: 'Message $id',
    attachments: const [],
    status: replies > 0
        ? SupportTicketStatus.inProgress
        : SupportTicketStatus.open,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    supportReplyCount: replies,
    hasUnreadSupportReply: unread,
    lastSupportReplyAt: lastReplyAt,
  );
}

class _ListRepository implements SupportRepository {
  _ListRepository(this.tickets);

  final List<SupportTicket> tickets;

  @override
  Stream<List<SupportTicket>> watchTickets(String userId) =>
      Stream.value(tickets);

  @override
  Stream<List<SupportMessage>> watchMessages({
    required String userId,
    required String ticketId,
  }) => Stream.value(const []);

  @override
  Future<SupportTicket?> getTicket({
    required String userId,
    required String ticketId,
  }) async => null;

  @override
  Future<SupportTicket> createTicket({
    required String userId,
    required SupportTicketDraft draft,
  }) => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, SupportRepository repository) async {
  const user = AuthUser(
    id: 'self',
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
  addTearDown(auth.dispose);
  final language = LanguageController(
    repository: LanguageRepository(local: MemoryLanguageDataSource()),
    deviceLocale: const Locale('en'),
  );
  await language.load();
  final router = GoRouter(
    initialLocation: '/tickets',
    routes: [
      GoRoute(path: '/tickets', builder: (_, _) => const SupportTicketsPage()),
    ],
  );
  await tester.pumpWidget(
    AppScope(
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
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only answered requests carry the support-replied mark', (
    tester,
  ) async {
    await _pump(
      tester,
      _ListRepository([
        _ticket('answered', replies: 1, unread: true),
        _ticket('waiting'),
        _ticket('legacy', lastReplyAt: DateTime.utc(2026, 1, 2)),
      ]),
    );

    expect(find.text('Subject answered'), findsOneWidget);
    expect(find.text('Subject waiting'), findsOneWidget);
    expect(find.text(_l10n.supportTicketRepliedBadge), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('support-replied-answered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('support-replied-legacy')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('support-replied-waiting')), findsNothing);
  });
}
