import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';

/// Where the user's "Bugünün Mizah Turu" stands, as `getDailyHumorSet` says.
enum HumorDailyStatus {
  /// Today's set exists and can be played (or has been finished).
  ready,

  /// The user cannot have a daily set yet; see [HumorDailyLockedReason].
  locked,

  /// The day's set is still being prepared. Never filled with other content.
  notReady;

  /// Anything unknown is treated as [notReady]: calm, and never a CTA.
  static HumorDailyStatus parse(Object? raw) {
    switch (raw) {
      case 'ready':
        return HumorDailyStatus.ready;
      case 'locked':
        return HumorDailyStatus.locked;
      default:
        return HumorDailyStatus.notReady;
    }
  }
}

enum HumorDailyLockedReason {
  /// Initial calibration is not finished; the calibration entry covers this.
  calibrationIncomplete,

  /// Calibration finished today; the first daily set arrives tomorrow.
  startsTomorrow,

  /// Every item of the sequence is behind the user; nothing is left to ask.
  sequenceComplete,

  /// Locked for a reason this build does not know.
  unknown;

  static HumorDailyLockedReason? parse(Object? raw) {
    switch (raw) {
      case null:
        return null;
      case 'calibration_incomplete':
        return HumorDailyLockedReason.calibrationIncomplete;
      case 'starts_tomorrow':
        return HumorDailyLockedReason.startsTomorrow;
      case 'sequence_complete':
        return HumorDailyLockedReason.sequenceComplete;
      default:
        return HumorDailyLockedReason.unknown;
    }
  }
}

/// One answered slot of today's set.
class HumorDailyAnswer {
  const HumorDailyAnswer({
    required this.index,
    required this.contentId,
    this.rating,
    this.skipped = false,
  });

  final int index;
  final String contentId;

  /// `null` when the slot was passed because its media failed.
  final HumorRating? rating;
  final bool skipped;

  static HumorDailyAnswer? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final contentId = raw['contentId'];
    if (contentId is! String || contentId.isEmpty) {
      return null;
    }
    return HumorDailyAnswer(
      index: firestoreInt(raw['index'], -1),
      contentId: contentId,
      rating: HumorRating.tryParse(raw['rating'] as String?),
      skipped: raw['skipped'] == true,
    );
  }
}

/// Server-authoritative progress through today's set, as returned by
/// `submitDailyHumorResponse`. The client never advances past it locally.
class HumorDailyProgress {
  const HumorDailyProgress({
    required this.dayId,
    this.setVersion = 1,
    required this.total,
    required this.answeredCount,
    required this.completed,
    required this.nextIndex,
    this.alreadyAnswered = false,
  });

  final String dayId;
  final int setVersion;
  final int total;
  final int answeredCount;
  final bool completed;

  /// Index of the first unanswered slot; equals [total] once completed.
  final int nextIndex;

  /// The slot had been answered before (an idempotent resubmit).
  final bool alreadyAnswered;

  factory HumorDailyProgress.fromMap(Map<String, dynamic> map) {
    final total = _nonNegative(map['total'], 0);
    final answered = _nonNegative(map['answeredCount'], 0).clamp(0, total);
    final completed =
        map['completed'] == true || (total > 0 && answered >= total);
    return HumorDailyProgress(
      dayId: _text(map['dayId']),
      setVersion: firestoreInt(map['setVersion'], 1),
      total: total,
      answeredCount: answered,
      completed: completed,
      nextIndex: _nextIndex(map['nextIndex'], answered, total, completed),
      alreadyAnswered: map['alreadyAnswered'] == true,
    );
  }
}

/// Today's "Bugünün Mizah Turu": a fixed, server-ordered set of items the user
/// rates one at a time, resumable across sessions.
class HumorDailySet {
  const HumorDailySet({
    required this.status,
    this.lockedReason,
    this.dayId = '',
    this.setVersion = 1,
    this.total = 0,
    this.answeredCount = 0,
    this.completed = false,
    this.nextIndex = 0,
    this.items = const [],
    this.answers = const [],
  });

  static const notReady = HumorDailySet(status: HumorDailyStatus.notReady);

  final HumorDailyStatus status;

  /// Set only while [status] is [HumorDailyStatus.locked].
  final HumorDailyLockedReason? lockedReason;

  /// Canonical server day (Europe/Istanbul), e.g. `2026-09-29`.
  final String dayId;
  final int setVersion;
  final int total;
  final int answeredCount;
  final bool completed;

  /// Index into [items] of the first unanswered slot (== [total] when done).
  final int nextIndex;

  /// Exactly [total] items, in the order they are played, while [isReady].
  final List<HumorContent> items;

  /// Answered slots only.
  final List<HumorDailyAnswer> answers;

  bool get isReady => status == HumorDailyStatus.ready;
  bool get isLocked => status == HumorDailyStatus.locked;
  bool get isNotReady => status == HumorDailyStatus.notReady;

  /// The daily entry card is shown only for a ready set.
  bool get showsEntryCard => isReady;

