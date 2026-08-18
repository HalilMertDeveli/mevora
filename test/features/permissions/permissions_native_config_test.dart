import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares only the needed foreground permissions', () {
    final xml = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(xml, contains('android.permission.CAMERA'));
    expect(xml, contains('android.permission.RECORD_AUDIO'));
    expect(xml, contains('ACCESS_COARSE_LOCATION'));
    expect(xml, contains('ACCESS_FINE_LOCATION'));
    expect(xml, contains('POST_NOTIFICATIONS'));
    expect(xml, contains('READ_MEDIA_IMAGES'));
    expect(xml, contains('READ_MEDIA_VISUAL_USER_SELECTED'));
    expect(xml, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    expect(xml, isNot(contains('FOREGROUND_SERVICE_LOCATION')));
    expect(xml, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(xml, isNot(contains('WRITE_EXTERNAL_STORAGE')));
    expect(xml, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });

  test('iOS usage descriptions match Mevora copy and omit always-location', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      contains('Mevora uses your camera to take profile photos.'),
    );
    expect(
      plist,
      contains(
        'Mevora uses your microphone for voice and audio features.',
      ),
    );
    expect(
      plist,
      contains(
        'Mevora needs access to your photos so you can add profile pictures.',
      ),
    );
    expect(
      plist,
      contains(
        'Mevora uses your location to improve distance and nearby discovery.',
      ),
    );
    expect(plist, contains('NSPhotoLibraryUsageDescription'));
    expect(plist, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')));
    expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
  });
}
