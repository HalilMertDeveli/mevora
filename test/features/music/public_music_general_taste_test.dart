import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/presentation/widgets/public_music_taste_section.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _taste = PublicMusicTaste(
  dominantGenre: 'alternative',
  secondaryGenres: ['indie', 'r&b'],
  signatureArtists: ['Arctic Monkeys', 'The Weeknd', 'Lana Del Rey'],
  stableArtistCount: 3,
  artistBreadth: 11,
);

const _published = PublicMusicProfile(
  enabled: true,
  artists: [
    PublicMusicArtist(id: 'a1', name: 'Arctic Monkeys'),
    PublicMusicArtist(id: 'a2', name: 'The Weeknd'),
    PublicMusicArtist(id: 'a3', name: 'Lana Del Rey'),
  ],
  tracks: [
    PublicMusicTrack(id: 't1', name: 'Do I Wanna Know?'),
    PublicMusicTrack(id: 't2', name: 'Blinding Lights'),
    PublicMusicTrack(id: 't3', name: 'Summertime Sadness'),
  ],
  genres: ['alternative', 'indie', 'r&b', 'pop', 'psychedelic'],
  taste: _taste,
);

Future<void> _pump(WidgetTester tester, PublicMusicProfile profile) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PublicMusicTasteSection(profile: profile),
        ),
      ),
    ),
  );
}

void main() {
  group('parsing what the backend published', () {
    test('reads a general summary', () {
      final profile = PublicMusicProfile.parse({
        'enabled': true,
        'artists': [
          {'id': 'a1', 'name': 'Arctic Monkeys'},
        ],
        'tracks': <Object>[],
        'genres': ['alternative', 'indie', 'r&b', 'pop', 'psychedelic'],
        'taste': {
          'dominantGenre': 'alternative',
          'secondaryGenres': ['indie', 'r&b'],
          'signatureArtists': ['Arctic Monkeys', 'The Weeknd'],
          'stableArtistCount': 2,
          'artistBreadth': 9,
        },
      });

      expect(profile.taste.dominantGenre, 'alternative');
      expect(profile.taste.signatureArtists, ['Arctic Monkeys', 'The Weeknd']);
      expect(profile.taste.stableArtistCount, 2);
      expect(profile.taste.hasContent, isTrue);
      expect(
        profile.genres,
        hasLength(5),
        reason: 'genres describe the general taste, so five are allowed',
      );
    });

    test('a card published before the analysis existed simply has none', () {
      final profile = PublicMusicProfile.parse({
        'enabled': true,
        'artists': [
          {'id': 'a1', 'name': 'Arctic Monkeys'},
        ],
        'genres': ['indie'],
      });
      expect(profile.taste.hasContent, isFalse);
      expect(profile.hasContent, isTrue, reason: 'the card still renders');
    });

    test('a malformed summary is dropped rather than trusted', () {
      final profile = PublicMusicProfile.parse({
        'enabled': true,
        'artists': [
          {'id': 'a1', 'name': 'Arctic Monkeys'},
        ],
        'taste': {
          'dominantGenre': 42,
          'signatureArtists': 'not a list',
          'stableArtistCount': 'lots',
        },
      });
      expect(profile.taste.dominantGenre, isNull);
      expect(profile.taste.signatureArtists, isEmpty);
      expect(profile.taste.stableArtistCount, 0);
    });

    test('a summary that is not a map at all is ignored', () {
      expect(PublicMusicTaste.parse('nonsense').hasContent, isFalse);
      expect(PublicMusicTaste.parse(null).hasContent, isFalse);
    });
  });

  group('what the section shows', () {
    testWidgets('all three artists and all three tracks render', (
      tester,
    ) async {
      await _pump(tester, _published);

      for (final name in ['Arctic Monkeys', 'The Weeknd', 'Lana Del Rey']) {
        expect(find.text(name), findsWidgets, reason: '$name is missing');
      }
      for (final name in [
        'Do I Wanna Know?',
        'Blinding Lights',
        'Summertime Sadness',
      ]) {
        expect(find.text(name), findsOneWidget, reason: '$name is missing');
      }
    });

    testWidgets('it describes a general taste, not a recent week', (
      tester,
    ) async {
      await _pump(tester, _published);

      expect(find.text(_en.musicTasteGeneralHeading), findsOneWidget);
      expect(
        find.text(_en.musicTasteDominant('Alternative, Indie, R&b')),
        findsOneWidget,
      );
      expect(
        find.text(
          _en.musicTasteSignature('Arctic Monkeys, The Weeknd, Lana Del Rey'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('it says at most three things', (tester) async {
      await _pump(tester, _published);

      final lines = [
        _en.musicTasteDominant('Alternative, Indie, R&b'),
        _en.musicTasteSignature('Arctic Monkeys, The Weeknd, Lana Del Rey'),
        _en.musicTasteStable(3),
      ].where((line) => find.text(line).evaluate().isNotEmpty).length;
      expect(lines, lessThanOrEqualTo(3));
    });

    testWidgets('the bare genre line is not repeated alongside it', (
      tester,
    ) async {
      await _pump(tester, _published);
      expect(
        find.text('Alternative · Indie · R&b · Pop · Psychedelic'),
        findsNothing,
        reason: 'the summary already names the genres',
      );
    });

    testWidgets('an older card still shows its genres', (tester) async {
      await _pump(
        tester,
        const PublicMusicProfile(
          enabled: true,
          artists: [PublicMusicArtist(id: 'a1', name: 'Arctic Monkeys')],
          genres: ['indie', 'alternative'],
        ),
      );
      expect(find.text('Indie · Alternative'), findsOneWidget);
    });

    testWidgets('one lasting artist is not worth remarking on', (tester) async {
      await _pump(
        tester,
        _published.copyWith(
          taste: const PublicMusicTaste(
            dominantGenre: 'indie',
            signatureArtists: ['Arctic Monkeys'],
            stableArtistCount: 1,
          ),
        ),
      );
      expect(find.text(_en.musicTasteStable(1)), findsNothing);
    });

    testWidgets('nothing published means nothing rendered', (tester) async {
      await _pump(tester, PublicMusicProfile.hidden);
      expect(find.text(_en.profileMusicTasteHeading), findsNothing);
    });
  });
}
