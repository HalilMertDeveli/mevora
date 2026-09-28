import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/feature_flags.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_profile_display.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_chat_starter_chip.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_badge.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_sheet.dart';
import 'package:mevora/features/humor/presentation/widgets/match_humor_compatibility_banner.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));

/// Only the compatibility call is real; anything else fails loudly.
class _FakeHumorRepository implements HumorRepository {
  _FakeHumorRepository(this._respond);

  final Future<Result<HumorCompatibility>> Function() _respond;
  final requested = <String>[];

  @override
  Future<Result<HumorCompatibility>> getMatchCompatibility(String matchId) {
    requested.add(matchId);
    return _respond();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _RecordingAnalytics implements AnalyticsProvider {
  final events = <(String, Map<String, Object>?)>[];

  List<String> get names => [for (final e in events) e.$1];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

const _available = HumorCompatibility(
  available: true,
  score: 82,
  strongestShared: [HumorCategory.absurd, HumorCategory.dark],
);

Future<Result<HumorCompatibility>> _ok(HumorCompatibility value) async =>
    Success(value);

Widget _host(
  Widget child, {
  HumorRepository? repository,
  bool humorLabEnabled = true,
}) {
  const environment = AppEnvironment.development;
  Widget app = MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('tr'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: Column(children: [child])),
  );
  if (repository != null) {
    app = HumorScope(repository: repository, child: app);
  }
  return AppScope(
    config: AppConfig(
      environment: environment,
      featureFlags: FeatureFlags(humorLabEnabled: humorLabEnabled),
    ),
    logger: const AppLogger(environment: environment),
    child: app,
  );
}

/// Any digit on screen would be a number the UI promised not to show.
Finder _anyDigits() => find.byWidgetPredicate(
  (widget) => widget is Text && RegExp(r'\d').hasMatch(widget.data ?? ''),
);

void main() {
  group('MatchHumorCompatibilityBanner', () {
    testWidgets('available: shows the coarse badge, logs viewed once', (
      tester,
    ) async {
      final repository = _FakeHumorRepository(() => _ok(_available));
      final analytics = _RecordingAnalytics();

      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(matchId: 'm_1', analytics: analytics),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.requested, ['m_1']);
      expect(find.byType(HumorCompatibilityBadge), findsOneWidget);
      expect(find.text(_tr.humorCompatibilityLevelHigh), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(_anyDigits(), findsNothing);
      // Not offered unless the chat asks for it.
      expect(find.byType(HumorChatStarterChip), findsNothing);

      expect(analytics.names, [AnalyticsEvents.humorCompatibilityViewed]);
      final params = analytics.events.single.$2!;
      expect(params, {'surface': 'chat', 'level': 'high', 'shared_count': 2});
      for (final value in params.values) {
        expect(value is String || value is num, isTrue);
      }

      // Rebuilds do not refetch or relog.
      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(matchId: 'm_1', analytics: analytics),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.requested, hasLength(1));
      expect(analytics.events, hasLength(1));
    });

    testWidgets('tapping the badge opens the sheet with localised styles', (
      tester,
    ) async {
      final repository = _FakeHumorRepository(() => _ok(_available));

      await tester.pumpWidget(
        _host(
          const MatchHumorCompatibilityBanner(matchId: 'm_1'),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(HumorCompatibilityBadge));
      await tester.pumpAndSettle();

      final sheet = find.byType(HumorCompatibilitySheet);
      expect(sheet, findsOneWidget);
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      expect(
        inSheet(find.text(_tr.humorCompatibilityLevelHigh)),
        findsOneWidget,
      );
      expect(
        inSheet(find.text(_tr.humorCompatibilitySharedStyles)),
        findsOneWidget,
      );
      expect(
        inSheet(
          find.text(
            HumorProfileDisplay.categoryLabel(_tr, HumorCategory.absurd),
          ),
        ),
        findsOneWidget,
      );
      expect(
        inSheet(
          find.text(HumorProfileDisplay.categoryLabel(_tr, HumorCategory.dark)),
        ),
        findsOneWidget,
      );
      expect(inSheet(find.text(_tr.humorCompatibilityNote)), findsOneWidget);
      // Raw API keys and numbers never reach the user.
      expect(inSheet(find.text('absurd')), findsNothing);
      expect(inSheet(find.text('dark')), findsNothing);
      expect(inSheet(_anyDigits()), findsNothing);
    });

    testWidgets('moderate and low scores read as their buckets', (
      tester,
    ) async {
      for (final (score, label) in [
        (55, _tr.humorCompatibilityLevelMedium),
        (20, _tr.humorCompatibilityLevelLow),
      ]) {
        await tester.pumpWidget(
          _host(
            MatchHumorCompatibilityBanner(
              key: ValueKey(score),
              matchId: 'm_$score',
            ),
            repository: _FakeHumorRepository(
              () => _ok(
                HumorCompatibility(
                  available: true,
                  score: score,
                  strongestShared: const [HumorCategory.meme],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(_anyDigits(), findsNothing);
      }
    });

    testWidgets('building: one quiet line, nothing else', (tester) async {
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(
            matchId: 'm_1',
            analytics: analytics,
            showChatStarter: true,
            onChatStarter: (_) {},
          ),
          repository: _FakeHumorRepository(
            () => _ok(
              const HumorCompatibility(
                available: false,
                reason: HumorCompatibility.reasonBuilding,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_tr.humorCompatibilityBuilding), findsOneWidget);
      expect(find.byType(HumorCompatibilityBadge), findsNothing);
      expect(find.byType(HumorChatStarterChip), findsNothing);
      expect(analytics.events, isEmpty);
    });

    testWidgets('no-signal and invalid-match render nothing', (tester) async {
      for (final reason in [
        HumorCompatibility.reasonNoSignal,
        HumorCompatibility.reasonInvalidMatch,
      ]) {
        await tester.pumpWidget(
          _host(
            MatchHumorCompatibilityBanner(
              key: ValueKey(reason),
              matchId: 'm_1',
            ),
            repository: _FakeHumorRepository(
              () => _ok(HumorCompatibility(available: false, reason: reason)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Text), findsNothing, reason: reason);
      }
    });

    testWidgets('loading renders nothing', (tester) async {
      final pending = Completer<Result<HumorCompatibility>>();
      await tester.pumpWidget(
        _host(
          const MatchHumorCompatibilityBanner(matchId: 'm_1'),
          repository: _FakeHumorRepository(() => pending.future),
        ),
      );
      await tester.pump();

      expect(find.byType(Text), findsNothing);
      pending.complete(const Success(HumorCompatibility.unavailable));
      await tester.pumpAndSettle();
    });

    testWidgets('an error renders nothing', (tester) async {
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(matchId: 'm_1', analytics: analytics),
          repository: _FakeHumorRepository(
            () async => const Err(NetworkFailure('offline')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
      expect(analytics.events, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a throwing repository renders nothing', (tester) async {
      await tester.pumpWidget(
        _host(
          const MatchHumorCompatibilityBanner(matchId: 'm_1'),
          repository: _FakeHumorRepository(
            () async => throw StateError('boom'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('flag off: renders nothing and never calls the backend', (
      tester,
    ) async {
      final repository = _FakeHumorRepository(() => _ok(_available));
      await tester.pumpWidget(
        _host(
          const MatchHumorCompatibilityBanner(matchId: 'm_1'),
          repository: repository,
          humorLabEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
      expect(repository.requested, isEmpty);
    });

    testWidgets('no HumorScope: renders nothing', (tester) async {
      await tester.pumpWidget(
        _host(const MatchHumorCompatibilityBanner(matchId: 'm_1')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Text), findsNothing);
    });
  });

  group('humor chat starter', () {
    testWidgets('offered with shared styles; tap hands over the text only', (
      tester,
    ) async {
      final analytics = _RecordingAnalytics();
      final used = <String>[];
      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(
            matchId: 'm_1',
            analytics: analytics,
            showChatStarter: true,
            onChatStarter: used.add,
          ),
          repository: _FakeHumorRepository(() => _ok(_available)),
        ),
      );
      await tester.pumpAndSettle();

      // Keyed on the first (strongest) shared style.
      final text = _tr.humorChatStarterAbsurd;
      expect(find.byType(HumorChatStarterChip), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      expect(analytics.names, [
        AnalyticsEvents.humorCompatibilityViewed,
        AnalyticsEvents.humorChatStarterShown,
      ]);

      await tester.tap(find.text(text));
      await tester.pumpAndSettle();

      expect(used, [text]);
      expect(analytics.names.last, AnalyticsEvents.humorChatStarterUsed);
      expect(analytics.events.last.$2, {'category': 'absurd'});
    });

    testWidgets('not offered without shared styles', (tester) async {
      await tester.pumpWidget(
        _host(
          MatchHumorCompatibilityBanner(
            matchId: 'm_1',
            showChatStarter: true,
            onChatStarter: (_) {},
          ),
          repository: _FakeHumorRepository(
            () => _ok(const HumorCompatibility(available: true, score: 64)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HumorCompatibilityBadge), findsOneWidget);
      expect(find.byType(HumorChatStarterChip), findsNothing);
    });

    testWidgets('not offered once the chat is no longer empty', (tester) async {
      final repository = _FakeHumorRepository(() => _ok(_available));
      Widget banner({required bool empty}) => _host(
        MatchHumorCompatibilityBanner(
          matchId: 'm_1',
          showChatStarter: empty,
          onChatStarter: (_) {},
        ),
        repository: repository,
      );

      await tester.pumpWidget(banner(empty: true));
      await tester.pumpAndSettle();
      expect(find.byType(HumorChatStarterChip), findsOneWidget);

      await tester.pumpWidget(banner(empty: false));
      await tester.pumpAndSettle();
      expect(find.byType(HumorChatStarterChip), findsNothing);
      expect(find.byType(HumorCompatibilityBadge), findsOneWidget);
    });

    test('every category has its own template, with a generic fallback', () {
      for (final l10n in [_tr, lookupAppLocalizations(const Locale('en'))]) {
        final texts = {
          for (final category in HumorCategory.values)
            HumorChatStarterChip.starterText(l10n, category),
        };
        expect(texts, hasLength(HumorCategory.values.length));
        final generic = HumorChatStarterChip.starterText(l10n, null);
        expect(generic, l10n.humorChatStarter);
        expect(texts, isNot(contains(generic)));
        for (final text in [...texts, generic]) {
          expect(text.trim(), isNotEmpty);
          expect(RegExp(r'\d').hasMatch(text), isFalse);
        }
      }
    });
  });
}
