import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mevora consumes `mevora://auth/spotify` through `app_links` ->
/// `SpotifyAuthService`. Flutter's own deep-link handler defaults to ON, and
/// when it is on it hands the callback to the router instead, which has no
/// route for that location. Both platforms have to opt out explicitly.
void main() {
  test('Android registers the Spotify callback and opts out of Flutter deep '
      'linking', () {
    final xml = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(xml, contains('android:name="flutter_deeplinking_enabled"'));
    expect(
      RegExp(
        r'flutter_deeplinking_enabled"\s*\r?\n?\s*android:value="false"',
      ).hasMatch(xml),
      isTrue,
      reason: 'flutter_deeplinking_enabled must be false, not true',
    );
    expect(
      xml,
      contains(
        '<data android:scheme="mevora" android:host="auth" '
        'android:pathPrefix="/spotify"/>',
      ),
    );
  });

  test('iOS registers the mevora scheme and opts out of Flutter deep linking', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<key>FlutterDeepLinkingEnabled</key>'));
    expect(
      RegExp(
        r'<key>FlutterDeepLinkingEnabled</key>\s*\r?\n?\s*<false/>',
      ).hasMatch(plist),
      isTrue,
      reason: 'FlutterDeepLinkingEnabled must be <false/>, not <true/>',
    );
    expect(plist, contains('<string>mevora</string>'));
  });
}
