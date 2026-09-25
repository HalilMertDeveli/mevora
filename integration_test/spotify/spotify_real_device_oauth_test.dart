// Phase 7B — physical device Spotify music link E2E.
// Manual step: when Spotify authorize opens, complete login+consent on the phone.
//
// flutter test integration_test/spotify/spotify_real_device_oauth_test.dart -d R68T305S3VM ^
//   --flavor development ^
//   --dart-define=USE_EMULATORS=false ^
//   --dart-define=SPOTIFY_CLIENT_ID=b0a808c4c2264b0ba179c2045a8d3445 ^
//   --dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN=<token> ^
//   --dart-define=QA_A_EMAIL=... ^
//   --dart-define=QA_E2E_PASSWORD=...

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mevora/bootstrap.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/l10n/app_localizations.dart';

const _email = String.fromEnvironment('QA_A_EMAIL');
const _password = String.fromEnvironment('QA_E2E_PASSWORD');
const _uidHint = String.fromEnvironment('QA_A_UID');

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Phase 7B real-device Spotify music OAuth + summary', (tester) async {
    expect(_email.isNotEmpty, isTrue, reason: 'QA_A_EMAIL required');
    expect(_password.isNotEmpty, isTrue, reason: 'QA_E2E_PASSWORD required');

    await bootstrap(AppEnvironment.development);
    await tester.pumpAndSettle(const Duration(seconds: 6));

    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email,
        password: _password,
      );
      await tester.pumpAndSettle(const Duration(seconds: 10));
    }

    final user = FirebaseAuth.instance.currentUser;
    expect(user, isNotNull, reason: 'Firebase Auth required before Spotify music link');
    final uid = user!.uid;
    if (_uidHint.isNotEmpty) {
      expect(uid, _uidHint);
    }

    final l10n = lookupAppLocalizations(const Locale('en'));

    // Dismiss any overlays, open Music tab.
    final musicTab = find.text(l10n.musicTitle);
    expect(musicTab, findsWidgets);
    await tester.tap(musicTab.last);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final connect = find.text(l10n.musicConnectCta);
    if (connect.evaluate().isEmpty) {
      // Already connected — still validate summary.
      final existing = await FirebaseFirestore.instance
          .doc('users/$uid/music/summary')
          .get();
      expect(existing.exists, isTrue);
      expect(existing.data()?['provider'], 'spotify');
      return;
    }

    await tester.tap(connect);
    await tester.pump(const Duration(seconds: 2));

    // Allow manual Spotify login + consent (up to 5 minutes).
    DocumentSnapshot<Map<String, dynamic>>? summary;
    for (var i = 0; i < 60; i += 1) {
      await _pumpFor(tester, const Duration(seconds: 5));
      summary = await FirebaseFirestore.instance.doc('users/$uid/music/summary').get();
      final data = summary.data();
      if (data != null &&
          (data['spotifyConnected'] == true || data['connected'] == true) &&
          data['provider'] == 'spotify') {
        break;
      }
    }

    final data = summary?.data();
    expect(data, isNotNull, reason: 'music/summary not written after OAuth wait');
    expect(data!['provider'], 'spotify');
    expect(data['musicProfileVersion'], 3);
    final profile = Map<String, dynamic>.from(data['musicProfile'] as Map? ?? {});
    expect(profile['trackIds'], isA<List>());
    expect(profile['artistIds'], isA<List>());
    expect((profile['trackIds'] as List).isNotEmpty, isTrue);
    expect((profile['artistIds'] as List).isNotEmpty, isTrue);
    final recentArtists = profile['recentArtists'] as List? ?? [];
    expect(recentArtists.length, lessThanOrEqualTo(5));

    // Client payload must not expose secret fields in summary doc.
    final serialized = data.toString().toLowerCase();
    expect(serialized.contains('accesstoken'), isFalse);
    expect(serialized.contains('refreshtoken'), isFalse);
    expect(serialized.contains('clientsecret'), isFalse);
  });
}
