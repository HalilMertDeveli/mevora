import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Turkish ARB and generated localizations stay valid UTF-8', () {
    final files = [
      'lib/l10n/app_tr.arb',
      'lib/l10n/app_en.arb',
      'lib/l10n/app_localizations_tr.dart',
      'lib/l10n/app_localizations_en.dart',
    ];
    const mojibake = ['Ã§', 'Ã¶', 'Ã¼', 'ÄŸ', 'Ä±', 'ÅŸ', 'Ä°', 'â€”', 'â€¦'];
    for (final path in files) {
      final bytes = File(path).readAsBytesSync();
      final text = utf8.decode(bytes);
      for (final bad in mojibake) {
        expect(text.contains(bad), isFalse, reason: '$path contains $bad');
      }
    }
    final tr = File('lib/l10n/app_localizations_tr.dart').readAsStringSync();
    for (final good in ['ç', 'ğ', 'ı', 'İ', 'ö', 'ş', 'ü', 'Yardım', 'Gizlilik']) {
      expect(tr.contains(good), isTrue, reason: 'missing $good');
    }
  });
}
