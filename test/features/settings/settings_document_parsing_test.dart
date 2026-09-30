import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';

void main() {
  group('privacy listener decodes the snapshot it was given', () {
    test('a missing document means the defaults', () {
      final privacy = FirebaseSettingsDataSource.privacyFromData('b', null);
      expect(privacy.uid, 'b');
      expect(privacy.showOnlineStatus, isTrue);
      expect(privacy.showLastSeen, isTrue);
      expect(privacy.showTypingStatus, isTrue);
      expect(privacy.allowMessages, isTrue);
    });

    test(
      'stored choices win, and showActivity backs a missing showLastSeen',
      () {
        final privacy = FirebaseSettingsDataSource.privacyFromData('b', {
          'showOnlineStatus': false,
          'showActivity': false,
          'showTypingStatus': false,
          'allowCalls': false,
        });
        expect(privacy.showOnlineStatus, isFalse);
        expect(privacy.showLastSeen, isFalse);
        expect(privacy.showActivity, isFalse);
        expect(privacy.showTypingStatus, isFalse);
        expect(privacy.allowCalls, isFalse);
        expect(privacy.allowMessages, isTrue);
      },
    );
  });

  group('settings listener decodes the snapshot it was given', () {
    test('a missing document means the defaults', () {
      final settings = FirebaseSettingsDataSource.settingsFromData('a', null);
      expect(settings.uid, 'a');
      expect(settings.theme, 'system');
      expect(settings.messageNotifications, isTrue);
      expect(settings.locationEnabled, isFalse);
      expect(settings.lastLocationUpdate, isNull);
    });

    test('stored values, legacy language key and timestamps are read', () {
      final at = DateTime.utc(2026, 9, 30, 12);
      final settings = FirebaseSettingsDataSource.settingsFromData('a', {
        'language': 'en',
        'theme': 'dark',
        'messageNotifications': false,
        'locationEnabled': true,
        'lastLocationUpdate': Timestamp.fromDate(at),
      });
      expect(settings.languageCode, 'en');
      expect(settings.theme, 'dark');
      expect(settings.messageNotifications, isFalse);
      expect(settings.locationEnabled, isTrue);
      expect(settings.lastLocationUpdate?.toUtc(), at);
    });
  });
}
