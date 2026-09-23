import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_reveal_section.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/presentation/widgets/likes_you_insight_card.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_match_celebration.dart';

typedef _Size = ({double w, double h, String label});

const _devices = <_Size>[
  (w: 360, h: 640, label: '360x640'),
  (w: 360, h: 800, label: '360x800'),
  (w: 390, h: 844, label: '390x844'),
  (w: 412, h: 915, label: '412x915'),
  (w: 430, h: 932, label: '430x932'),
  (w: 375, h: 667, label: '375x667'),
  (w: 393, h: 852, label: '393x852'),
];

const _textScales = [0.8, 1.0, 1.15, 1.3];

Future<void> _configureViewport(WidgetTester tester, _Size size) async {
  tester.view.physicalSize = Size(size.w, size.h);
  tester.view.devicePixelRatio = 1.0;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Widget _withScale(Widget child, double scale, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    darkTheme: AppTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: const EdgeInsets.only(top: 44, bottom: 34),
      ),
      child: child!,
    ),
    home: child,
  );
}

const _sampleBreakdown = CompatibilityBreakdown(
  overallScore: 94,
  relationshipScore: 96,
  interestScore: 88,
  lifestyleScore: 91,
  musicScore: 94,
  questionScore: 88,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3 — match connection tile', () {
    for (final device in _devices) {
      testWidgets('tile ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device);
        await tester.pumpWidget(
          _withScale(
            Scaffold(
              body: SafeArea(
                child: MatchConnectionTile(
                  item: MatchListItem(
                    match: Match(
                      id: 'm1',
                      userIds: const ['me', 'other'],
                      createdAt: DateTime(2026, 1, 1),
                      isActive: true,
                      lastMessage: 'Hello',
                    ),
                    otherUserId: 'other',
                    name: 'Elif',
                  ),
                  currentUid: 'me',
                  breakdown: _sampleBreakdown,
                ),
              ),
            ),
            1.0,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 3 — likes you insight card', () {
    for (final device in _devices) {
      testWidgets('card ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device);
        await tester.pumpWidget(
          _withScale(
            Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: LikesYouInsightCard(
                    item: const IncomingLikerPreview(
                      uid: 'u1',
                      displayName: 'Elif',
                      age: 25,
                      city: 'Istanbul',
                    ),
                    onTap: () {},
                    breakdown: _sampleBreakdown,
                  ),
                ),
              ),
            ),
            1.0,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 3 — compatibility reveal', () {
    for (final scale in _textScales) {
      testWidgets('scale $scale on 360x640', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, _devices.first);
        await tester.pumpWidget(
          _withScale(
          const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: CompatibilityRevealSection(
                  breakdown: _sampleBreakdown,
                  reasons: [],
                ),
              ),
            ),
          ),
            scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 3 — match celebration dark', () {
    testWidgets('360x640 dark', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first);
      await tester.pumpWidget(
        _withScale(
          Scaffold(
            body: MevoraMatchCelebration(
              leftName: 'You',
              rightName: 'Elif',
              compatibilitySection: const CompatibilityRevealSection(
                breakdown: _sampleBreakdown,
                reasons: [],
                density: CompatibilityRevealDensity.compact,
              ),
              onSendMessage: () {},
              onKeepExploring: () {},
            ),
          ),
          1.0,
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 3 — relationship question card', () {
    testWidgets('question 360x640', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first);
      final question = RelationshipQuestionCatalog.questions.first;
      await tester.pumpWidget(
        _withScale(
          Scaffold(
            body: RelationshipQuestionCard(
              question: question,
              answeredCount: 1,
              totalCount: 3,
              onAnswer: (_) {},
            ),
          ),
          1.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
