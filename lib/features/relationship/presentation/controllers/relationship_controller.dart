import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/domain/services/relationship_question_sets.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';

/// Hourly Istanbul matching game (default) or legacy Discovery dwell offer.
class RelationshipController extends ChangeNotifier with WidgetsBindingObserver {
  RelationshipController({
    required RelationshipRepository repository,
    Duration? interval,
    @Deprecated('Unused; Discovery visibility drives the timer')
    Duration idleTimeout = RelationshipQuestionConfig.idleTimeout,
    DateTime Function()? clock,
    bool? enforceOfferGates,
    bool? hourlyGlobalMatchingGame,
  }) : _repository = repository,
       _interval = interval ?? RelationshipQuestionConfig.interval,
       _clock = clock ?? DateTime.now,
       _enforceOfferGates =
           enforceOfferGates ?? !RelationshipQuestionConfig.bypassOfferGates,
       _hourlyGlobalMatchingGame =
           hourlyGlobalMatchingGame ??
           RelationshipQuestionConfig.hourlyGlobalMatchingGame;

  final RelationshipRepository _repository;
  final Duration _interval;
  final DateTime Function() _clock;
  final bool _enforceOfferGates;
  final bool _hourlyGlobalMatchingGame;

  Timer? _timer;
  Timer? _heartbeat;
  Timer? _roundPoll;
  Duration _elapsed = Duration.zero;
  DateTime? _runningSince;
  DateTime? _offerCooldownUntil;
  var _discoveryVisible = false;
  var _appPaused = false;
  var _observing = false;
  var _submitting = false;
  var _answersReady = false;
  var _sessionLocked = false;
  var _offerVisible = false;
  var _continuePromptVisible = false;
  var _resultsVisible = false;
  var _emptyResults = false;
  var _unavailable = false;
  var _waitingForRoundResult = false;
  var _normalMatchCount = 0;
  var _matchingEventCount = 0;
  var _matchingPaused = false;
  String? _lastError;
  String? _activeRoundId;
  MatchingGameRoundInfo? _roundInfo;
  Set<String> _answeredIds = {};
  final Map<String, String> _sessionAnswers = {};
  List<RelationshipQuestion> _session = const [];
  var _sessionIndex = 0;
  List<RelationshipMatchSuggestion> _suggestions = const [];
  List<RelationshipMatchSuggestion> _testResults = const [];

  Set<String> get answeredIds => _answeredIds;
  int get answeredCount => _answeredIds.length;
  int get totalCount => RelationshipQuestionCatalog.questions.length;
  int get sessionLength => _session.length;
  int get sessionIndex => _sessionIndex;
  int get normalMatchCount => _normalMatchCount;
  String? get lastError => _lastError;
  RelationshipQuestion? get currentQuestion {
    if (_sessionIndex < 0 || _sessionIndex >= _session.length) {
      return null;
    }
    return _session[_sessionIndex];
  }

  bool get isOfferVisible => _offerVisible;
  bool get isContinuePromptVisible => _continuePromptVisible;
  bool get isPromptVisible => currentQuestion != null;
  bool get isResultVisible => _resultsVisible;
  bool get hasEmptyResults => _emptyResults;
  bool get hasUnavailableFallback => _unavailable && !isPromptVisible;
  bool get submitting => _submitting;
  bool get sessionLocked => _sessionLocked;
  bool get waitingForRoundResult => _waitingForRoundResult;
  bool get hourlyGlobalMatchingGame => _hourlyGlobalMatchingGame;
  MatchingGameRoundInfo? get roundInfo => _roundInfo;
  String? get activeRoundId => _activeRoundId;

  /// Istanbul round hour digits for UI (e.g. "14"), from server round id.
  String? get hourlyRoundHour {
    if (!_hourlyGlobalMatchingGame) {
      return null;
    }
    final id = _activeRoundId ?? _roundInfo?.roundId;
    if (id == null || id.length < 10) {
      return null;
    }
    return id.substring(id.length - 2);
  }

  Duration? get hourlyCountdownRemaining {
    final round = _roundInfo;
    if (!_hourlyGlobalMatchingGame || round == null) {
      return null;
    }
    return round.timeUntilClose;
  }

