import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/di/social_services_factory.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/chat/presentation/controllers/chat_controller.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/safety/domain/models/report_reason.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';
import 'package:mevora/features/safety/presentation/pages/report_page.dart';
import 'package:mevora/features/safety/presentation/widgets/chat_more_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Members must be able to report a child-safety concern from inside the app
/// (sexual content or behaviour involving a minor). The reason has to be
/// offered in both languages with wording nobody can mistake, sit at the top
/// of the list, and reach the server as `child_safety`.
const _childSafetyEn =
    'Child safety concern (sexual content or behaviour involving a minor)';
const _childSafetyTr =
    'Çocuk güvenliği (reşit olmayan birini içeren cinsel içerik veya davranış)';

class _ReportCall {
  const _ReportCall({
    required this.userId,
    required this.reason,
    this.matchId,
    this.messageId,
    this.description,
  });

  final String userId;
  final String reason;
  final String? matchId;
  final String? messageId;
  final String? description;
}

/// Records exactly what the page hands to the repository; the string in
/// `reason` is what the reportUser callable receives.
class _RecordingSafetyRepository implements SafetyRepository {
  final reports = <_ReportCall>[];

  @override
  Future<void> reportUser({
    required String userId,
    required String reason,
    String? matchId,
    String? messageId,
    String? description,
  }) async {
    reports.add(
      _ReportCall(
        userId: userId,
        reason: reason,
        matchId: matchId,
        messageId: messageId,
        description: description,
      ),
    );
  }

  /// What the next block calls fail with, in order; once empty they succeed.
  final blockFailures = <Object>[];
  var blockCalls = 0;

  @override
  Future<void> blockUser({required String userId, String? matchId}) async {
    blockCalls += 1;
    if (blockFailures.isNotEmpty) {
      throw blockFailures.removeAt(0);
    }
  }

  @override
  Future<void> unmatch({required String matchId}) async {}

  @override
  Future<bool> isBlockedPair(String uidA, String uidB) async => false;

  @override
  Stream<Set<String>> watchBlockedUserIds(String uid) => const Stream.empty();
}

SocialServices _servicesWith(SafetyRepository safety) {
  final base = createGraphSocialServices(
    graph: InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12)),
    uidSource: MutableAuthUidSource('aya'),
  );
  return SocialServices(
    uidSource: base.uidSource,
    matchRepository: base.matchRepository,
    likeRepository: base.likeRepository,
    chatRepository: base.chatRepository,
    safetyRepository: safety,
    presenceRepository: base.presenceRepository,
    callRepository: base.callRepository,
    videoCallService: base.videoCallService,
    videoCallProvider: base.videoCallProvider,
    notificationRepository: base.notificationRepository,
    discoveryExclusion: base.discoveryExclusion,
    incomingLikesRepository: base.incomingLikesRepository,
  );
}

Future<void> _pumpReportPage(
  WidgetTester tester, {
  required Locale locale,
  required SafetyRepository safety,
  Size size = const Size(390, 844),
  String? matchId,
  String? messageId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    SocialScope(
      services: _servicesWith(safety),
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: ReportPage(userId: 'can', matchId: matchId, messageId: messageId),
      ),
    ),
  );
  await tester.pump();
}

/// The report page opened on top of another page, the way the app opens it,
/// so that leaving it is something a test can see.
Future<void> _pumpReportPageOverHome(
  WidgetTester tester, {
  required SafetyRepository safety,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'report',
            builder: (context, state) =>
                const ReportPage(userId: 'can', matchId: 'match-1'),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    SocialScope(
      services: _servicesWith(safety),
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: router,
      ),
    ),
  );
  router.go('/report');
  await tester.pumpAndSettle();
}

List<String> _reasonLabelsInOrder(WidgetTester tester) {
  return tester
      .widgetList<RadioListTile<ReportReason>>(
        find.byType(RadioListTile<ReportReason>),
      )
      .map((tile) => (tile.title! as Text).data!)
      .toList();
}

