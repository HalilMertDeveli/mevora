import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/compatibility_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_server_payload.dart';
import 'package:mevora/features/compatibility/domain/repositories/why_you_matched_repository.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/match_why_you_matched_entry.dart';
import 'package:mevora/l10n/app_localizations.dart';

class _FakeWhyYouMatchedRepository implements WhyYouMatchedRepository {
  _FakeWhyYouMatchedRepository(this._handler);

  final Future<Result<WhyYouMatchedServerPayload>> Function({
    required String matchId,
    bool forceRefresh,
  }) _handler;

  @override
  Future<Result<WhyYouMatchedServerPayload>> fetchForMatch({
    required String matchId,
    bool forceRefresh = false,
  }) {
    return _handler(matchId: matchId, forceRefresh: forceRefresh);
  }
}

void main() {
  testWidgets('MatchWhyYouMatchedEntry opens sheet after fetch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CompatibilityScope(
          whyYouMatchedRepository: _FakeWhyYouMatchedRepository(
            ({required matchId, forceRefresh = false}) async {
              expect(matchId, 'a_b');
              return Success(
                WhyYouMatchedServerPayload.fromJson({
                  'available': true,
                  'overallScore': 80,
                  'reasons': [
                    {
                      'id': 'humor_answers_b',
                      'category': 'humor',
                      'score': 80,
                      'confidence': 0.8,
                      'titleKey': 'wymHumorTitle',
                      'descriptionKey': 'wymHumorEvidence',
                      'descriptionArgs': ['4', '5'],
                      'evidence': {
                        'type': 'sharedHumorAnswers',
                        'values': {'matching': 4, 'comparable': 5},
                      },
                    },
                  ],
                }),
              );
            },
          ),
          child: const Scaffold(
            body: MatchWhyYouMatchedEntry(matchId: 'a_b'),
          ),
        ),
      ),
    );

    expect(find.text('Neden Eşleştiniz?'), findsOneWidget);
    await tester.tap(find.text('Neden Eşleştiniz?'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Mizah anlayışınız benziyor.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MatchWhyYouMatchedEntry hidden without CompatibilityScope',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: MatchWhyYouMatchedEntry(matchId: 'a_b'),
        ),
      ),
    );

    expect(find.text('Neden Eşleştiniz?'), findsNothing);
  });
}