  int get matchingEventCount => _matchingEventCount;
  bool get matchingPaused => _matchingPaused;
  Duration get interval => _interval;
  Duration get activeSwipeTime => _elapsed + _runningElapsed;
  List<RelationshipMatchSuggestion> get suggestions => _suggestions;
  List<RelationshipMatchSuggestion> get testResults => _testResults;

  Duration get _runningElapsed {
    final started = _runningSince;
    if (started == null) {
      return Duration.zero;
    }
    final delta = _clock().difference(started);
    return delta.isNegative ? Duration.zero : delta;
  }

  bool get _cooldownActive {
    final cooldown = _offerCooldownUntil;
    return cooldown != null && cooldown.isAfter(_clock());
  }

  Future<void> start() async {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    await refreshAnswered();
    unawaited(refreshSuggestions());
    _log(
      'Discovery active timer started '
      '(interval: ${_interval.inSeconds}s, gates: $_enforceOfferGates)',
    );
    if (_discoveryVisible) {
      _armTimer();
    }
  }

  void pause() {
    _pauseTimer();
    _roundPoll?.cancel();
    _roundPoll = null;
    if (!_observing) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  void setDiscoveryVisible(bool visible) {
    final opened = visible && !_discoveryVisible;
    final closed = !visible && _discoveryVisible;
    _discoveryVisible = visible;
    if (visible) {
      if (opened) {
        _log('Discovery visible');
        unawaited(refreshAnswered());
        if (_matchingPaused && _enforceOfferGates && !_sessionLocked) {
          _sessionLocked = true;
          _continuePromptVisible = true;
          notifyListeners();
          return;
        }
        _armTimer();
        return;
      }
      if (_timer == null && !_sessionLocked) {
        _armTimer();
      }
      return;
    }
    if (closed) {
      _log(
        'Discovery hidden — dwell timer paused at ${activeSwipeTime.inSeconds}s',
      );
    }
    _pauseTimer();
  }

  void setNormalMatchCount(int count) {
    if (_normalMatchCount == count) {
      return;
    }
    _normalMatchCount = count;
    _log('Active conversations: $count');
    // Hourly game: active chats no longer block participation.
    if (_hourlyGlobalMatchingGame) {
      return;
    }
    if (count > 0 && _enforceOfferGates && (_offerVisible || _continuePromptVisible)) {
      _offerVisible = false;
      _continuePromptVisible = false;
      _sessionLocked = false;
      notifyListeners();
    }
    if (count == 0 && _discoveryVisible && !_sessionLocked) {
      _armTimer();
    }
  }

  void recordDiscoveryActivity() {
    if (!_discoveryVisible || _sessionLocked) {
      return;
    }
    if (_timer == null) {
      _armTimer();
    }
  }

  Future<void> refreshAnswered() async {
    final result = await _repository.getAnswered();
    if (result.isSuccess) {
      final snapshot = result.valueOrNull;
      _answeredIds = snapshot?.answeredIds ?? {};
      _offerCooldownUntil = snapshot?.offerCooldownUntil;
      _matchingEventCount = snapshot?.matchingEventCount ?? 0;
      _matchingPaused = snapshot?.matchingPaused ?? false;
      _log('Answered ids loaded (${_answeredIds.length})');
      _log(
        'Cooldown until: ${_offerCooldownUntil?.toIso8601String() ?? 'none'} '
        'events=$_matchingEventCount paused=$_matchingPaused',
      );
    } else {
      _logFailure('Questions requested', result.failureOrNull);
      _log('Answered ids unavailable; using local catalog');
    }
    _answersReady = true;
    notifyListeners();
  }

  Future<void> refreshSuggestions() async {
    final result = await _repository.getSuggestions();
    if (result.isSuccess) {
      _suggestions = result.valueOrNull ?? const [];
      notifyListeners();
    } else {
      _logFailure('Suggestions refresh', result.failureOrNull);
    }
  }

  Future<void> acceptOffer() async {
    if (!_offerVisible || _submitting) {
      _log('Start button ignored (offer=$_offerVisible submitting=$_submitting)');
      return;
    }
    if (!_answersReady) {
      await refreshAnswered();
    }
    _log('Opening relationship test');
    _offerVisible = false;
    _lastError = null;
    _sessionAnswers.clear();
    if (_hourlyGlobalMatchingGame) {
      final roundId = _activeRoundId ?? _roundInfo?.roundId;
      if (roundId != null && roundId.isNotEmpty) {
        final joined = await _repository.joinMatchingGameRound(roundId);
        if (joined.isError) {
          _lastError = joined.failureOrNull?.message;
          _offerVisible = true;
          notifyListeners();
          return;
        }
        _activeRoundId = roundId;
      }
    }
    _log('Questions requested');
    final questions = RelationshipQuestionSets.nextUnanswered(_answeredIds);
    if (questions == null ||
        questions.length < RelationshipQuestionConfig.questionsPerSession) {
      _log('Questions received: 0');
      _unavailable = true;
      _sessionLocked = false;
      notifyListeners();
      return;
    }
    _session = questions;
    _sessionIndex = 0;
    _sessionLocked = true;
    _unavailable = false;
    _log('Questions received: ${_session.length}');
    _log('Question set: ${_session.map((item) => item.id).join(',')}');
    notifyListeners();
  }

  Future<void> dismissOffer() async {
    if (!_offerVisible) {
      return;
    }
    _log('Offer dismissed');
    _offerVisible = false;
    _sessionLocked = false;
    _elapsed = Duration.zero;
    await _applyCooldown(matchTaken: false);
    notifyListeners();
    if (_discoveryVisible) {
      _armTimer();
    }
  }

  Future<void> continueMatchingEvents() async {
    if (!_continuePromptVisible || _submitting) {
      return;
    }
    _log('Continue matching accepted');
    _continuePromptVisible = false;
    _matchingPaused = false;
    _submitting = true;
    notifyListeners();
    final result = await _repository.dismissOffer(continueMatching: true);
    _submitting = false;
    if (result.isSuccess) {
      final snapshot = result.valueOrNull;
      _matchingPaused = snapshot?.matchingPaused ?? false;
      _matchingEventCount =
          snapshot?.matchingEventCount ?? _matchingEventCount;
      _offerCooldownUntil = snapshot?.offerCooldownUntil;
    }
    _sessionLocked = true;
    _offerVisible = true;
    notifyListeners();
  }

  Future<void> pauseMatchingEvents() async {
    if (!_continuePromptVisible) {
      return;
    }
    _log('Continue matching declined — pausing events');
    _continuePromptVisible = false;
    _sessionLocked = false;
    _matchingPaused = true;
    _elapsed = Duration.zero;
    final result = await _repository.dismissOffer(pauseMatching: true);
    if (result.isSuccess) {
      _matchingPaused = result.valueOrNull?.matchingPaused ?? true;
      _matchingEventCount =
          result.valueOrNull?.matchingEventCount ?? _matchingEventCount;
    }
    notifyListeners();
  }

  Future<bool> answer(String answerId) async {
    final question = currentQuestion;
    if (question == null || _submitting || !_sessionLocked) {
      _log(
        'Answer ignored (question=${question?.id} submitting=$_submitting locked=$_sessionLocked)',
      );
      return false;
    }
    if (!question.hasAnswer(answerId)) {
      _log('Answer ignored — invalid id $answerId for ${question.id}');
      return false;
    }
    _submitting = true;
    _lastError = null;
    notifyListeners();
    _log('Question answers submitted ${question.id}=$answerId');
    final result = await _repository.saveAnswer(
      questionId: question.id,
      answerId: answerId,
    );
    if (result.isError) {
      _lastError = result.failureOrNull?.message;
      _logFailure('Answers save', result.failureOrNull);
      _submitting = false;
      notifyListeners();
      return false;
    }
    _answeredIds =
        result.valueOrNull?.answeredIds ?? {..._answeredIds, question.id};
    _sessionAnswers[question.id] = answerId;
    _log('Answers saved successfully ${question.id}=$answerId');
    _sessionIndex += 1;
    if (_sessionIndex >= _session.length) {
      final questionIds = _session.map((item) => item.id).toList();
      _session = const [];
      _sessionIndex = 0;
      if (_hourlyGlobalMatchingGame) {
        await _completeHourlyRound(questionIds);
        return true;
      }
      _log('Relationship pool query started');
      final completed = await _repository.completeTest(questionIds: questionIds);
      _submitting = false;
      _elapsed = Duration.zero;
      _runningSince = null;
      if (completed.isError) {
        _lastError = completed.failureOrNull?.message;
        _logFailure('completeRelationshipTest', completed.failureOrNull);
        _log('Candidates found: 0');
        _emptyResults = true;
        _resultsVisible = true;
        notifyListeners();
        return true;
      }
      _testResults = completed.valueOrNull ?? const [];
      _suggestions = _testResults;
      _matchingEventCount += 1;
      _log('Compatibility key generated: YES');
      _log('Matching event count: $_matchingEventCount');
      _log('Candidates found: ${_testResults.length}');
      for (final item in _testResults) {
        _log(
          'Candidate: ${item.candidate.uid} Distance: ${item.candidate.distanceKm} km',
        );
      }
      _log('Relationship matches created: ${_testResults.length}');
      _emptyResults = _testResults.isEmpty;
      _resultsVisible = true;
      _log('Result screen opened');
      notifyListeners();
      return true;
    }
    _submitting = false;
    _log('Opening question screen ${_sessionIndex + 1}/${_session.length}');
    notifyListeners();
    return true;
  }

  /// Closed result without taking the match → 3 min, then survey can return.
  Future<void> dismissResults() async {
    _resultsVisible = false;
    _emptyResults = false;
    _sessionLocked = false;
    _testResults = const [];
    _lastError = null;
    _elapsed = Duration.zero;
    await _applyCooldown(matchTaken: false);
    notifyListeners();
    if (_discoveryVisible) {
      _armTimer();
    }
  }

  /// User took the relationship match (open chat) → 30 min survey break.
  Future<void> acceptMatchResult() async {
    _resultsVisible = false;
    _emptyResults = false;
    _sessionLocked = false;
    _testResults = const [];
    _lastError = null;
    _elapsed = Duration.zero;
    await _applyCooldown(matchTaken: true);
    notifyListeners();
    if (_discoveryVisible) {
      _armTimer();
    }
  }

  void dismissUnavailable() {
    _unavailable = false;
    _sessionLocked = false;
    notifyListeners();
  }

  Future<void> _applyCooldown({required bool matchTaken}) async {
    final localUntil = _clock().add(
      RelationshipQuestionConfig.cooldownFor(matchTaken: matchTaken),
    );
    _offerCooldownUntil = localUntil;
    _log(
      matchTaken
          ? 'Match taken — survey pause ${_matchedMinutes}m'
          : 'No match taken — retry in ${_declinedMinutes}m',
    );
    final result = await _repository.dismissOffer(matchTaken: matchTaken);
    if (result.isSuccess) {
      _offerCooldownUntil =
          result.valueOrNull?.offerCooldownUntil ?? _offerCooldownUntil;
    } else {
      _logFailure('Persist offer cooldown', result.failureOrNull);
    }
  }

  int get _declinedMinutes =>
      RelationshipQuestionConfig.declinedCooldown.inMinutes;
  int get _matchedMinutes =>
      RelationshipQuestionConfig.matchedCooldown.inMinutes;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appPaused = false;
        if (_discoveryVisible && !_sessionLocked) {
          _log('App resumed — dwell timer continued');
          _armTimer();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _appPaused = true;
        _pauseTimer();
        _log(
          'App background — dwell timer paused at ${activeSwipeTime.inSeconds}s',
        );
        break;
    }
  }

