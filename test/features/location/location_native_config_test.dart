import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android requests only foreground location', () {
    final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(xml, contains('ACCESS_FINE_LOCATION'));
    expect(xml, contains('ACCESS_COARSE_LOCATION'));
    expect(xml, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    expect(xml, isNot(contains('FOREGROUND_SERVICE_LOCATION')));
  });

  test('iOS usage string is present and always-location is omitted', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(
      plist,
      contains(
        'Mevora, yakındaki eşleşmeleri göstermek için konumunuzu kullanır.',
      ),
    );
    expect(plist, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')));
    expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
  });
}
