import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_daily_set.dart';
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
    this.failProfile = false,
    this.failReport = false,
  }) : _items = List<HumorContent>.from(seed ?? seedCatalog),
       _profile = profile ?? UserHumorProfile.empty;

  final List<HumorContent> _items;
  UserHumorProfile _profile;

  /// Real ratings, one per content id — a re-rate replaces, never adds.
  final Map<String, HumorRating> _ratings = {};

  /// Content passed without a rating (skip or report marker). Excluded from
  /// the feed like a rating, but never counted.
  final Set<String> _passed = {};
  var failFeed = false;
  var failFeedback = false;
  var failProfile = false;
  var failReport = false;

  /// When set, feedback and skip calls wait for it — lets tests hold a
  /// submission in flight.
  Completer<void>? feedbackGate;
  var feedCalls = 0;
  var feedbackCalls = 0;
  var skipCalls = 0;

  /// The `skipReason` of every skip, in order (`null` when none was sent).
  final List<String?> skipReasons = <String?>[];
  var reportCalls = 0;

  UserHumorProfile get profile => _profile;

  /// The rating currently stored for [contentId], if any.
  HumorRating? ratingOf(String contentId) => _ratings[contentId];

  /// Content ids passed without a rating.
  Set<String> get passedContentIds => Set.unmodifiable(_passed);

  bool _interacted(String contentId) =>
      _ratings.containsKey(contentId) || _passed.contains(contentId);

  static const seedCatalog = <HumorContent>[
    HumorContent(
      contentId: 'hc_tr_vid_001',
      type: HumorContentType.video,
      language: 'tr',
      category: HumorCategory.absurd,
      humorTags: ['absürt', 'video'],
      textBody: 'Alarm değil, sabah sabotajı.',
      downloadUrl:
          'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
      durationMs: 10000,
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
          'https://test-videos.co.uk/vids/sintel/mp4/h264/360/Sintel_360_10s_1MB.mp4',
      durationMs: 10000,
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
          'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
      durationMs: 10000,
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
          'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
      durationMs: 5055,
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
          'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
      durationMs: 5055,
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
          'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
      durationMs: 10000,
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
          'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
      durationMs: 10000,
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

  int get _completedCalibration =>
      _ratings.length > HumorCalibration.totalInteractions
      ? HumorCalibration.totalInteractions
      : _ratings.length;

  /// Last position (exclusive) of the stage [completedCount] is in. A
  /// calibration page never crosses it, so the next stage is chosen only after
  /// the current one has been rated — the server contract.
  static int _stageEnd(int completedCount) {
    const anchorEnd = HumorCalibration.anchorInteractions;
    const adaptiveEnd = anchorEnd + HumorCalibration.adaptiveInteractions;
    if (completedCount < anchorEnd) {
      return anchorEnd;
    }
    if (completedCount < adaptiveEnd) {
      return adaptiveEnd;
    }
    return HumorCalibration.totalInteractions;
  }

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
    int rank(HumorContent item) {
      final index = preferred.indexOf(item.language);
      return index < 0 ? 99 : index;
    }

    // Stable: equal ranks keep catalog order, so an id cursor stays valid.
    final ranked = [for (var i = 0; i < _items.length; i += 1) (i, _items[i])]
      ..sort((a, b) {
        final byRank = rank(a.$2).compareTo(rank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    final ordered = [for (final entry in ranked) entry.$2];
    final open = ordered.where((item) => !_interacted(item.contentId)).toList();
    final state = calibration;
    if (!state.complete) {
      // Calibration owns the page: content the user has not interacted with,
      // each tagged with the stage of the position it would occupy, and never
      // more than what is left of the current stage — the same contract the
      // server returns, so controller/UI behaviour matches mock and real.
      final wanted = _stageEnd(state.completedCount) - state.completedCount;
      final take = wanted < open.length ? wanted : open.length;
      if (take > 0) {
        final page = <HumorContent>[
          for (var i = 0; i < take; i += 1)
            open[i].copyWithCalibrationStage(
              _stageFor(state.completedCount + i),
            ),
        ];
        return HumorFeedPage(
          items: page,
          nextCursor: null,
          profileBuilding: true,
          interactionCount: _profile.interactionCount,
          calibration: state.copyWith(
            insufficientPool: open.length < state.remaining,
          ),
        );
      }
      // Nothing left to serve for calibration: fall through to the ordinary
      // path exactly as the server does, so the catalog state is reported
      // rather than hidden behind an empty calibration page.
    }

    // Mirror the server contract: content the user has not interacted with,
    // walked in catalog order from an item-id cursor. An index cursor would
    // skip items, because the unrated list shrinks as the user rates.
    var start = 0;
    if (cursor != null && cursor.isNotEmpty) {
      final at = ordered.indexWhere((item) => item.contentId == cursor);
      start = at < 0 ? 0 : at + 1;
    }
    final page = <HumorContent>[];
    var last = start - 1;
    for (var i = start; i < ordered.length && page.length < pageSize; i += 1) {
      last = i;
      if (!_interacted(ordered[i].contentId)) {
        page.add(ordered[i]);
      }
    }
    final moreAfter = ordered
        .skip(last + 1)
        .any((item) => !_interacted(item.contentId));
    return HumorFeedPage(
      items: page,
      nextCursor: page.isNotEmpty && moreAfter ? page.last.contentId : null,
      // Reached through the fall-through above as well, where calibration is
      // still running — so this tracks the real state rather than assuming.
      profileBuilding: !state.complete,
      interactionCount: _profile.interactionCount,
      calibration: state,
      catalogExhausted: open.isEmpty && _items.isNotEmpty,
      catalogEmpty: _items.isEmpty,
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    if (failProfile) {
      throw StateError('mock-profile-failed');
    }
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
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    feedbackCalls += 1;
    await feedbackGate?.future;
    if (failFeedback) {
      throw StateError('mock-feedback-failed');
    }
    // Only a real rating counts, once per content. A skip or report marker is
    // not a rating, so rating that content later is its first rating; rating
    // it again replaces the earlier rating without counting twice.
    final firstRating = !_ratings.containsKey(contentId);
    _ratings[contentId] = rating;
    _passed.remove(contentId);
    // Lifetime learning keeps counting past calibration, exactly like the
    // server: only the calibration milestone freezes at 15.
    final nextCount = _profile.interactionCount + (firstRating ? 1 : 0);
    final confidence = (nextCount / 40).clamp(0.0, 1.0);
    final state = calibration;
    _profile = _profile.copyWith(
      confidence: confidence,
      interactionCount: nextCount,
      profileBuilding: !state.complete,
      calibration: state,
    );
    return _feedbackResult();
  }

  @override
  Future<HumorFeedbackResult> skipContent({
    required String contentId,
    String? skipReason,
  }) async {
    feedbackCalls += 1;
    skipCalls += 1;
    skipReasons.add(skipReason);
    await feedbackGate?.future;
    if (failFeedback) {
      throw StateError('mock-skip-failed');
    }
    // Never touches the profile, the count or calibration. An existing
    // rating wins: skipping rated content is a no-op.
    if (!_ratings.containsKey(contentId)) {
      _passed.add(contentId);
    }
    return _feedbackResult();
  }

  HumorFeedbackResult _feedbackResult() {
    final state = calibration;
    return HumorFeedbackResult(
      ok: true,
      profileBuilding: !state.complete,
      interactionCount: _profile.interactionCount,
      confidence: _profile.confidence,
      calibration: state,
    );
  }

  @override
  Future<HumorCompatibility> getMatchCompatibility(String matchId) async {
    // The mock only knows this user's side. It reports "building" while that
    // side is unfinished — true whatever the peer did — and otherwise stays
    // silent: inventing a peer or a score would put a fake reading in a real
    // chat.
    if (!calibration.complete) {
      return const HumorCompatibility(
        available: false,
        reason: HumorCompatibility.reasonBuilding,
      );
    }
    return HumorCompatibility.unavailable;
  }

  @override
  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) async {
    reportCalls += 1;
    if (failReport) {
      throw StateError('mock-report-failed');
    }
    // The report marker keeps the content out of the reporter's feed but
    // never overwrites a rating they already gave.
    if (!_ratings.containsKey(contentId)) {
      _passed.add(contentId);
    }
  }

  // ---------------------------------------------------------------------------
  // Daily humor ("Bugünün Mizah Turu")
  // ---------------------------------------------------------------------------

  /// Items in a mock day, matching the server's set size.
  static const dailySetSize = 10;

  /// The canonical day. Defaults to today in Europe/Istanbul (UTC+3).
  String dailyDayId = _istanbulDayId(DateTime.now());

  /// Report `locked` / `starts_tomorrow` once calibration is complete, as the
  /// server does on the day calibration finished.
  var dailyStartsTomorrow = false;

  /// Report `not_ready` once calibration is complete.
  var dailyNotReady = false;

  /// Make every daily call fail as a network error would.
  var failDaily = false;

  /// When set, daily submissions wait for it — holds one in flight.
  Completer<void>? dailyGate;
  var dailySetCalls = 0;
  var dailySubmitCalls = 0;
  var dailySkipCalls = 0;

  String? _dailyItemsDay;
  List<HumorContent> _dailyItems = const [];
  final Map<int, HumorDailyAnswer> _dailyAnswers = {};

  /// Answers recorded for today's set, by slot index.
  Map<int, HumorDailyAnswer> get dailyAnswers =>
      Map.unmodifiable(_dailyAnswers);

  static String _istanbulDayId(DateTime now) {
    final local = now.toUtc().add(const Duration(hours: 3));
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }

  /// Roll the canonical day over to [nextDayId]: a submission for the old
  /// day is then refused with `day-closed`, and the next load starts fresh.
  void closeDay(String nextDayId) {
    dailyDayId = nextDayId;
  }

  /// Answer the first [count] slots of today's set, as another session.
  void seedDailyProgress(int count) {
    final items = _ensureDailyItems();
    for (var i = 0; i < count && i < items.length; i += 1) {
      _dailyAnswers[i] = HumorDailyAnswer(
        index: i,
        contentId: items[i].contentId,
        rating: HumorRating.funny,
      );
    }
  }

  /// Today's fixed order: content the user has not seen first, then the rest
  /// of the catalog. Frozen per day, like the server's set.
  List<HumorContent> _ensureDailyItems() {
    if (_dailyItemsDay != dailyDayId) {
      _dailyItemsDay = dailyDayId;
      _dailyAnswers.clear();
      final fresh = _items.where((item) => !_interacted(item.contentId));
      final seen = _items.where((item) => _interacted(item.contentId));
      _dailyItems = [...fresh, ...seen].take(dailySetSize).toList();
    }
    return _dailyItems;
  }

  int get _dailyNextIndex {
    for (var i = 0; i < _dailyItems.length; i += 1) {
      if (!_dailyAnswers.containsKey(i)) {
        return i;
      }
    }
    return _dailyItems.length;
  }

  @override
  Future<HumorDailySet> getDailySet() async {
    dailySetCalls += 1;
    if (failDaily) {
      throw StateError('mock-daily-failed');
    }
    if (!calibration.complete) {
      return HumorDailySet(
        status: HumorDailyStatus.locked,
        lockedReason: HumorDailyLockedReason.calibrationIncomplete,
        dayId: dailyDayId,
      );
    }
    if (dailyStartsTomorrow) {
      return HumorDailySet(
        status: HumorDailyStatus.locked,
        lockedReason: HumorDailyLockedReason.startsTomorrow,
        dayId: dailyDayId,
      );
    }
    final items = _ensureDailyItems();
    if (dailyNotReady || items.isEmpty) {
      return HumorDailySet(
        status: HumorDailyStatus.notReady,
        dayId: dailyDayId,
      );
    }
    final answered = _dailyAnswers.length;
    final entries = _dailyAnswers.keys.toList()..sort();
    return HumorDailySet(
      status: HumorDailyStatus.ready,
      dayId: dailyDayId,
      total: items.length,
      answeredCount: answered,
      completed: answered >= items.length,
      nextIndex: _dailyNextIndex,
      items: List.unmodifiable(items),
      answers: [for (final index in entries) _dailyAnswers[index]!],
    );
  }

  @override
  Future<HumorDailyProgress> submitDailyResponse({
    required String dayId,
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
  }) async {
    dailySubmitCalls += 1;
    return _answerDaily(dayId, contentId, rating: rating);
  }

  @override
  Future<HumorDailyProgress> skipDailyItem({
    required String dayId,
    required String contentId,
  }) async {
    dailySkipCalls += 1;
    return _answerDaily(dayId, contentId, skipped: true);
  }

  /// Mirrors the server: idempotent per slot, refused once the day closed.
  Future<HumorDailyProgress> _answerDaily(
    String dayId,
    String contentId, {
    HumorRating? rating,
    bool skipped = false,
  }) async {
    await dailyGate?.future;
    if (failDaily) {
      throw StateError('mock-daily-failed');
    }
    if (!calibration.complete) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'not-eligible',
      );
    }
    if (dayId != dailyDayId) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'day-closed',
      );
    }
    final items = _ensureDailyItems();
    final index = items.indexWhere((item) => item.contentId == contentId);
    if (index < 0) {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'content-unavailable',
      );
    }
    final already = _dailyAnswers.containsKey(index);
    if (!already) {
      _dailyAnswers[index] = HumorDailyAnswer(
        index: index,
        contentId: contentId,
        rating: rating,
        skipped: skipped,
      );
    }
    final answered = _dailyAnswers.length;
    return HumorDailyProgress(
      dayId: dailyDayId,
      total: items.length,
      answeredCount: answered,
      completed: answered >= items.length,
      nextIndex: _dailyNextIndex,
      alreadyAnswered: already,
    );
  }
}