  void _armTimer() {
    if (_hourlyGlobalMatchingGame) {
      unawaited(_syncHourlyRoundOffer());
      return;
    }
    if (!_discoveryVisible || _sessionLocked || _appPaused) {
      _log(
        'Dwell timer idle (visible=$_discoveryVisible locked=$_sessionLocked paused=$_appPaused)',
      );
      return;
    }
    if (_timer != null && _runningSince != null) {
      return;
    }
    _pauseTimer();
    if (_normalMatchCount > 0 && _enforceOfferGates) {
      _log('Dwell timer idle — user has an active conversation');
      _log('Relationship trigger condition: FALSE');
      return;
    }
    if (_matchingPaused && _enforceOfferGates) {
      _log('Dwell timer idle — matching paused after continue prompt');
      _log('Relationship trigger condition: FALSE');
      return;
    }
    if (_cooldownActive && _enforceOfferGates) {
      final wait = _offerCooldownUntil!.difference(_clock());
      _log('Dwell timer waiting on cooldown (${wait.inMinutes}m)');
      _log('Relationship trigger condition: FALSE');
      _timer = Timer(wait, _onElapsed);
      _startHeartbeat();
      return;
    }
    if (_normalMatchCount > 0) {
      _log('Debug bypass — existing matches will not block the offer');
    }
    if (_cooldownActive) {
      _log('Debug bypass — offer cooldown ignored');
    }
    final remaining = _interval - _elapsed;
    if (remaining <= Duration.zero) {
      _onElapsed();
      return;
    }
    _runningSince = _clock();
    _timer = Timer(remaining, _onElapsed);
    _startHeartbeat();
    _log(
      'Dwell timer armed for ${remaining.inSeconds}s (elapsed ${_elapsed.inSeconds}s)',
    );
  }

