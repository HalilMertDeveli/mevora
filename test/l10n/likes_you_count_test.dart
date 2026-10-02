import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  test('the locked likes count reads correctly for one and for many', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.likesYouLockedCount(1), '1 person likes you');
    expect(en.likesYouLockedCount(2), '2 people like you');
    expect(en.likesYouLockedCount(11), '11 people like you');

    // Turkish does not inflect the noun after a number.
    final tr = lookupAppLocalizations(const Locale('tr'));
    expect(tr.likesYouLockedCount(1), '1 kişi seni beğendi');
    expect(tr.likesYouLockedCount(5), '5 kişi seni beğendi');
  });
}
