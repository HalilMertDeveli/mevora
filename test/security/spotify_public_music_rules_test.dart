import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static contract for the Spotify public/private split.
///
/// The behavioural assertions live in
/// `firebase/tests/firestore.security.emulator.test.mjs`; these run without an
/// emulator so a rules regression fails in the ordinary Flutter suite too.
void main() {
  late String rules;

  setUpAll(() {
    rules = File('firebase/firestore.rules').readAsStringSync();
  });

  group('public music card', () {
    test('publicMusic is not in the client profile write allowlists', () {
      // profiles/{uid} restricts client writes with hasOnly(...), so a field
      // absent from both lists cannot be written by any client. The public
      // music card is published only by updatePublicMusicProfile, which
      // validates the selection against the caller's own Spotify import.
      final createList = _between(
        rules,
        'function profileCreateKeysAllowed()',
        '}',
      );
      final updateList = _between(
        rules,
        'function profileUpdateKeysAllowed()',
        '}',
      );
      expect(createList, isNot(contains("'publicMusic'")));
      expect(updateList, isNot(contains("'publicMusic'")));
    });

    test('client profile writes stay restricted to an allowlist', () {
      // If these degraded to a denylist, every new server-owned field would
      // silently become client-writable.
      expect(rules, contains('profileCreateKeysAllowed'));
      expect(rules, contains('profileUpdateKeysAllowed'));
      expect(rules, contains('hasOnly(['));
    });

    test('spotifyConnected also stays server-owned', () {
      final updateList = _between(
        rules,
        'function profileUpdateKeysAllowed()',
        '}',
      );
      expect(updateList, isNot(contains("'spotifyConnected'")));
    });
  });

  group('private music data', () {
    test('imported taste is owner-read and never client-written', () {
      final music = _between(rules, 'match /music/{docId}', '}');
      expect(music, contains('allow read: if isOwner(userId)'));
      expect(music, contains('allow create, update, delete: if false'));
    });

    test('Spotify token store is deny-all for clients', () {
      final secrets = _between(rules, 'match /spotifySecrets/{userId}', '}');
      expect(secrets, contains('allow read, write: if false'));
    });

    test('Spotify ownership indexes are deny-all for clients', () {
      final musicIndex = _between(
        rules,
        'match /musicSpotifyIndex/{spotifyId}',
        '}',
      );
      expect(musicIndex, contains('allow read, write: if false'));
      // The login index has no rule of its own and must fall through to the
      // catch-all deny rather than to an open default.
      expect(rules, contains('match /{document=**}'));
      final fallback = _between(rules, 'match /{document=**}', '}');
      expect(fallback, contains('allow read, write: if false'));
    });
  });
}

/// The rule body between [start] and the next [end] marker.
String _between(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNot(-1), reason: 'missing rule block: $start');
  final to = source.indexOf(end, from + start.length);
  expect(to, isNot(-1), reason: 'unterminated rule block: $start');
  return source.substring(from, to);
}