  Future<void> _syncHourlyRoundOffer() async {
    if (!_discoveryVisible || _sessionLocked || _appPaused) {
      return;
    }
    if (_offerVisible || _resultsVisible || _waitingForRoundResult) {
      return;
    }
    if (_matchingPaused && _enforceOfferGates) {
      return;
    }
    if (_cooldownActive && _enforceOfferGates) {
      return;
    }
    final roundResult = await _repository.getMatchingGameRound();
    if (roundResult.isError) {
      _logFailure('getMatchingGameRound', roundResult.failureOrNull);
      return;
    }
    final round = roundResult.valueOrNull;
    if (round == null || round.roundId.isEmpty) {
      return;
    }
    _roundInfo = round;
    _activeRoundId = round.roundId;
    notifyListeners();
    if (!round.isOpen) {
      _log('Hourly round ${round.roundId} not open (${round.status})');
      return;
    }
    // Check if already submitted this round.
    final existing = await _repository.getMatchingGameResult(round.roundId);
    final status = existing.valueOrNull?.participantStatus;
    if (status == 'submitted' || status == 'matched' || status == 'unmatched') {
      if (status == 'submitted') {
        _waitingForRoundResult = true;
        _startRoundResultPoll(round.roundId);
      } else if (status == 'matched' || status == 'unmatched') {
        await _applyGameResult(existing.valueOrNull!);
      }
      notifyListeners();
      return;
    }
    _log('Hourly matching game offer for ${round.roundId}');
    _triggerOffer();
  }

