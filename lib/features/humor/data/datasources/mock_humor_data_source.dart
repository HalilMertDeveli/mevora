import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';

/// In-memory Humor Lab with Turkish-first real playable media URLs.
class MockHumorDataSource implements HumorDataSource {
  MockHumorDataSource({
    List<HumorContent>? seed,
    UserHumorProfile? profile,
    this.failFeed = false,
    this.failFeedback = false,
  }) : _items = List<HumorContent>.from(seed ?? seedCatalog),
       _profile = profile ?? UserHumorProfile.empty;

  final List<HumorContent> _items;
  UserHumorProfile _profile;
  final Map<String, HumorRating> _ratings = {};
  final Set<String> _saved = {};
  var failFeed = false;
  var failFeedback = false;
  var feedCalls = 0;
  var feedbackCalls = 0;

  UserHumorProfile get profile => _profile;

  static const seedCatalog = <HumorContent>[
    HumorContent(
      contentId: 'hc_tr_vid_001',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.absurd,
      humorTags: ['absürt', 'video'],
      textBody: 'Alarm değil, sabah sabotajı.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerBlazes.jpg',
      durationMs: 15000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_tr_vid_002',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.situational,
      humorTags: ['günlük', 'video'],
      textBody: 'Buzdolabı yine boş fikirler sunuyor.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerEscapes.jpg',
      durationMs: 15000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_tr_vid_003',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      humorTags: ['saçma', 'video'],
      textBody: 'Planım vardı… sonra pazartesi oldu.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerFun.jpg',
      durationMs: 60000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_tr_vid_004',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.meme,
      humorTags: ['meme', 'video'],
      textBody: 'Wi‑Fi şifresi kadar karmaşık bir ruh hali.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerJoyrides.jpg',
      durationMs: 15000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_tr_img_001',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.sarcasm,
      humorTags: ['ironi', 'meme'],
      textBody: 'Tabii, trafik yine benim yüzümden oluştu.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-1/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-1/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_002',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.wordplay,
      humorTags: ['kelime', 'espri'],
      textBody: "Kahve olmadan ben 'ben' değilim; 'be n'.",
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-2/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-2/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_003',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.teasing,
      humorTags: ['takılma'],
      textBody: 'Poker suratın tatilde galiba.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-3/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-3/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_004',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.cringe,
      humorTags: ['cringe', 'sosyal'],
      textBody: 'Arkandaki kişiye el sallayanı sandım. Klasik.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-4/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-4/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_005',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.dark,
      humorTags: ['kuru', 'bitki'],
      textBody: 'Bitkilerimle karşılıklı ihmal anlaşmamız var.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-5/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-5/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_vid_005',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.romantic,
      humorTags: ['romantik', 'espri'],
      textBody: 'Sen Wi‑Fi misin? Bağlantı hissediyorum.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ForBiggerMeltdowns.jpg',
      durationMs: 15000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_en_vid_001',
      type: HumorContentType.video,
      language: 'en',
      category: HumorCategory.silly,
      humorTags: ['silly', 'fallback'],
      textBody: 'English fallback clip for bilingual users.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
      durationMs: 60000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_en_img_001',
      type: HumorContentType.image,
      language: 'en',
      category: HumorCategory.meme,
      humorTags: ['meme', 'fallback'],
      textBody: 'English fallback still — TR feed stays primary.',
      downloadUrl: 'https://picsum.photos/seed/mevora-en-1/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-en-1/540/960',
      aspectRatio: 9 / 16,
    ),
    // Mixed-provider fixtures (keep hc_tr_vid_001 first for existing tests).
    HumorContent(
      contentId: 'ext_youtube_dQw4w9WgXcQ',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.silly,
      humorTags: ['youtube', 'embed'],
      textBody: 'YouTube embed fixture for mixed-provider tests.',
      downloadUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      thumbUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      embedUrl:
          'https://www.youtube.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0&modestbranding=1',
      sourceId: 'dQw4w9WgXcQ',
      provider: 'youtube',
      attributionRequired: true,
      sourceUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'ext_giphy_mockMp4Fixture01',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.meme,
      humorTags: ['giphy', 'mp4'],
      textBody: 'Giphy-style MP4 fixture for mixed-provider tests.',
      downloadUrl:
          'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.mp4',
      thumbUrl: 'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif',
      sourceId: 'mockMp4Fixture01',
      provider: 'giphy',
      attributionRequired: true,
      sourceUrl: 'https://giphy.com/gifs/3oEjI6SIIHBdRxXI40',
      aspectRatio: 1,
    ),
  ];

  @override
  Future<HumorFeedPage> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  }) async {
    feedCalls += 1;
    if (failFeed) {
      throw StateError('mock-feed-failed');
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final pageSize = limit ?? HumorFeedPolicy.pageSize;
    final preferred = (languages ?? const ['tr', 'en'])
        .map((l) => l.toLowerCase())
        .toList();
    final ranked = [..._items]
      ..sort((a, b) {
        final ai = preferred.indexOf(a.language);
        final bi = preferred.indexOf(b.language);
        final aRank = ai < 0 ? 99 : ai;
        final bRank = bi < 0 ? 99 : bi;
        return aRank.compareTo(bRank);
      });
    // Infinite: cursor encodes absolute offset; wraps forever.
    final start = cursor == null || cursor.isEmpty
        ? 0
        : (int.tryParse(cursor) ?? 0);
    final page = <HumorContent>[];
    for (var i = 0; i < pageSize; i++) {
      if (ranked.isEmpty) {
        break;
      }
      page.add(ranked[(start + i) % ranked.length]);
    }
    final next = ranked.isEmpty ? null : '${start + page.length}';
    return HumorFeedPage(
      items: page,
      nextCursor: next,
      profileBuilding: _profile.profileBuilding,
      interactionCount: _profile.interactionCount,
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    return _profile;
  }

  @override
  Future<HumorFeedbackResult> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool skipped = false,
    bool saved = false,
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    feedbackCalls += 1;
    if (failFeedback) {
      throw StateError('mock-feedback-failed');
    }
    _ratings[contentId] = rating;
    if (saved) {
      _saved.add(contentId);
    }
    final nextCount = _profile.interactionCount + 1;
    final confidence = (nextCount / 40).clamp(0.0, 1.0);
    final building = nextCount < HumorFeedPolicy.buildingThreshold;
    _profile = _profile.copyWith(
      confidence: confidence,
      interactionCount: nextCount,
      profileBuilding: building,
    );
    return HumorFeedbackResult(
      ok: true,
      profileBuilding: building,
      interactionCount: nextCount,
      confidence: confidence,
    );
  }

  @override
  Future<HumorCompatibility> getMatchCompatibility(String matchId) async {
    return HumorCompatibility.unavailable;
  }

  @override
  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) async {}
}
