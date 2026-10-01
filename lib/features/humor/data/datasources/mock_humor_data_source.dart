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
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';

/// In-memory Humor Lab with Turkish-first real playable media URLs.
///
/// Mirrors the server contract of the Humor Core sequence, so controllers and
/// UI behave the same against the mock and the real backend: the catalogue *in
/// order* is the canonical sequence (the first item is V1), the first
/// [onboardingCount] are the initial calibration, and afterwards a day holds
/// at most [dailySetSize] — frozen once touched, never more until [closeDay].
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

  /// Items in the initial calibration, as the server's sequence defines it.
  static const onboardingCount = 15;

  /// Most items in a day after the calibration, matching the server.
  static const dailySetSize = 5;

  /// Days of failing media after which an item is waived for the user.
  static const _waiveAfterFailedDays = 2;

  final List<HumorContent> _items;
  UserHumorProfile _profile;

  /// Real ratings, one per content id — a re-rate replaces, never adds.
  final Map<String, HumorRating> _ratings = {};

  /// Items the user is excused from: reported, or media that failed on two
  /// days. Never a rating.
  final Set<String> _waived = {};

  /// Days on which an item's media would not play, by content id.
  final Map<String, Set<String>> _mediaFailedDays = {};

  /// The calibration is behind the user (set on the rating that finished it).
  var _calibrated = false;

  /// The day that has been touched, and the ids frozen as its set.
  String? _frozenDay;
  List<String> _frozenIds = const [];
  var _frozenOnboarding = false;

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

  /// Content ids waived for the user (reported, or media failed twice).
  Set<String> get waivedContentIds => Set.unmodifiable(_waived);

  /// Content ids whose media failed today: done for today, back tomorrow.
  Set<String> get deferredContentIds => {
    for (final entry in _mediaFailedDays.entries)
      if (entry.value.contains(dailyDayId) && !_resolved(entry.key)) entry.key,
  };

  /// The canonical order: V1 is the first id.
  List<String> get sequenceIds => [for (final item in _items) item.contentId];

  /// The ids of the day's set, in order (frozen once the day is touched).
  List<String> get todayIds => List.unmodifiable(_today().ids);

  bool _resolved(String contentId) =>
      _ratings.containsKey(contentId) || _waived.contains(contentId);

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
    // Enough content to walk the whole initial calibration locally.
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
    // Six more, so the mock sequence holds two full days after calibration.
    HumorContent(
      contentId: 'hc_tr_img_017',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.absurd,
      humorTags: ['absürt'],
      textBody: 'Kedi toplantıya katıldı. En mantıklı fikir ondan çıktı.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-17/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-17/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_012',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.silly,
      humorTags: ['saçma'],
      textBody: 'Çorabın teki yine tatile çıkmış.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-12/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-12/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_013',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.teasing,
      humorTags: ['takılma'],
      textBody: 'Bu kadar hazırlık beş dakikalık bir kahve için miydi?',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-13/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-13/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_014',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.romantic,
      humorTags: ['romantik', 'espri'],
      textBody: 'Son dilimi sana bıraktım. Evet, bu aşk.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-14/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-14/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_015',
      type: HumorContentType.image,
      language: 'tr',
      category: HumorCategory.dark,
      humorTags: ['kara mizah'],
      textBody: 'Spor salonu üyeliğim benden daha çok dinleniyor.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-15b/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-15b/540/960',
      aspectRatio: 9 / 16,
    ),
    HumorContent(
      contentId: 'hc_tr_img_016',
      type: HumorContentType.meme,
      language: 'tr',
      category: HumorCategory.dry,
      humorTags: ['kuru'],
      textBody: 'Toplantı e-posta olabilirdi. E-posta da olmayabilirdi.',
      downloadUrl: 'https://picsum.photos/seed/mevora-tr-16/1080/1920',
      thumbUrl: 'https://picsum.photos/seed/mevora-tr-16/540/960',
      aspectRatio: 9 / 16,
    ),
  ];

  // ---------------------------------------------------------------------------
  // The canonical sequence
  // ---------------------------------------------------------------------------

  /// The canonical day. Defaults to today in Europe/Istanbul (UTC+3).
  String dailyDayId = _istanbulDayId(DateTime.now());

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

  List<HumorContent> get _onboarding =>
      _items.take(onboardingCount).toList(growable: false);

  bool get _onboardingFinished =>
      _calibrated ||
      (_onboarding.isNotEmpty &&
          _onboarding.every((item) => _resolved(item.contentId)));

  /// Today's set: the frozen ids once the day is touched; before that what is
  /// left of the calibration, or the first [dailySetSize] open items.
  ({List<String> ids, bool onboarding}) _today() {
    if (_frozenDay == dailyDayId) {
      return (ids: _frozenIds, onboarding: _frozenOnboarding);
    }
    if (!_onboardingFinished) {
      return (
        ids: [
          for (final item in _onboarding)
            if (!_resolved(item.contentId)) item.contentId,
        ],
        onboarding: true,
      );
    }
    return (
      ids: [
        for (final item in _items)
          if (!_resolved(item.contentId)) item.contentId,
      ].take(dailySetSize).toList(),
      onboarding: false,
    );
  }

  /// The first response of a day freezes its set.
  void _freeze() {
    if (_frozenDay == dailyDayId) {
      return;
    }
    final set = _today();
    _frozenDay = dailyDayId;
    _frozenIds = List.unmodifiable(set.ids);
    _frozenOnboarding = set.onboarding;
  }

  bool _deferredToday(String contentId) =>
      !_resolved(contentId) &&
      (_mediaFailedDays[contentId]?.contains(dailyDayId) ?? false);

  /// Done with [contentId] for today: rated, waived, or media failed today.
  bool _doneToday(String contentId) =>
      _resolved(contentId) || _deferredToday(contentId);

  HumorContent _itemOf(String contentId) =>
      _items.firstWhere((item) => item.contentId == contentId);

  /// A response is only ever accepted for an item of today's set.
  void _requireInToday(String contentId, {String message = 'not-in-set'}) {
    if (!_today().ids.contains(contentId)) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: message,
      );
    }
  }

  void _settle() {
    if (!_calibrated && _onboardingFinished) {
      _calibrated = true;
    }
  }

  /// Finish the calibration as on an earlier day: V1 … V15 rated, and today
  /// untouched — so the daily tour is available right away.
  void completeCalibration({HumorRating rating = HumorRating.funny}) {
    var added = 0;
    for (final item in _onboarding) {
      if (!_resolved(item.contentId)) {
        _ratings[item.contentId] = rating;
        added += 1;
      }
    }
    _calibrated = true;
    final count = _profile.interactionCount + added;
    _profile = _profile.copyWith(
      interactionCount: count,
      confidence: (count / 40).clamp(0.0, 1.0),
      profileBuilding: false,
      calibration: calibration,
    );
  }

  HumorCalibration get calibration {
    final total = _onboarding.length;
    final finished = _onboardingFinished;
    final today = _today();
    final paused =
        !finished &&
        total > 0 &&
        today.onboarding &&
        today.ids.every(_doneToday);
    return HumorCalibration(
      stage: finished
          ? HumorCalibrationStage.complete
          : HumorCalibrationStage.anchor,
      completedCount: finished
          ? total
          : _onboarding.where((item) => _resolved(item.contentId)).length,
      totalCount: total,
      complete: finished,
      insufficientPool: total == 0,
      continuesTomorrow: paused,
    );
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
    // Nothing in the request selects content: the same items, in the same
    // order, for everyone — the server contract.
    final state = calibration;
    final today = _today();
    final open = !state.complete && today.onboarding
        ? [
            for (final id in today.ids)
              if (!_doneToday(id)) _itemOf(id),
          ]
        : const <HumorContent>[];
    return HumorFeedPage(
      items: open,
      nextCursor: null,
      profileBuilding: !state.complete,
      interactionCount: _profile.interactionCount,
      calibration: state,
      // Once the calibration is finished the feed is closed; while it is
      // paused for today there is nothing more to page through either.
      catalogExhausted:
          _items.isNotEmpty && (state.complete || state.continuesTomorrow),
      catalogEmpty: _items.isEmpty,
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    if (failProfile) {
      throw StateError('mock-profile-failed');
    }
    // Like the server: the profile carries progress, not the feed-only flags.
    final state = calibration.copyWith(
      insufficientPool: false,
      continuesTomorrow: false,
    );
    return _profile.copyWith(
      calibration: state,
      profileBuilding: !state.complete,
    );
  }

  /// One rating for [contentId]: counted once, replaced when it changes.
  void _rate(String contentId, HumorRating rating) {
    _freeze();
    final firstRating = !_ratings.containsKey(contentId);
    _ratings[contentId] = rating;
    _waived.remove(contentId);
    _settle();
    // Lifetime learning keeps counting past calibration, exactly like the
    // server: the daily items teach the same profile.
    final nextCount = _profile.interactionCount + (firstRating ? 1 : 0);
    final state = calibration;
    _profile = _profile.copyWith(
      confidence: (nextCount / 40).clamp(0.0, 1.0),
      interactionCount: nextCount,
      profileBuilding: !state.complete,
      calibration: state,
    );
  }

  /// The media of [contentId] would not play: never a rating. Done for today,
  /// offered again tomorrow, waived after a second failed day.
  void _mediaFailed(String contentId) {
    _freeze();
    if (_resolved(contentId)) {
      return;
    }
    final days = _mediaFailedDays.putIfAbsent(contentId, () => <String>{})
      ..add(dailyDayId);
    if (days.length >= _waiveAfterFailedDays) {
      _waived.add(contentId);
    }
    _settle();
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
    _requireInToday(contentId);
    _rate(contentId, rating);
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
    // Only media that would not play is recorded. A plain "not interested"
    // records nothing: the item is a measurement and stays open.
    if (skipReason == HumorSkipReason.mediaFailed) {
      _requireInToday(contentId);
      _mediaFailed(contentId);
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
      // Like the server: the feed-only flags are not part of this payload.
      calibration: state.copyWith(
        insufficientPool: false,
        continuesTomorrow: false,
      ),
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
    // A reported item of today's set is waived for the reporter; a rating
    // they already gave stands.
    if (_today().ids.contains(contentId) && !_ratings.containsKey(contentId)) {
      _freeze();
      _waived.add(contentId);
      _settle();
    }
  }

  // ---------------------------------------------------------------------------
  // Daily humor ("Bugünün Mizah Turu")
  // ---------------------------------------------------------------------------

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

  /// What is recorded for today's set, by position.
  Map<int, HumorDailyAnswer> get dailyAnswers {
    final ids = _today().ids;
    return Map.unmodifiable({
      for (var i = 0; i < ids.length; i += 1)
        if (_doneToday(ids[i]))
          i: HumorDailyAnswer(
            index: i,
            contentId: ids[i],
            rating: _ratings[ids[i]],
            skipped: !_ratings.containsKey(ids[i]),
          ),
    });
  }

  /// Answer the first [count] items of today's set, as another session.
  void seedDailyProgress(int count) {
    final ids = _today().ids;
    for (var i = 0; i < count && i < ids.length; i += 1) {
      _rate(ids[i], HumorRating.funny);
    }
  }

  HumorDailySet _locked(HumorDailyLockedReason reason) => HumorDailySet(
    status: HumorDailyStatus.locked,
    lockedReason: reason,
    dayId: dailyDayId,
  );

  HumorDailyProgress _dailyProgress({bool alreadyAnswered = false}) {
    final ids = _today().ids;
    final done = ids.where(_doneToday).length;
    final next = ids.indexWhere((id) => !_doneToday(id));
    return HumorDailyProgress(
      dayId: dailyDayId,
      total: ids.length,
      answeredCount: done,
      completed: ids.isNotEmpty && done >= ids.length,
      nextIndex: next < 0 ? ids.length : next,
      alreadyAnswered: alreadyAnswered,
    );
  }

  @override
  Future<HumorDailySet> getDailySet() async {
    dailySetCalls += 1;
    if (failDaily) {
      throw StateError('mock-daily-failed');
    }
    if (!calibration.complete) {
      return _locked(HumorDailyLockedReason.calibrationIncomplete);
    }
    if (dailyStartsTomorrow) {
      return _locked(HumorDailyLockedReason.startsTomorrow);
    }
    if (dailyNotReady) {
      return HumorDailySet(
        status: HumorDailyStatus.notReady,
        dayId: dailyDayId,
      );
    }
    final today = _today();
    if (today.onboarding) {
      // The calibration was finished today: the daily items start tomorrow.
      return _locked(HumorDailyLockedReason.startsTomorrow);
    }
    if (today.ids.isEmpty) {
      return _locked(HumorDailyLockedReason.sequenceComplete);
    }
    final progress = _dailyProgress();
    final answers = dailyAnswers;
    return HumorDailySet(
      status: HumorDailyStatus.ready,
      dayId: dailyDayId,
      total: progress.total,
      answeredCount: progress.answeredCount,
      completed: progress.completed,
      nextIndex: progress.nextIndex,
      items: List.unmodifiable([for (final id in today.ids) _itemOf(id)]),
      answers: [
        for (final index in answers.keys.toList()..sort()) answers[index]!,
      ],
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
    return _answerDaily(dayId, contentId);
  }

  /// Mirrors the server: refused once the day closed or for anything that is
  /// not one of today's items; idempotent per item; a media skip never
  /// overrides a rating.
  Future<HumorDailyProgress> _answerDaily(
    String dayId,
    String contentId, {
    HumorRating? rating,
  }) async {
    await dailyGate?.future;
    if (failDaily) {
      throw StateError('mock-daily-failed');
    }
    if (dayId != dailyDayId) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'day-closed',
      );
    }
    _requireInToday(contentId, message: 'slot-replaced');
    final already = rating == null
        ? _doneToday(contentId)
        : _ratings[contentId] == rating;
    if (!already) {
      if (rating == null) {
        _mediaFailed(contentId);
      } else {
        _rate(contentId, rating);
      }
    }
    return _dailyProgress(alreadyAnswered: already);
  }
}