  Future<void> _completeHourlyRound(List<String> questionIds) async {
    final roundId = _activeRoundId ?? _roundInfo?.roundId;
    if (roundId == null || roundId.isEmpty) {
      _submitting = false;
      _emptyResults = true;
      _resultsVisible = true;
      notifyListeners();
      return;
    }
    final answers = <String, String>{
      for (final id in questionIds)
        if (_sessionAnswers.containsKey(id)) id: _sessionAnswers[id]!,
    };
    _log('Submitting hourly game answers for $roundId');
    final submitted = await _repository.submitMatchingGameAnswers(
      roundId: roundId,
      questionIds: questionIds,
      answers: answers,
    );
    _submitting = false;
    _elapsed = Duration.zero;
    _runningSince = null;
    _sessionAnswers.clear();
    if (submitted.isError) {
      _lastError = submitted.failureOrNull?.message;
      _emptyResults = true;
      _resultsVisible = true;
      notifyListeners();
      return;
    }
    _matchingEventCount += 1;
    _waitingForRoundResult = true;
    _resultsVisible = false;
    notifyListeners();
    _startRoundResultPoll(roundId);
  }

  void _startRoundResultPoll(String roundId) {
    _roundPoll?.cancel();
    _roundPoll = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_pollRoundResult(roundId));
    });
    unawaited(_pollRoundResult(roundId));
  }

  Future<void> _pollRoundResult(String roundId) async {
    final result = await _repository.getMatchingGameResult(roundId);
    if (result.isError) {
      return;
    }
    final info = result.valueOrNull;
    if (info == null) {
      return;
    }
    if (info.roundStatus == 'COMPLETED' ||
        info.isMatched ||
        info.isUnmatched) {
      _roundPoll?.cancel();
      _roundPoll = null;
      _waitingForRoundResult = false;
      await _applyGameResult(info);
    }
  }

  Future<void> _applyGameResult(MatchingGameResultInfo info) async {
    if (info.isMatched && info.partnerUid != null) {
      _testResults = [
        RelationshipMatchSuggestion(
          candidate: DiscoveryCandidate(
            uid: info.partnerUid!,
            displayName: info.partnerName ?? '',
            age: 0,
            photos: [
              if (info.partnerPhotoUrl != null &&
                  info.partnerPhotoUrl!.isNotEmpty)
                info.partnerPhotoUrl!,
            ],
            relationshipCompatibilityScore: info.compatibilityScore,
          ),
          score: info.compatibilityScore ?? 0,
          sharedQuestionCount: RelationshipQuestionConfig.questionsPerSession,
          alignedCount: info.compatibilityScore == 100
              ? RelationshipQuestionConfig.questionsPerSession
              : 0,
          matchId: info.matchId,
        ),
      ];
      _suggestions = _testResults;
      _emptyResults = false;
    } else {
      _testResults = const [];
      _emptyResults = true;
    }
    _resultsVisible = true;
    _sessionLocked = true;
    notifyListeners();
  }

  void _pauseTimer() {
    final started = _runningSince;
    if (started != null) {
      final delta = _clock().difference(started);
      if (!delta.isNegative) {
        _elapsed += delta;
      }
      _runningSince = null;
    }
    _timer?.cancel();
    _timer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  void _startHeartbeat() {
    if (!kDebugMode) {
      return;
    }
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      _log('Active time: ${activeSwipeTime.inSeconds} seconds');
      _log('Normal matches: $_normalMatchCount');
    });
  }

  void _onElapsed() {
    _timer?.cancel();
    _timer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _runningSince = null;
    _elapsed = Duration.zero;
    if (!_discoveryVisible || _sessionLocked || _appPaused) {
      _log(
        'Offer interval reached but skipped (visible=$_discoveryVisible locked=$_sessionLocked paused=$_appPaused)',
      );
      _log('Relationship trigger condition: FALSE');
      return;
    }
    _log('Offer interval reached (${_interval.inSeconds}s)');
    _log('Normal matches: $_normalMatchCount');
    _triggerOffer();
  }

  void _triggerOffer() {
    if (_sessionLocked) {
      _log('Relationship trigger condition: FALSE');
      return;
    }
    if (!_hourlyGlobalMatchingGame &&
        _normalMatchCount > 0 &&
        _enforceOfferGates) {
      _log('Offer skipped — active conversation');
      _log('Relationship trigger condition: FALSE');
      return;
    }
    if (_matchingPaused && _enforceOfferGates) {
      _log('Offer skipped — matching paused');
      _log('Relationship trigger condition: FALSE');
      return;
    }
    if (_cooldownActive && _enforceOfferGates) {
      _log('Offer skipped — cooldown');
      _log('Relationship trigger condition: FALSE');
      _armTimer();
      return;
    }
    _sessionLocked = true;
    _unavailable = false;
    _resultsVisible = false;
    _emptyResults = false;
    _lastError = null;
    final needsContinue =
        !_hourlyGlobalMatchingGame &&
        _matchingEventCount >=
            RelationshipQuestionConfig.eventsBeforeContinuePrompt &&
        _enforceOfferGates;
    if (needsContinue) {
      _continuePromptVisible = true;
      _offerVisible = false;
      _log('Opening continue-matching prompt (events=$_matchingEventCount)');
    } else {
      _continuePromptVisible = false;
      _offerVisible = true;
      _log('Relationship trigger condition: TRUE');
      _log('Opening test offer');
    }
    notifyListeners();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[RELATIONSHIP_DEBUG] $message');
    }
  }

  void _logFailure(String stage, Failure? failure) {
    if (failure == null) {
      _log('$stage failed');
      return;
    }
    _log('$stage ${failure.runtimeType}: ${failure.message}');
  }

  @visibleForTesting
  void debugElapse(Duration duration) {
    _answersReady = true;
    if (!_discoveryVisible) {
      return;
    }
    _pauseTimer();
    _elapsed += duration;
    _onElapsed();
  }

  @override
  void dispose() {
    pause();
    super.dispose();
  }
}
