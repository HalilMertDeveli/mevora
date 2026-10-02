import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/music/data/datasources/functions_music_data_source.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';

/// `getSameTasteProfiles` sends each member's photos as objects, never as bare
/// URLs. The Music tab once kept only strings, so every same-taste row fell
/// back to an initial and the profile it opened had no photos at all.
void main() {
  Future<List<SameTasteMatch>> sameTaste(List<Object?> items) {
    final source = FunctionsMusicDataSource(
      backend: _FakeBackend({
        'getSameTasteProfiles': {'items': items},
      }),
      connectSpotifyImpl: () async {},
    );
    return source.getSameTasteProfiles();
  }

  // One entry as the callable returns it: the music overlap at the top level,
  // the public profile projection under `profile`.
  Map<String, Object?> entry({
    required List<Object?> photos,
    int musicScore = 82,
    Map<String, Object?> profile = const {},
  }) => {
    'uid': 'u-ada',
    'musicScore': musicScore,
    'sharedArtists': ['Mabel Matiz', 'Sezen Aksu'],
    'sharedTracks': ['Öyle Kolaysa'],
    'sharedGenres': ['turkish pop'],
    'sharedArtistCount': 4,
    'sharedTrackCount': 2,
    'sharedGenreCount': 1,
    'profile': {
      'uid': 'u-ada',
      'displayName': 'Ada',
      'age': 29,
      'gender': 'woman',
      'bio': 'Plak biriktiririm.',
      'photos': photos,
      'interests': ['music', 'hiking'],
      'city': 'İzmir',
      ...profile,
    },
  };

  Map<String, Object?> projectedPhoto(int index, {bool withVariants = true}) =>
      {
        'id': 'p$index',
        'downloadUrl': 'https://s/original-$index',
        'thumbUrl': withVariants ? 'https://s/thumb-$index' : null,
        'cardUrl': withVariants ? 'https://s/card-$index' : null,
        'order': index,
        'isPrimary': index == 0,
        'moderationStatus': 'approved',
      };

  test(
    'projected photo objects reach the tile and the profile gallery',
    () async {
      final matches = await sameTaste([
        entry(photos: [projectedPhoto(0), projectedPhoto(1)]),
      ]);

      final candidate = matches.single.candidate;
      // The gallery keeps full-size originals, in the order the server sent.
      expect(candidate.photos, [
        'https://s/original-0',
        'https://s/original-1',
      ]);
      // The primary photo's variants ride alongside for cards and avatars.
      expect(candidate.cardPhotoUrl, 'https://s/card-0');
      expect(candidate.thumbPhotoUrl, 'https://s/thumb-0');
      // What the same-taste row draws.
      expect(candidate.avatarPhoto, 'https://s/thumb-0');
    },
  );

  test('no overall score is being calculated for a same-taste member', () async {
    // The callable sends the music overlap, not an overall compatibility
    // score. The profile opened from the row used to show "Calculating..."
    // for as long as it stayed open.
    final matches = await sameTaste([
      entry(photos: [projectedPhoto(0)]),
    ]);

    final candidate = matches.single.candidate;
    expect(candidate.hasCompatibilityScore, isFalse);
    expect(
      candidate.compatibilityStatus,
      CompatibilityDisplayStatus.unavailable,
    );
    // The music overlap itself is untouched.
    expect(candidate.musicCompatibilityScore, 82);
    expect(matches.single.musicScore, 82);
  });

  test('an overall score the callable does send is kept', () async {
    final matches = await sameTaste([
      {
        ...entry(photos: [projectedPhoto(0)]),
        'compatibilityScore': 71,
      },
    ]);

    final candidate = matches.single.candidate;
    expect(candidate.compatibilityStatus, CompatibilityDisplayStatus.ready);
    expect(candidate.compatibilityScore, 71);
  });

  test('a photo without variants falls back to the original', () async {
    final matches = await sameTaste([
      entry(photos: [projectedPhoto(0, withVariants: false)]),
    ]);

    final candidate = matches.single.candidate;
    expect(candidate.photos, ['https://s/original-0']);
    expect(candidate.cardPhotoUrl, isNull);
    expect(candidate.thumbPhotoUrl, isNull);
    expect(candidate.avatarPhoto, 'https://s/original-0');
  });

  test('stored photo documents parse the same way', () async {
    // The shape the callable sent before it projected: the profile's own
    // photo entries, storage fields and all.
    final matches = await sameTaste([
      entry(
        photos: [
          {
            ...projectedPhoto(0),
            'storagePath': 'profile-photos/u-ada/p0.jpg',
            'thumbPath': 'profile-photos/u-ada/p0_thumb.jpg',
            'createdAt': {'_seconds': 1790000000, '_nanoseconds': 0},
          },
        ],
      ),
    ]);

    final candidate = matches.single.candidate;
    expect(candidate.photos, ['https://s/original-0']);
    expect(candidate.avatarPhoto, 'https://s/thumb-0');
  });

  test('a member with no approved photo still appears, without one', () async {
    final matches = await sameTaste([entry(photos: const [])]);

    final candidate = matches.single.candidate;
    expect(candidate.photos, isEmpty);
    expect(candidate.avatarPhoto, isNull);
  });

  test('the rest of the public card arrives with the photos', () async {
    final matches = await sameTaste([
      entry(
        photos: [projectedPhoto(0)],
        profile: {
          'relationshipGoal': 'long_term',
          'isVerified': true,
          'publicMusic': {
            'enabled': true,
            'artists': [
              {'id': 'a1', 'name': 'Mabel Matiz'},
            ],
          },
        },
      ),
    ]);

    final candidate = matches.single.candidate;
    expect(candidate.displayName, 'Ada');
    expect(candidate.age, 29);
    expect(candidate.city, 'İzmir');
    expect(candidate.bio, 'Plak biriktiririm.');
    expect(candidate.gender, 'woman');
    expect(candidate.interests, ['music', 'hiking']);
    expect(candidate.relationshipGoal, 'long_term');
    expect(candidate.isVerified, isTrue);
    expect(candidate.publicMusic.hasContent, isTrue);
    expect(candidate.publicMusic.artists.single.name, 'Mabel Matiz');
  });

  test('the music overlap keeps its own fields', () async {
    final matches = await sameTaste([
      entry(photos: [projectedPhoto(0)]),
    ]);

    final match = matches.single;
    expect(match.musicScore, 82);
    expect(match.candidate.musicCompatibilityScore, 82);
    expect(match.sharedArtists, ['Mabel Matiz', 'Sezen Aksu']);
    expect(match.sharedTracks, ['Öyle Kolaysa']);
    expect(match.sharedGenres, ['turkish pop']);
    expect(match.sharedArtistCount, 4);
    expect(match.sharedTrackCount, 2);
    expect(match.sharedGenreCount, 1);
  });

  test('a zero music score is no score, not a 0% match', () async {
    final matches = await sameTaste([
      entry(photos: [projectedPhoto(0)], musicScore: 0),
    ]);

    expect(matches.single.candidate.musicCompatibilityScore, isNull);
    expect(matches.single.candidate.hasMusicMatchDetail, isFalse);
  });

  test('an entry without a uid is skipped', () async {
    final matches = await sameTaste([
      {
        'musicScore': 70,
        'profile': <String, Object?>{'displayName': 'Kim'},
      },
      'not-a-map',
      entry(photos: [projectedPhoto(0)]),
    ]);

    expect(matches.map((match) => match.candidate.uid), ['u-ada']);
  });
}

class _FakeBackend implements BackendCallable {
  _FakeBackend(this._responses);

  final Map<String, Map<String, dynamic>> _responses;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final response = _responses[name];
    if (response == null) {
      throw StateError('Unexpected callable: $name');
    }
    return response;
  }
}