Future<void> _submit(WidgetTester tester, AppLocalizations l10n) async {
  final submit = find.text(l10n.submitReport);
  await tester.ensureVisible(submit);
  await tester.pump();
  await tester.tap(submit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tr = lookupAppLocalizations(const Locale('tr'));

  group('child safety report reason', () {
    test('maps to the server value child_safety', () {
      expect(ReportReason.childSafety.firestoreValue, 'child_safety');
      expect(
        ReportReason.values.where((r) => r.firestoreValue == 'child_safety'),
        [ReportReason.childSafety],
      );
    });

    test('is worded explicitly in English and Turkish', () {
      expect(en.reportChildSafety, _childSafetyEn);
      expect(tr.reportChildSafety, _childSafetyTr);
      expect(reportReasonLabel(en, ReportReason.childSafety), _childSafetyEn);
      expect(reportReasonLabel(tr, ReportReason.childSafety), _childSafetyTr);
    });

    test('leads the list, directly above the underage reason', () {
      expect(ReportReason.values.first, ReportReason.childSafety);
      expect(ReportReason.values[1], ReportReason.underage);
    });

    testWidgets('report page lists it first in English', (tester) async {
      await _pumpReportPage(
        tester,
        locale: const Locale('en'),
        safety: _RecordingSafetyRepository(),
      );

      expect(find.text(_childSafetyEn), findsOneWidget);
      final labels = _reasonLabelsInOrder(tester);
      expect(labels.first, _childSafetyEn);
      expect(labels[1], en.reportUnderage);
      expect(labels, hasLength(ReportReason.values.length));
    });

    testWidgets('report page lists it first in Turkish', (tester) async {
      await _pumpReportPage(
        tester,
        locale: const Locale('tr'),
        safety: _RecordingSafetyRepository(),
      );

      expect(find.text(_childSafetyTr), findsOneWidget);
      final labels = _reasonLabelsInOrder(tester);
      expect(labels.first, _childSafetyTr);
      expect(labels[1], tr.reportUnderage);
    });

    for (final (locale, label) in [
      (const Locale('en'), _childSafetyEn),
      (const Locale('tr'), _childSafetyTr),
    ]) {
      testWidgets(
        'the full wording is readable on a small phone (${locale.languageCode})',
        (tester) async {
          await _pumpReportPage(
            tester,
            locale: locale,
            safety: _RecordingSafetyRepository(),
            size: const Size(320, 568),
          );

          // Nothing is cut off with an ellipsis: every line of the label is
          // laid out.
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.widgetWithText(RadioListTile<ReportReason>, label),
              matching: find.byType(RichText),
            ),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('choosing it submits child_safety (English)', (tester) async {
      final safety = _RecordingSafetyRepository();
      await _pumpReportPage(
        tester,
        locale: const Locale('en'),
        safety: safety,
        matchId: 'match-1',
        messageId: 'message-1',
      );

      await tester.tap(find.text(_childSafetyEn));
      await tester.pump();
      await _submit(tester, en);

      expect(safety.reports, hasLength(1));
      expect(safety.reports.single.reason, 'child_safety');
      expect(safety.reports.single.userId, 'can');
      expect(safety.reports.single.matchId, 'match-1');
      expect(safety.reports.single.messageId, 'message-1');
      expect(find.text(en.reportThanks), findsOneWidget);
    });

    testWidgets('choosing it submits child_safety (Turkish)', (tester) async {
      final safety = _RecordingSafetyRepository();
      await _pumpReportPage(tester, locale: const Locale('tr'), safety: safety);

      await tester.tap(find.text(_childSafetyTr));
      await tester.pump();
      await _submit(tester, tr);

      expect(safety.reports.single.reason, 'child_safety');
      expect(find.text(tr.reportThanks), findsOneWidget);
    });

    testWidgets('it is never the pre-selected reason', (tester) async {
      final safety = _RecordingSafetyRepository();
      await _pumpReportPage(tester, locale: const Locale('en'), safety: safety);

      await _submit(tester, en);

      // A report sent without choosing must not arrive as a critical one.
      expect(safety.reports.single.reason, 'spam');
    });

    test(
      'the in-memory graph keeps the reason instead of filing it as other',
      () {
        final graph = InMemorySocialGraph(now: () => DateTime(2026, 1, 1, 12));
        graph.report(actorUid: 'aya', userId: 'can', reason: 'child_safety');
        expect(graph.reports.single.reason, ReportReason.childSafety);
      },
    );
  });

  group('blocking after a report', () {
    testWidgets('a block that fails is said and can be tried again', (
      tester,
    ) async {
      // Found on a real phone: the block call timed out, nothing was shown
      // and the page sat on the filled form with "Submit report" live again.
      final safety = _RecordingSafetyRepository()
        ..blockFailures.add(StateError('no connection'));
      await _pumpReportPageOverHome(tester, safety: safety);

      await _submit(tester, en);
      await tester.tap(find.text(en.block));
      await tester.pumpAndSettle();

      expect(safety.blockCalls, 1);
      expect(find.text(en.blockFailedMessage), findsOneWidget);
      expect(find.text('home'), findsNothing);

      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();

      expect(safety.blockCalls, 2);
      expect(safety.reports, hasLength(1));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('giving up after a failed block does not report twice', (
      tester,
    ) async {
      final safety = _RecordingSafetyRepository()
        ..blockFailures.add(StateError('no connection'));
      await _pumpReportPageOverHome(tester, safety: safety);

      await _submit(tester, en);
      await tester.tap(find.text(en.block));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.cancel));
      await tester.pumpAndSettle();

      expect(safety.reports, hasLength(1));
      expect(safety.blockCalls, 1);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a block that works leaves the page without a second prompt', (
      tester,
    ) async {
      final safety = _RecordingSafetyRepository();
      await _pumpReportPageOverHome(tester, safety: safety);

      await _submit(tester, en);
      await tester.tap(find.text(en.block));
      await tester.pumpAndSettle();

      expect(safety.blockCalls, 1);
      expect(find.text(en.blockFailedMessage), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('blocking from the chat menu', () {
    testWidgets('a block that fails is said', (tester) async {
      final safety = _RecordingSafetyRepository()
        ..blockFailures.add(StateError('no connection'));
      final services = _servicesWith(safety);
      final controller = ChatController(
        matchId: 'match-1',
        chatRepository: services.chatRepository,
        matchRepository: services.matchRepository,
        safetyRepository: safety,
        presenceRepository: services.presenceRepository,
        uidSource: services.uidSource,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        SocialScope(
          services: services,
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showChatMoreSheet(context, controller: controller),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // The sheet's Block action, then the confirm dialog's Block button.
      await tester.tap(find.text(en.block));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.block));
      await tester.pumpAndSettle();

      expect(safety.blockCalls, 1);
      expect(find.text(en.blockFailedMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
