import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/localization/locale_casing.dart';

const _tr = Locale('tr');
const _en = Locale('en');

void main() {
  group('Turkish', () {
    test('dotted i uppercases to dotted capital I', () {
      expect(LocaleCasing.upper('bildirimler', _tr), 'BİLDİRİMLER');
      expect(LocaleCasing.upper('gizlilik', _tr), 'GİZLİLİK');
      expect(
        LocaleCasing.upper('Bildirimler ve gizlilik', _tr),
        'BİLDİRİMLER VE GİZLİLİK',
      );
    });

    test('dotless i uppercases to plain capital I', () {
      expect(LocaleCasing.upper('ılık', _tr), 'ILIK');
      expect(LocaleCasing.upper('ırmak', _tr), 'IRMAK');
    });

    test('keeps the two i letters distinct in one string', () {
      // "ışık" (dotless) and "iyi" (dotted) must not collapse together.
      expect(LocaleCasing.upper('ışık iyi', _tr), 'IŞIK İYİ');
    });

    test('other Turkish letters follow the default mapping', () {
      expect(LocaleCasing.upper('çğöşü', _tr), 'ÇĞÖŞÜ');
    });

    test('is idempotent on already-uppercased Turkish text', () {
      expect(LocaleCasing.upper('BİLDİRİMLER', _tr), 'BİLDİRİMLER');
    });
  });

  group('English', () {
    test('uses the default mapping', () {
      expect(LocaleCasing.upper('notifications', _en), 'NOTIFICATIONS');
      expect(LocaleCasing.upper('Privacy', _en), 'PRIVACY');
    });

    test('does not apply the Turkish dotted I', () {
      expect(LocaleCasing.upper('i', _en), 'I');
      expect(LocaleCasing.upper('notifications', _en).contains('İ'), isFalse);
    });
  });

  test('empty and non-letter input is unchanged', () {
    expect(LocaleCasing.upper('', _tr), '');
    expect(LocaleCasing.upper('123 - +', _tr), '123 - +');
  });
}
