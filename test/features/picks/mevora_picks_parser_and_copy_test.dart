import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'picks_fixtures.dart';

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

void main() {
  group('MevoraPicksParser', () {
    test('parses a batch in rank order with its lifecycle status', () {
      final batch = batchOf([
        pickPayload(uid: 'b', rank: 1),
        pickPayload(uid: 'a', rank: 0),
      ], status: 'lowSupply');
      expect(batch.picks.map((p) => p.uid), ['a', 'b']);
      expect(batch.status, PicksStatus.lowSupply);
      expect(batch.generationId, 'gen1');
      expect(batch.refreshAt, isNotNull);
    });

    test('an empty batch is empty whatever status it claims', () {
      final batch = batchOf(
        const [],
        status: 'ready',
        emptyReason: 'allDecided',
      );
      expect(batch.status, PicksStatus.empty);
      expect(batch.emptyReason, PicksEmptyReason.allDecided);
    });

    test('drops entries with an unknown type instead of guessing', () {
      final batch = batchOf([
        pickPayload(uid: 'ok'),
        pickPayload(uid: 'odd', pickType: 'somethingNew'),
      ]);
      expect(batch.picks.map((p) => p.uid), ['ok']);
    });

    test('reads structured reasons, including the reserved "values" type', () {
      final pick = pickFrom(
        pickPayload(
          uid: 'v',
          pickType: 'valuesMatch',
          labels: const ['valuesMatch', 'bestOverall'],
          reasons: [
            {
              'type': 'values',
              'score': 90,
              'strength': 'strong',
              'meta': {
                'aligned': 4,
                'shared': 5,
                'topics': ['trust'],
              },
            },
            {
              'type': 'relationship',
              'score': null,
              'strength': 'strong',
              'meta': <String, Object>{},
            },
            {
              'type': 'unknownReason',
              'score': 50,
              'strength': 'notable',
              'meta': <String, Object>{},
            },
          ],
        ),
      );
      expect(pick.pickType, PickType.valuesMatch);
      expect(pick.secondaryLabels, [PickType.bestOverall]);
      expect(pick.reasons.map((r) => r.type), [
        PickReasonType.relationshipViews,
        PickReasonType.relationship,
      ]);
      final views = pick.reasonOf(PickReasonType.relationshipViews)!;
      expect(views.score, 90);
      expect(views.intMeta('aligned'), 4);
      expect(views.listMeta('topics'), ['trust']);
      expect(pick.reasonOf(PickReasonType.relationship)!.score, isNull);
    });

    test('keeps humor traits the app knows and ignores the rest', () {
      final pick = pickFrom(
        pickPayload(
          uid: 'h',
          pickType: 'humorMatch',
          humorScore: 92,
          humorTraits: const ['absurd', 'dark', 'notATrait'],
        ),
      );
      expect(pick.humorScore, 92);
      expect(pick.sharedHumorTraits, [
        HumorCategory.absurd,
        HumorCategory.dark,
      ]);
    });

    test('never carries coordinates from the payload', () {
      final raw = pickPayload(uid: 'x')..['latitude'] = 41.0;
      (raw['profile'] as Map)['longitude'] = 29.0;
      final pick = pickFrom(raw);
      expect(pick.candidate.distanceKm, isNull);
    });
  });

  group('PickCopy — every claim traces to server data', () {
    test('Humor Match shows a percentage only when the server scored it', () {
      final scored = pickFrom(
        pickPayload(
          uid: 'h',
          pickType: 'humorMatch',
          reasons: [
            {
              'type': 'humor',
              'score': 92,
              'strength': 'strong',
              'meta': {'traits': <String>[]},
            },
          ],
        ),
      );
      expect(
        PickCopy.headline(_en, scored),
        'Your humor profiles are 92% compatible.',
      );
      expect(PickCopy.headline(_tr, scored), 'Mizah profiliniz %92 uyumlu.');

      final unscored = pickFrom(
        pickPayload(
          uid: 'h2',
          pickType: 'humorMatch',
          reasons: [
            {
              'type': 'relationship',
              'score': null,
              'strength': 'strong',
              'meta': <String, Object>{},
            },
          ],
        ),
      );
      final headline = PickCopy.headline(_en, unscored);
      expect(headline.contains('%'), isFalse);
    });

    test('Music Match counts artists only when the server counted them', () {
      final withArtists = pickFrom(
        pickPayload(
          uid: 'm',
          pickType: 'musicMatch',
          reasons: [
            {
              'type': 'music',
              'score': 70,
              'strength': 'notable',
              'meta': {'artists': 4},
            },
          ],
        ),
      );
      expect(PickCopy.headline(_en, withArtists), 'You share 4 artists.');
      expect(PickCopy.headline(_tr, withArtists), '4 ortak sanatçınız var.');

      final scoreOnly = pickFrom(
        pickPayload(
          uid: 'm2',
          pickType: 'musicMatch',
          reasons: [
            {
              'type': 'music',
              'score': 81,
              'strength': 'strong',
              'meta': {'artists': 0},
            },
          ],
        ),
      );
      expect(PickCopy.headline(_en, scoreOnly), _en.pickHeadlineMusic);
    });

    test('Unexpected Match explains the contrast, not a random pick', () {
      final pick = pickFrom(pickPayload(uid: 'u', pickType: 'unexpectedMatch'));
      expect(
        PickCopy.headline(_tr, pick),
        'Normalde gözden kaçırabileceğin biri.',
      );
      expect(PickCopy.supportingLine(_tr, pick), _tr.pickDetailUnexpected);
    });

    test(
      'a reason missing its data yields no sentence rather than a made-up one',
      () {
        const noScore = PickReason(type: PickReasonType.overall);
        const noCount = PickReason(type: PickReasonType.interests);
        const noKm = PickReason(type: PickReasonType.distance);
        expect(PickCopy.reasonSentence(_en, noScore), isNull);
        expect(PickCopy.reasonSentence(_en, noCount), isNull);
        expect(PickCopy.reasonSentence(_en, noKm), isNull);
      },
    );

    test('"Why {name}?" lists each real reason once', () {
      final pick = pickFrom(
        pickPayload(
          uid: 'w',
          name: 'Zeynep',
          pickType: 'humorMatch',
          humorTraits: const ['absurd', 'dark'],
          reasons: [
            {'type': 'humor', 'score': 92, 'strength': 'strong', 'meta': <String, Object>{}},
            {
              'type': 'relationship',
              'score': null,
              'strength': 'strong',
              'meta': <String, Object>{},
            },
            {
              'type': 'music',
              'score': 70,
              'strength': 'notable',
              'meta': {'artists': 4},
            },
            {
              'type': 'lifestyle',
              'score': 80,
              'strength': 'notable',
              'meta': <String, Object>{},
            },
            {'type': 'overall', 'score': 89, 'strength': 'strong', 'meta': <String, Object>{}},
          ],
        ),
      );
      final lines = PickCopy.whyLines(_tr, pick).map((l) => l.text).toList();
      expect(_tr.pickWhyTitle('Zeynep'), 'Neden Zeynep?');
      expect(lines, [
        'Mizah profiliniz %92 uyumlu.',
        'Ortak mizah tarzlarınız: Absürt, ${_tr.humorCategoryDark}.',
        'İkiniz de aynı türde bir ilişki arıyorsunuz.',
        'Müzik profilinizde 4 ortak sanatçı var.',
        'Yaşam tarzı tercihleriniz uyumlu.',
        'Mevora genel uyumunuz %89.',
      ]);
    });
  });
}
