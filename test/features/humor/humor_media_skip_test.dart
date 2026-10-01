import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/functions_humor_data_source.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/presentation/controllers/humor_controller.dart';
import 'package:mevora/features/humor/presentation/pages/humor_lab_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_network_images.dart';
import '../../helpers/l10n_harness.dart';

class _FakeBackend implements BackendCallable {
  _FakeBackend(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<Map<String, dynamic>> payloads = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? payload,
  ]) async {
    payloads.add(payload ?? const <String, dynamic>{});
    return responses[name] ?? const <String, dynamic>{};
  }
}

class _RecordingAnalytics implements AnalyticsProvider {
  final events = <(String, Map<String, Object>?)>[];

  Iterable<String> get names => events.map((e) => e.$1);

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add((name, parameters));
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

Map<String, dynamic> _feedItem(String id, Object? attribution) => {
  'contentId': id,
  'type': 'video',
  'language': 'tr',
  'category': 'meme',
  'media': {'downloadUrl': 'https://media.example.test/$id.mp4'},
  'attribution': attribution,
};

/// Rate [count] catalog items directly on the backend, as another session.
Future<void> _preRate(MockHumorDataSource source, int count) async {
  for (final contentId in source.sequenceIds.take(count)) {
    await source.submitFeedback(
      contentId: contentId,
      rating: HumorRating.funny,
    );
  }
}

void main() {
  group('attribution (contract K1)', () {
    test('parses a full provider credit and survives calibration tagging', () {
      final parsed = HumorContentAttribution.tryParse({
        'provider': 'giphy',
        'displayName': 'Funny Person',
        'username': 'funnyperson',
        'sourceUrl': 'https://giphy.com/gifs/abc',
        'verified': true,
      });

      expect(parsed, isNotNull);
      expect(parsed!.provider, 'giphy');
      expect(parsed.displayName, 'Funny Person');
      expect(parsed.username, 'funnyperson');
      expect(parsed.sourceUrl, 'https://giphy.com/gifs/abc');
      expect(parsed.verified, isTrue);
      expect(parsed.label, 'GIPHY · @funnyperson');

      final item = HumorContent(
        contentId: 'g1',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.meme,
        attribution: parsed,
      ).copyWithCalibrationStage(HumorCalibrationStage.anchor);
      expect(item.attribution, same(parsed));
      expect(item.calibrationStage, HumorCalibrationStage.anchor);
    });

    test('null, unknown or malformed attribution degrades safely', () {
      expect(HumorContentAttribution.tryParse(null), isNull);
      expect(HumorContentAttribution.tryParse('giphy'), isNull);
      expect(HumorContentAttribution.tryParse(<String, dynamic>{}), isNull);
      expect(HumorContentAttribution.tryParse({'provider': '  '}), isNull);
      expect(HumorContentAttribution.tryParse({'provider': 7}), isNull);

      final sparse = HumorContentAttribution.tryParse({
        'provider': 'giphy',
        'displayName': 42,
        'username': '',
        'sourceUrl': 'javascript:alert(1)',
        'verified': 'yes',
      })!;
      expect(sparse.displayName, isNull);
      expect(sparse.username, isNull);
      expect(sparse.sourceUrl, isNull, reason: 'only http(s) links are kept');
      expect(sparse.verified, isFalse);
      expect(sparse.label, 'GIPHY');

      final named = HumorContentAttribution.tryParse({
        'provider': 'someprovider',
        'displayName': 'Studio',
      })!;
      expect(named.label, 'someprovider · Studio');
    });

    test('the feed parser attaches attribution per item', () async {
      final backend = _FakeBackend({
        'getHumorFeed': {
          'items': [
            _feedItem('giphy-1', {
              'provider': 'giphy',
              'displayName': null,
              'username': 'maker',
              'sourceUrl': null,
              'verified': false,
            }),
            _feedItem('curated-1', null),
            _feedItem('odd-1', ['not', 'a', 'map']),
          ],
        },
      });
      final page = await FunctionsHumorDataSource(backend: backend).getFeed();

      expect(page.items.map((i) => i.contentId), [
        'giphy-1',
        'curated-1',
        'odd-1',
      ]);
      expect(page.items[0].attribution?.label, 'GIPHY · @maker');
      expect(page.items[1].attribution, isNull);
      expect(page.items[2].attribution, isNull);
    });

    test('curated text content (contract K2) parses as a text card', () async {
      final backend = _FakeBackend({
        'getHumorFeed': {
          'items': [
            {
              'contentId': 'mevora-1',
              'type': 'text',
              'language': 'tr',
              'category': 'wordplay',
              'media': {'textBody': 'Kahve olmadan ben ben değilim.'},
              'attribution': null,
            },
          ],
        },
      });
      final page = await FunctionsHumorDataSource(backend: backend).getFeed();
      final item = page.items.single;

      expect(item.type, HumorContentType.text);
      expect(item.hasText, isTrue);
      expect(item.hasMedia, isFalse);
      expect(item.attribution, isNull);
    });
  });

  group('skipReason (contract K3)', () {
    test('a media-failed skip sends skipReason with skipped:true', () async {
      final backend = _FakeBackend({
        'submitHumorFeedback': {'ok': true},
      });
      final source = FunctionsHumorDataSource(backend: backend);

      await source.skipContent(
        contentId: 'c9',
        skipReason: HumorSkipReason.mediaFailed,
      );

      expect(backend.payloads, [
        {'contentId': 'c9', 'skipped': true, 'skipReason': 'media_failed'},
      ]);
      expect(backend.payloads.first.containsKey('rating'), isFalse);
    });
  });

  group('HumorController.skipUnplayable', () {
    test('skips as media_failed, never rates, never counts, and '
        'advances', () async {
      final source = MockHumorDataSource();
      final analytics = _RecordingAnalytics();
      final controller = HumorController(
        repository: HumorRepositoryImpl(dataSource: source),
        analytics: analytics,
      );
      await controller.load();
      final broken = controller.state.current!.contentId;

      await controller.skipUnplayable(broken);

      expect(source.skipReasons, [HumorSkipReason.mediaFailed]);
      expect(source.ratingOf(broken), isNull);
      expect(source.deferredContentIds, contains(broken));
      expect(source.waivedContentIds, isEmpty);
      expect(source.profile.interactionCount, 0);
      expect(controller.state.calibration.completedCount, 0);
      expect(controller.state.currentIndex, 1);
      expect(controller.state.current!.contentId, isNot(broken));
      expect(analytics.names, contains(AnalyticsEvents.humorMediaSkipped));
      expect(
        analytics.names,
        isNot(contains(AnalyticsEvents.humorContentSkipped)),
      );
      expect(
        analytics.events
            .firstWhere((e) => e.$1 == AnalyticsEvents.humorMediaSkipped)
            .$2,
        {'content_id': broken, 'reason': 'media_failed'},
      );
    });

    test('a tap from a card that is no longer on screen is ignored', () async {
      final source = MockHumorDataSource();
      final controller = HumorController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await controller.load();
      final second = controller.state.items[1].contentId;

      await controller.skipUnplayable(second);

      expect(source.skipCalls, 0);
      expect(controller.state.currentIndex, 0);
    });

    test('an unplayable last calibration item is never replaced by other '
        'content: the calibration pauses and the same item is back '
        'tomorrow', () async {
      const total = MockHumorDataSource.onboardingCount;
      final source = MockHumorDataSource();
      await _preRate(source, total - 1);
      final controller = HumorController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await controller.load();
      expect(controller.state.items, hasLength(1));
      final broken = controller.state.current!.contentId;
      final feedCallsBefore = source.feedCalls;

      await controller.skipUnplayable(broken);

      expect(source.feedCalls, feedCallsBefore + 1, reason: 'one tail fetch');
      // Nothing took its place — everyone rates the same items.
      expect(controller.state.current, isNull);
      expect(controller.state.items.map((item) => item.contentId), [broken]);
      expect(controller.state.continuesTomorrow, isTrue);
      expect(controller.state.calibration.complete, isFalse);
      expect(controller.state.calibration.completedCount, total - 1);
      expect(source.profile.interactionCount, total - 1);

      source.closeDay('2099-01-02');
      await controller.load();
      expect(controller.state.current?.contentId, broken);
      await controller.rate(HumorRating.funny);
      expect(controller.state.calibration.complete, isTrue);
    });

    test('media that fails on a second day is waived for the user instead of '
        'holding the calibration open forever', () async {
      const total = MockHumorDataSource.onboardingCount;
      final source = MockHumorDataSource();
      await _preRate(source, total - 1);
      final controller = HumorController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await controller.load();
      final broken = controller.state.current!.contentId;
      await controller.skipUnplayable(broken);

      source.closeDay('2099-01-02');
      await controller.load();
      await controller.skipUnplayable(broken);

      expect(source.waivedContentIds, contains(broken));
      expect(source.ratingOf(broken), isNull, reason: 'never a rating');
      expect(source.calibration.complete, isTrue);
      expect(source.profile.interactionCount, total - 1);
    });

    test('a failed media skip is retried as a media skip', () async {
      final source = MockHumorDataSource();
      final controller = HumorController(
        repository: HumorRepositoryImpl(dataSource: source),
      );
      await controller.load();
      final broken = controller.state.current!.contentId;
      source.failFeedback = true;

      await controller.skipUnplayable(broken);
      expect(controller.state.currentIndex, 0);
      expect(controller.state.actionFailure, isNotNull);

      source.failFeedback = false;
      await controller.retryFailedAction();

      expect(source.skipReasons, [
        HumorSkipReason.mediaFailed,
        HumorSkipReason.mediaFailed,
      ]);
      expect(controller.state.currentIndex, 1);
      expect(source.ratingOf(broken), isNull);
    });
  });

  group('Humor Lab', () {
    testWidgets('Next on a clip that cannot play skips it as media_failed '
        'and moves on without touching calibration', (tester) async {
      final l10n = l10nTr();
      await withFakeNetworkImages(() async {
        final source = MockHumorDataSource();
        final controller = HumorController(
          repository: HumorRepositoryImpl(dataSource: source),
        );
        final first = MockHumorDataSource.seedCatalog.first;
        expect(first.type, HumorContentType.video);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('tr'),
            home: HumorLabPage(controller: controller),
          ),
        );
        // No platform video player exists in widget tests, so the first clip
        // fails, is retried once, and lands in the failed state.
        final next = find.text(l10n.humorMediaNext);
        for (var i = 0; i < 300 && next.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(next, findsOneWidget);
        expect(find.text(l10n.humorVideoLoadFailed), findsOneWidget);

        await tester.tap(next);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(source.skipReasons, [HumorSkipReason.mediaFailed]);
        expect(source.ratingOf(first.contentId), isNull);
        expect(source.feedbackCalls, 1, reason: 'the skip only, no rating');
        expect(controller.state.currentIndex, 1);
        expect(
          find.text(
            l10n.humorCalibrationProgress(
              0,
              MockHumorDataSource.onboardingCount,
            ),
          ),
          findsOneWidget,
        );
      });
    });
  });
}