  bool get startsTomorrow =>
      isLocked && lockedReason == HumorDailyLockedReason.startsTomorrow;

  /// Nothing is left: the user has been through every item there is.
  bool get sequenceComplete =>
      isLocked && lockedReason == HumorDailyLockedReason.sequenceComplete;

  /// Started but not finished.
  bool get inProgress => isReady && !completed && answeredCount > 0;

  /// Unknown or malformed data degrades to [notReady] rather than throwing,
  /// and a "ready" set that carries nothing to play is never shown as ready.
  factory HumorDailySet.fromMap(Map<String, dynamic> map) {
    final status = HumorDailyStatus.parse(map['status']);
    if (status == HumorDailyStatus.locked) {
      return HumorDailySet(
        status: status,
        lockedReason:
            HumorDailyLockedReason.parse(map['lockedReason']) ??
            HumorDailyLockedReason.unknown,
        dayId: _text(map['dayId']),
        setVersion: firestoreInt(map['setVersion'], 1),
      );
    }
    if (status == HumorDailyStatus.notReady) {
      return HumorDailySet(
        status: status,
        dayId: _text(map['dayId']),
        setVersion: firestoreInt(map['setVersion'], 1),
      );
    }
    final items = HumorContent.listFromFeed(map['items']);
    final sentTotal = _nonNegative(map['total'], items.length);
    final total = sentTotal == 0 ? items.length : sentTotal;
    final answered = _nonNegative(map['answeredCount'], 0).clamp(0, total);
    final completed =
        map['completed'] == true || (total > 0 && answered >= total);
    final dayId = _text(map['dayId']);
    if (total == 0 || dayId.isEmpty || (!completed && items.isEmpty)) {
      return HumorDailySet(status: HumorDailyStatus.notReady, dayId: dayId);
    }
    final answers = <HumorDailyAnswer>[];
    final rawAnswers = map['answers'];
    if (rawAnswers is List) {
      for (final raw in rawAnswers) {
        final answer = HumorDailyAnswer.tryParse(raw);
        if (answer != null) {
          answers.add(answer);
        }
      }
    }
    return HumorDailySet(
      status: status,
      dayId: dayId,
      setVersion: firestoreInt(map['setVersion'], 1),
      total: total,
      answeredCount: answered,
      completed: completed,
      nextIndex: _nextIndex(map['nextIndex'], answered, total, completed),
      items: items,
      answers: answers,
    );
  }

  /// This set with the server's latest [progress] applied.
  HumorDailySet withProgress(HumorDailyProgress progress) {
    return HumorDailySet(
      status: status,
      lockedReason: lockedReason,
      dayId: dayId,
      setVersion: progress.setVersion,
      total: progress.total > 0 ? progress.total : total,
      answeredCount: progress.answeredCount,
      completed: progress.completed,
      nextIndex: progress.nextIndex,
      items: items,
      answers: answers,
    );
  }
}

/// What the entry card's call to action says.
enum HumorDailyCta {
  /// Nothing answered yet: "Başla".
  start,

  /// Part-way through: "Devam et · 4/10".
  resume,

  /// Finished for today: a quiet, non-interactive "Bugünlük tamam ✓".
  done;

  static HumorDailyCta of(HumorDailySet set) {
    if (set.completed) {
      return HumorDailyCta.done;
    }
    return set.answeredCount > 0 ? HumorDailyCta.resume : HumorDailyCta.start;
  }
}

/// Why a submission was refused because the client's picture of the day is
/// out of date. Every one of them means: reload `getDailyHumorSet`.
enum HumorDailyStaleReason {
  /// The canonical day rolled over; continue with the new day.
  dayClosed,

  /// The slot's content was replaced by an admin repair.
  slotReplaced,

  /// The user is no longer eligible; the reload reports a locked state.
  notEligible,

  /// The content is gone; treated like [slotReplaced].
  contentUnavailable,

  /// Any other `failed-precondition`.
  other,
}

/// The result of one daily rating or media-failed skip.
sealed class HumorDailySubmitOutcome {
  const HumorDailySubmitOutcome();
}

/// The server recorded the answer (or had already recorded it).
final class HumorDailyAccepted extends HumorDailySubmitOutcome {
  const HumorDailyAccepted(this.progress);

  final HumorDailyProgress progress;
}

/// The server refused it because the day, slot or eligibility changed.
final class HumorDailyStale extends HumorDailySubmitOutcome {
  const HumorDailyStale(this.reason);

  final HumorDailyStaleReason reason;
}

String _text(Object? value) => value is String ? value.trim() : '';

int _nonNegative(Object? value, int fallback) {
  final parsed = firestoreInt(value, fallback);
  return parsed < 0 ? 0 : parsed;
}

int _nextIndex(Object? raw, int answered, int total, bool completed) {
  if (completed) {
    return total;
  }
  final parsed = firestoreInt(raw, answered);
  if (parsed < 0) {
    return 0;
  }
  return parsed > total ? total : parsed;
}
