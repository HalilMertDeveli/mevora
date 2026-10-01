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
    // Gallery picks go through the system photo picker, which needs no
    // permission; Google Play rejects broad media access for that use.
    expect(xml, isNot(contains('"android.permission.READ_MEDIA_IMAGES"')));
    expect(
      xml,
      isNot(contains('"android.permission.READ_MEDIA_VISUAL_USER_SELECTED"')),
    );
    expect(xml, isNot(contains('"android.permission.READ_MEDIA_VIDEO"')));
    // No ads: the advertising-ID and ad-attribution permissions that Firebase
    // Analytics merges in are removed explicitly.
    for (final permission in [
      'com.google.android.gms.permission.AD_ID',
      'android.permission.ACCESS_ADSERVICES_AD_ID',
      'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
    ]) {
      expect(xml, contains('"$permission" tools:node="remove"'));
    }
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
      contains('Mevora uses your camera for profile photos and video calls.'),
    );
    expect(
      plist,
      contains('Mevora uses your microphone for voice and audio features.'),
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
    expect(
      plist,
      isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')),
    );
    expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
  });
}
