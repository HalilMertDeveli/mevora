import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_breakdown.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_reason.dart';
import 'package:mevora/features/compatibility/domain/services/compatibility_reason_engine.dart';
import 'package:mevora/features/compatibility/presentation/compatibility_l10n.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Product-language rules for compatibility copy (docs/product-language.md):
/// a human tier leads, and every sentence is backed by real data.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final tr = lookupAppLocalizations(const Locale('tr'));

  group('overall tier', () {
    test('boundaries map to the documented tiers', () {
      expect(CompatibilityL10n.tier(tr, 100), 'Güçlü eşleşme');
      expect(CompatibilityL10n.tier(tr, 80), 'Güçlü eşleşme');
      expect(CompatibilityL10n.tier(tr, 79), 'Birçok konuda yakınsınız');
      expect(CompatibilityL10n.tier(tr, 65), 'Birçok konuda yakınsınız');
      expect(
        CompatibilityL10n.tier(tr, 64),
        'Dikkate değer ortak noktalarınız var',
      );
      expect(
        CompatibilityL10n.tier(tr, 50),
        'Dikkate değer ortak noktalarınız var',
      );
      expect(CompatibilityL10n.tier(tr, 49), 'Bazı ortak noktalarınız var');
      expect(CompatibilityL10n.tier(tr, 0), 'Bazı ortak noktalarınız var');
    });

    test('tier leads and the percentage follows', () {
      expect(
        CompatibilityL10n.tierWithPercent(tr, 87),
        'Güçlü eşleşme · %87 uyum',
      );
      expect(
        CompatibilityL10n.tierWithPercent(en, 87),
        'Strong match · 87% match',
      );
    });
  });

  group('strongest dimension', () {
    test('names what the top dimension means for the two people', () {
      const breakdown = CompatibilityBreakdown(
        overallScore: 82,
        relationshipScore: 96,
        interestScore: 40,
        lifestyleScore: 60,
        strongestCategory: CompatibilityCategory.relationship,
      );
      expect(
        CompatibilityL10n.strongest(tr, breakdown),
        'Aynı şeyi arıyorsunuz',
      );
    });

    test('stays quiet when the top dimension is not actually strong', () {
      const breakdown = CompatibilityBreakdown(
        overallScore: 40,
        relationshipScore: 45,
        interestScore: 20,
        lifestyleScore: 30,
        strongestCategory: CompatibilityCategory.relationship,
      );
      expect(CompatibilityL10n.strongest(tr, breakdown), isNull);
    });
  });

  group('relationship goal reason', () {
    const base = CompatibilityBreakdown(
      overallScore: 80,
      relationshipScore: 100,
      interestScore: 0,
      lifestyleScore: 0,
    );

    List<CompatibilityReason> reasonsFor(String goal) {
      return CompatibilityReasonEngine.build(
            viewer: UserProfile(
              uid: 'a',
              displayName: 'A',
              relationshipGoal: goal,
            ),
            candidate: UserProfile(
              uid: 'b',
              displayName: 'B',
              relationshipGoal: goal,
            ),
            breakdown: base,
          )
          .where((r) => r.messageKey == 'compatReasonSameRelationshipGoal')
          .toList();
    }

    test('stored onboarding ids read as a sentence, never a raw id', () {
      final reasons = reasonsFor('short_term');
      expect(reasons, hasLength(1));
      expect(
        CompatibilityL10n.reason(tr, reasons.single),
        'İkiniz de daha rahat bir ilişki arıyorsunuz',
      );
      expect(
        CompatibilityL10n.reason(tr, reasonsFor('long_term').single),
        'İkiniz de uzun süreli bir ilişki arıyorsunuz',
      );
    });

    test('two people who declined to answer do not "want the same thing"', () {
      expect(reasonsFor('prefer_not_to_say'), isEmpty);
    });
  });

  group('shared interest reason', () {
    test('lists localized interest labels', () {
      const reason = CompatibilityReason(
        messageKey: 'compatReasonSharedInterests',
        messageArgs: ['travel', 'music'],
        category: CompatibilityCategory.interests,
      );
      expect(
        CompatibilityL10n.reason(tr, reason),
        'İkiniz de Seyahat, Müzik seviyorsunuz',
      );
    });
  });

  group('server reason codes', () {
    test('known codes are localized', () {
      expect(
        CompatibilityL10n.serverReasons(tr, [
          'Shared interests',
          'Similar music taste',
        ]),
        [
          'Ortak ilgi alanlarınız var',
          'Müzik zevkinizde güçlü ortak noktalar var',
        ],
      );
    });

    test('same goal needs the goal itself to say what is shared', () {
      expect(
        CompatibilityL10n.serverReason(
          tr,
          'Same relationship goal',
          relationshipGoal: 'long_term',
        ),
        'İkiniz de uzun süreli bir ilişki arıyorsunuz',
      );
      expect(
        CompatibilityL10n.serverReason(
          tr,
          'Same relationship goal',
          relationshipGoal: 'prefer_not_to_say',
        ),
        isNull,
      );
      expect(
        CompatibilityL10n.serverReason(tr, 'Same relationship goal'),
        isNull,
      );
    });

    test('unknown free text is dropped, never shown raw', () {
      expect(
        CompatibilityL10n.serverReasons(tr, ['Both love specialty coffee']),
        isEmpty,
      );
    });
  });
}
