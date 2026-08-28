import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';

void main() {
  group('HumorContent YouTube helpers', () {
    test('parses valid video id from embedUrl and sourceId', () {
      const item = HumorContent(
        contentId: 'ext_youtube_dQw4w9WgXcQ',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.silly,
        embedUrl:
            'https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0',
        downloadUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        sourceId: 'dQw4w9WgXcQ',
        provider: 'youtube',
      );
      expect(item.isYoutube, isTrue);
      expect(item.isGiphy, isFalse);
      expect(item.youtubeVideoId, 'dQw4w9WgXcQ');
    });

    test('rejects invalid youtube ids', () {
      const item = HumorContent(
        contentId: 'ext_youtube_bad!',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.meme,
        embedUrl: 'https://www.youtube.com/embed/not_valid!!',
        sourceId: 'too_short',
        provider: 'youtube',
      );
      expect(item.isYoutube, isTrue);
      expect(item.youtubeVideoId, isNull);
    });

    test('sanitized strips embed HTML from downloadUrl', () {
      final item = HumorContent.sanitized(
        contentId: 'ext_youtube_abcdefghijk',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.meme,
        provider: 'youtube',
        sourceId: 'abcdefghijk',
        downloadUrl: 'https://www.youtube.com/embed/abcdefghijk?playsinline=1',
        thumbUrl: 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
        embedUrl: 'https://www.youtube.com/embed/abcdefghijk',
      );
      expect(item.isYoutube, isTrue);
      expect(item.downloadUrl, 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg');
      expect(
        HumorContent.isYoutubeHtmlPlaybackUrl(item.downloadUrl),
        isFalse,
      );
      expect(item.embedUrl?.contains('/embed/'), isTrue);
    });

    test('never treats youtube poster url as giphy', () {
      const item = HumorContent(
        contentId: 'ext_youtube_abcdefghijk',
        type: HumorContentType.video,
        language: 'en',
        category: HumorCategory.meme,
        downloadUrl: 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
        embedUrl: 'https://www.youtube.com/embed/abcdefghijk',
        sourceId: 'abcdefghijk',
        provider: 'youtube',
      );
      expect(item.isGiphy, isFalse);
      expect(item.youtubeVideoId, 'abcdefghijk');
    });

    test('isGiphy detects provider and CDN urls', () {
      const byProvider = HumorContent(
        contentId: 'ext_giphy_abc',
        type: HumorContentType.video,
        language: 'tr',
        category: HumorCategory.meme,
        provider: 'giphy',
        downloadUrl: 'https://media.giphy.com/media/abc/giphy.mp4',
      );
      expect(byProvider.isGiphy, isTrue);
      expect(byProvider.isYoutube, isFalse);
    });
  });

  group('MockHumorDataSource mixed providers', () {
    test('keeps hc_tr_vid_001 first and appends youtube + giphy fixtures', () {
      const catalog = MockHumorDataSource.seedCatalog;
      expect(catalog.first.contentId, 'hc_tr_vid_001');
      expect(
        catalog.any((c) => c.provider == 'youtube' && c.isYoutube),
        isTrue,
      );
      expect(
        catalog.any((c) => c.provider == 'giphy' && c.isGiphy),
        isTrue,
      );
      final youtube = catalog.firstWhere((c) => c.provider == 'youtube');
      expect(youtube.youtubeVideoId, isNotNull);
      expect(
        youtube.downloadUrl?.contains('youtube.com/embed') ?? false,
        isFalse,
      );
    });
  });
}
