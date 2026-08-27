import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';

/// In-memory Humor Lab stand-in for tests and local UI (MVP default).
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
      contentId: 'hc_seed_001',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.wordplay,
      humorTags: ['pun', 'office'],
      textBody: 'I told my computer I needed a break… it froze.',
    ),
    HumorContent(
      contentId: 'hc_seed_002',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.sarcasm,
      humorTags: ['sarcasm', 'monday'],
      textBody: "Oh great, another meeting that could've been an email.",
    ),
    HumorContent(
      contentId: 'hc_seed_003',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.absurd,
      humorTags: ['absurd', 'animals'],
      textBody: 'A goose just billed me for emotional damages.',
    ),
    HumorContent(
      contentId: 'hc_seed_004',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.romantic,
      humorTags: ['romantic', 'flirty'],
      textBody: 'Are you Wi-Fi? Because I feel a connection.',
    ),
    HumorContent(
      contentId: 'hc_seed_005',
      type: HumorContentType.meme,
      language: 'en',
      category: HumorCategory.meme,
      humorTags: ['meme', 'relatable'],
      textBody: 'Me explaining my sleep schedule to my future self',
    ),
    HumorContent(
      contentId: 'hc_seed_006',
      type: HumorContentType.text,
      language: 'tr',
      category: HumorCategory.silly,
      humorTags: ['silly', 'everyday'],
      textBody: 'Çalar saat değil, moral sabotajcısı.',
    ),
    HumorContent(
      contentId: 'hc_seed_007',
      type: HumorContentType.text,
      language: 'tr',
      category: HumorCategory.sarcasm,
      humorTags: ['sarcasm'],
      textBody: 'Tabii, trafik yine benim yüzümden oluştu.',
    ),
    HumorContent(
      contentId: 'hc_seed_008',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.dark,
      humorTags: ['dark', 'mild'],
      textBody: 'My plants and I have a mutual neglect agreement.',
    ),
    HumorContent(
      contentId: 'hc_seed_009',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.teasing,
      humorTags: ['teasing'],
      textBody: 'Nice try. Your poker face is on vacation.',
    ),
    HumorContent(
      contentId: 'hc_seed_010',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.cringe,
      humorTags: ['cringe', 'social'],
      textBody: 'Waved at someone who was waving at the person behind me.',
    ),
    HumorContent(
      contentId: 'hc_seed_011',
      type: HumorContentType.text,
      language: 'tr',
      category: HumorCategory.wordplay,
      humorTags: ['wordplay'],
      textBody: "Kahve olmadan ben 'ben' değilim; 'be n'.",
    ),
    HumorContent(
      contentId: 'hc_seed_012',
      type: HumorContentType.text,
      language: 'en',
      category: HumorCategory.situational,
      humorTags: ['situational', 'home'],
      textBody: 'Opened the fridge for the third time. Still no new ideas.',
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
      throw StateError('mock-humor-feed-failed');
    }
    final pageLimit = limit ?? HumorFeedPolicy.pageSize;
    var start = 0;
    if (cursor != null && cursor.isNotEmpty) {
      start = int.tryParse(cursor) ?? 0;
    }
    final filtered = languages == null || languages.isEmpty
        ? _items
        : _items
              .where((item) => languages.contains(item.language))
              .toList(growable: false);
    final slice = filtered.skip(start).take(pageLimit).toList();
    final next = start + slice.length;
    final hasMore = next < filtered.length;
    return HumorFeedPage(
      items: slice,
      nextCursor: hasMore ? '$next' : null,
      profileBuilding: HumorFeedPolicy.isBuilding(_profile.interactionCount),
      interactionCount: _profile.interactionCount,
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
      throw StateError('mock-humor-feedback-failed');
    }
    final already = _ratings.containsKey(contentId);
    _ratings[contentId] = rating;
    if (saved) {
      _saved.add(contentId);
    }
    if (!already && !skipped) {
      final count = _profile.interactionCount + 1;
      final vibes = _deriveTopVibes(contentId, rating);
      _profile = _profile.copyWith(
        interactionCount: count,
        profileBuilding: HumorFeedPolicy.isBuilding(count),
        confidence: (count / 40).clamp(0.0, 1.0),
        topVibes: vibes,
      );
    }
    return HumorFeedbackResult(
      ok: true,
      profileBuilding: _profile.profileBuilding,
      interactionCount: _profile.interactionCount,
      confidence: _profile.confidence,
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    if (!detailed) {
      return UserHumorProfile(
        confidence: _profile.confidence,
        interactionCount: _profile.interactionCount,
        profileBuilding: _profile.profileBuilding,
        topVibes: _profile.topVibes,
        version: _profile.version,
      );
    }
    return _profile;
  }

  @override
  Future<HumorCompatibility> getMatchCompatibility(String matchId) async {
    if (_profile.interactionCount < 8) {
      return const HumorCompatibility(
        available: false,
        reason: 'building',
        confidence: 0,
      );
    }
    return HumorCompatibility(
      available: true,
      score: 72,
      strongestShared: _profile.topVibes.map((v) => v.category).take(2).toList(),
      differences: const [
        HumorDifference(dim: HumorCategory.dark, a: 40, b: 70),
      ],
      confidence: _profile.confidence,
    );
  }

  @override
  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) async {}

  /// Test helper: clear rated set and optionally reset profile.
  void reset({UserHumorProfile? profile}) {
    _ratings.clear();
    _saved.clear();
    _profile = profile ?? UserHumorProfile.empty;
  }

  List<HumorVibe> _deriveTopVibes(String contentId, HumorRating rating) {
    HumorContent? content;
    for (final item in _items) {
      if (item.contentId == contentId) {
        content = item;
        break;
      }
    }
    final category = content?.category ?? HumorCategory.meme;
    final boost = switch (rating) {
      HumorRating.veryFunny => 90,
      HumorRating.funny => 75,
      HumorRating.neutral => 55,
      HumorRating.notFunny => 35,
      HumorRating.notAtAll => 20,
    };
    final existing = List<HumorVibe>.from(_profile.topVibes);
    existing.removeWhere((v) => v.category == category);
    existing.insert(0, HumorVibe(category: category, value: boost));
    return existing.take(3).toList();
  }
}
