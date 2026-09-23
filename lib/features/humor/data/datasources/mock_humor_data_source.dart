import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
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
    // Mirrors the calibration alternates added to the backend internal seed so
    // local QA has enough content to walk a full 15-item calibration.
    HumorContent(
      contentId: 'hc_tr_img_006',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.sarcasm,
      humorTags: ['ironi', 'gunluk'],
      textBody: 'Harika, tam da bugün bitmesi gereken şey bitmedi.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-6/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-6/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_vid_006',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.absurd,
      humorTags: ['absürt', 'video'],
      textBody: 'Rüyamda da sıra bekliyordum. Uyanınca da.',
      downloadUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      thumbUrl:
          'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/images/ElephantsDream.jpg',
      durationMs: 15000,
      aspectRatio: 16 / 9,
    ),
    HumorContent(
      contentId: 'hc_tr_img_007',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.situational,
      humorTags: ['günlük', 'sosyal'],
      textBody: 'Asansörde sohbet başlatan insan türü üzerine bir inceleme.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-7/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-7/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_008',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.meme,
      humorTags: ['meme', 'klasik'],
      textBody: 'Bildirimi kapattım, huzur geldi sandım. Gelmedi.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-8/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-8/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_009',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.wordplay,
      humorTags: ['kelime', 'espri'],
      textBody: 'Planım yoktu ama planım olmadığına dair bir planım vardı.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-9/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-9/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_010',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.cringe,
      humorTags: ['cringe', 'sosyal'],
      textBody: 'Sesli mesajı yanlış gruba attım. İyi geceler herkese.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-10/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-10/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_011',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.dry,
      humorTags: ['kuru', 'sakin'],
      textBody: 'Evet. Güzel. Devam edelim.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-11/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-11/540/960',
      aspectRatio: 9 / 16,
    ),
  ];

  /// Mirror of the server stage boundaries so local QA walks the same shape.
  static HumorCalibrationStage _stageFor(int completedCount) {
    if (completedCount < HumorCalibration.anchorInteractions) {
      return HumorCalibrationStage.anchor;
    }
    if (completedCount <
        HumorCalibration.anchorInteractions +
            HumorCalibration.adaptiveInteractions) {
      return HumorCalibrationStage.adaptive;
    }
    if (completedCount < HumorCalibration.totalInteractions) {
      return HumorCalibrationStage.exploration;
    }
    return HumorCalibrationStage.complete;
  }

  HumorCalibration get calibration {
    final done = _completedCalibration;
    return HumorCalibration(
      stage: _stageFor(done),
      completedCount: done,
      complete: done >= HumorCalibration.totalInteractions,
    );
  }

  int get _completedCalibration => _ratings.length > HumorCalibration.totalInteractions
      ? HumorCalibration.totalInteractions
      : _ratings.length;

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
    final state = calibration;
    if (!state.complete) {
      // Calibration owns the page: unrated items only, each tagged with the
      // stage of the position it would occupy — the same contract the server
      // returns, so controller/UI behaviour matches between mock and real.
      final unrated = ranked
          .where((item) => !_ratings.containsKey(item.contentId))
          .toList();
      final wanted = HumorCalibration.totalInteractions - state.completedCount;
      final take = wanted < unrated.length ? wanted : unrated.length;
      final page = <HumorContent>[
        for (var i = 0; i < take; i += 1)
          unrated[i].copyWithCalibrationStage(
            _stageFor(state.completedCount + i),
          ),
      ];
      return HumorFeedPage(
        items: page,
        nextCursor: null,
        profileBuilding: true,
        interactionCount: _profile.interactionCount,
        calibration: state.copyWith(insufficientPool: page.length < wanted),
      );
    }

    // Mirror the server contract: unrated items only, walked in catalog order,
    // so the mock cannot hide a pagination regression behind repeats.
    final unrated = ranked
        .where((item) => !_ratings.containsKey(item.contentId))
        .toList();
    final start = cursor == null || cursor.isEmpty ? 0 : int.tryParse(cursor) ?? 0;
    final from = start.clamp(0, unrated.length);
    final end = (from + pageSize).clamp(0, unrated.length);
    final page = unrated.sublist(from, end);
    final next = end < unrated.length ? '$end' : null;
    return HumorFeedPage(
      items: page,
      nextCursor: next,
      profileBuilding: false,
      interactionCount: _profile.interactionCount,
      calibration: state,
      catalogExhausted: page.isEmpty && _items.isNotEmpty,
      catalogEmpty: _items.isEmpty,
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    final state = calibration;
    return _profile.copyWith(
      calibration: state,
      profileBuilding: !state.complete,
    );
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
    // Lifetime learning keeps counting past calibration, exactly like the
    // server: only the calibration milestone freezes at 15.
    final nextCount = _profile.interactionCount + 1;
    final confidence = (nextCount / 40).clamp(0.0, 1.0);
    final state = calibration;
    _profile = _profile.copyWith(
      confidence: confidence,
      interactionCount: nextCount,
      profileBuilding: !state.complete,
      calibration: state,
    );
    return HumorFeedbackResult(
      ok: true,
      profileBuilding: !state.complete,
      interactionCount: nextCount,
      confidence: confidence,
      calibration: state,
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
