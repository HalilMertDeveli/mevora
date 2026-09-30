import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/discovery/data/parsers/discovery_candidate_parser.dart';

/// Server-rendered variants reach cards and avatars; the full-screen gallery
/// keeps the full-size originals.
void main() {
  Map<String, dynamic> payload(List<Object> photos) => {
    'uid': 'u1',
    'profile': {'displayName': 'Ada', 'age': 29, 'photos': photos},
  };

  test('cards and avatars use the variants, the gallery keeps originals', () {
    final candidate = DiscoveryCandidateParser.parse(
      payload([
        {
          'downloadUrl': 'https://s/original-1',
          'thumbUrl': 'https://s/thumb-1',
          'cardUrl': 'https://s/card-1',
        },
        {
          'downloadUrl': 'https://s/original-2',
          'thumbUrl': 'https://s/thumb-2',
          'cardUrl': 'https://s/card-2',
        },
      ]),
    )!;
    expect(candidate.photos, ['https://s/original-1', 'https://s/original-2']);
    expect(candidate.photoUrl, 'https://s/original-1');
    expect(candidate.cardPhoto, 'https://s/card-1');
    expect(candidate.avatarPhoto, 'https://s/thumb-1');
  });

  test(
    'a photo approved before variants existed falls back to the original',
    () {
      final candidate = DiscoveryCandidateParser.parse(
        payload([
          {
            'downloadUrl': 'https://s/original-1',
            'thumbUrl': null,
            'cardUrl': null,
          },
        ]),
      )!;
      expect(candidate.cardPhoto, 'https://s/original-1');
      expect(candidate.avatarPhoto, 'https://s/original-1');
    },
  );

  test(
    'a thumbnail is never promoted into the full-size gallery ahead of the original',
    () {
      final candidate = DiscoveryCandidateParser.parse(
        payload([
          {
            'downloadUrl': 'https://s/original-1',
            'thumbUrl': 'https://s/thumb-1',
          },
        ]),
      )!;
      expect(candidate.photos.single, 'https://s/original-1');
    },
  );

  test('variants follow the primary (first usable) photo', () {
    final candidate = DiscoveryCandidateParser.parse(
      payload([
        {'thumbUrl': ''},
        {'downloadUrl': 'https://s/original-2', 'cardUrl': 'https://s/card-2'},
      ]),
    )!;
    expect(candidate.photoUrl, 'https://s/original-2');
    expect(candidate.cardPhoto, 'https://s/card-2');
  });

  test('copyWith keeps the variants', () {
    final candidate = DiscoveryCandidateParser.parse(
      payload([
        {
          'downloadUrl': 'https://s/o',
          'thumbUrl': 'https://s/t',
          'cardUrl': 'https://s/c',
        },
      ]),
    )!.copyWith(isBoosted: true);
    expect(candidate.cardPhotoUrl, 'https://s/c');
    expect(candidate.thumbPhotoUrl, 'https://s/t');
  });
}
