import 'package:mevora/features/relationship/domain/entities/matching_game_round.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/domain/services/relationship_compatibility_key.dart';
import 'package:mevora/features/relationship/domain/services/relationship_match_rules.dart';
import 'package:mevora/features/relationship/domain/services/relationship_question_sets.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/relationship_data_source.dart';
import 'package:mevora/features/relationship/domain/config/relationship_question_config.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/matching/domain/match_engine.dart';

class MockRelationshipDataSource implements RelationshipDataSource {
  MockRelationshipDataSource({
    this.selfUid = 'self',
    DateTime Function()? clock,
    Map<String, String>? answers,
    List<MockRelationshipPeer>? peers,
    Map<String, DateTime?>? lastActiveAtByUid,
    DateTime? offerCooldownUntil,
    int matchingEventCount = 0,
  }) : _clock = clock ?? DateTime.now,
       _answers = Map<String, String>.from(answers ?? const {}),
       _peers = List<MockRelationshipPeer>.from(peers ?? seedPeers),
       _lastActiveAtByUid = lastActiveAtByUid ?? const {},
       _offerCooldownUntil = offerCooldownUntil,
       _matchingEventCount = matchingEventCount;

  final String selfUid;
  final DateTime Function() _clock;
  final Map<String, String> _answers;
  final List<MockRelationshipPeer> _peers;
  final Map<String, DateTime?> _lastActiveAtByUid;
  DateTime? _offerCooldownUntil;
  List<String> _completedQuestionIds = const [];
  var _matchingEventCount = 0;
  var _matchingPaused = false;

  static const seedPeers = [
    MockRelationshipPeer(
      candidate: DiscoveryCandidate(
        uid: 'rel-ada',
        displayName: 'Ada',
        age: 27,
        photos: [],
        city: 'Ankara',
        gender: 'woman',
        distanceKm: 1.4,
        isDemo: true,
      ),
      answers: {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
    ),
    MockRelationshipPeer(
      candidate: DiscoveryCandidate(
        uid: 'rel-leo',
        displayName: 'Leo',
        age: 29,
        photos: [],
        city: 'London',
        gender: 'man',
        distanceKm: 12,
        isDemo: true,
      ),
      answers: {'rq_001': 'a', 'rq_002': 'b', 'rq_003': 'c'},
    ),
  ];

  @override
  Future<RelationshipAnswerSnapshot> getAnswered() async {
    return _snapshot();
  }

  @override
  Future<RelationshipAnswerSnapshot> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    if (!RelationshipQuestionCatalog.isValidAnswer(
      questionId: questionId,
      answerId: answerId,
    )) {
      throw StateError('invalid-relationship-answer');
    }
    if (_answers.containsKey(questionId) && _answers[questionId] == answerId) {
      return _snapshot();
    }
    _answers[questionId] = answerId;
    return _snapshot();
  }

  @override
  Future<RelationshipAnswerSnapshot> dismissOffer({
    bool matchTaken = false,
    bool pauseMatching = false,
    bool continueMatching = false,
  }) async {
    if (pauseMatching) {
      _matchingPaused = true;
      return _snapshot();
    }
    if (continueMatching) {
      _matchingPaused = false;
      _offerCooldownUntil = _clock();
      return _snapshot();
    }
    _offerCooldownUntil = _clock().add(
      RelationshipQuestionConfig.cooldownFor(matchTaken: matchTaken),
    );
    return _snapshot();
  }

  @override
  Future<List<RelationshipMatchSuggestion>> completeTest({
    required List<String> questionIds,
  }) async {
    _completedQuestionIds = List<String>.from(questionIds);
    _matchingEventCount += 1;
    _matchingPaused = false;
    // Survey done without taking a match yet → short retry window.
    _offerCooldownUntil = _clock().add(
      RelationshipQuestionConfig.declinedCooldown,
    );
    return _exactSuggestions(questionIds);
  }

  @override
  Future<Map<String, String>> getSavedAnswers(String uid) async {
    if (uid != selfUid) {
      return const {};
    }
    return Map<String, String>.from(_answers);
  }

  @override
  Future<MatchingGameRoundInfo> getMatchingGameRound() async {
    final now = _clock();
    final next = now.add(const Duration(minutes: 30));
    return MatchingGameRoundInfo(
      roundId: 'mock_${now.year}${now.month}${now.day}${now.hour}',
      status: 'OPEN',
      timezone: 'Europe/Istanbul',
      serverNowMs: now.millisecondsSinceEpoch,
      nextRoundAtMs: next.millisecondsSinceEpoch,
      closesAtMs: next.millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> joinMatchingGameRound(String roundId) async {}

  @override
  Future<MatchingGameResultInfo> submitMatchingGameAnswers({
    required String roundId,
    required List<String> questionIds,
    required Map<String, String> answers,
  }) async {
    for (final entry in answers.entries) {
      _answers[entry.key] = entry.value;
    }
    _completedQuestionIds = List<String>.from(questionIds);
    _matchingEventCount += 1;
    final suggestions = _exactSuggestions(questionIds);
    if (suggestions.isEmpty) {
      return MatchingGameResultInfo(
        roundId: roundId,
        roundStatus: 'COMPLETED',
        participantStatus: 'unmatched',
      );
    }
    final hit = suggestions.first;
    return MatchingGameResultInfo(
      roundId: roundId,
      roundStatus: 'COMPLETED',
      participantStatus: 'matched',
      matchId: hit.matchId,
      compatibilityScore: hit.score,
      partnerUid: hit.candidate.uid,
      partnerName: hit.candidate.displayName,
      partnerPhotoUrl: hit.candidate.photos.isEmpty
          ? null
          : hit.candidate.photos.first,
    );
  }

  @override
  Future<MatchingGameResultInfo> getMatchingGameResult(String roundId) async {
    if (_completedQuestionIds.isEmpty) {
      return MatchingGameResultInfo(
        roundId: roundId,
        roundStatus: 'OPEN',
        participantStatus: null,
      );
    }
    final suggestions = _exactSuggestions(_completedQuestionIds);
    if (suggestions.isEmpty) {
      return MatchingGameResultInfo(
        roundId: roundId,
        roundStatus: 'COMPLETED',
        participantStatus: 'unmatched',
      );
    }
    final hit = suggestions.first;
    return MatchingGameResultInfo(
      roundId: roundId,
      roundStatus: 'COMPLETED',
      participantStatus: 'matched',
      matchId: hit.matchId,
      compatibilityScore: hit.score,
      partnerUid: hit.candidate.uid,
      partnerName: hit.candidate.displayName,
      partnerPhotoUrl: hit.candidate.photos.isEmpty
          ? null
          : hit.candidate.photos.first,
    );
  }

  @override
  Future<List<RelationshipMatchSuggestion>> getSuggestions() async {
    if (_completedQuestionIds.length == 3) {
      return _exactSuggestions(_completedQuestionIds);
    }
    final next = RelationshipQuestionSets.nextUnanswered(const {});
    if (next == null) {
      return const [];
    }
    final ids = next.map((question) => question.id).toList();
    if (!ids.every(_answers.containsKey)) {
      return const [];
    }
    return _exactSuggestions(ids);
  }

  List<RelationshipMatchSuggestion> _exactSuggestions(List<String> questionIds) {
    if (_answers.isEmpty || questionIds.length != 3) {
      return const [];
    }
    final now = _clock();
    final out = <RelationshipMatchSuggestion>[];
    for (final peer in _peers) {
      if (!RelationshipCompatibilityKey.isExactTriple(
        viewer: _answers,
        candidate: peer.answers,
        questionIds: questionIds,
      )) {
        continue;
      }
      if (!RelationshipMatchRules.isEligible(
        selfUid: selfUid,
        candidateUid: peer.candidate.uid,
        blocked: const {},
        passed: const {},
        candidateGender: peer.candidate.gender,
        lastActiveAt: _lastActiveAtByUid[peer.candidate.uid],
        now: now,
        alignedCount: 3,
      )) {
        continue;
      }
      final km = peer.candidate.distanceKm;
      if (km == null || km > RelationshipQuestionConfig.maxDistanceKm) {
        continue;
      }
      out.add(
        RelationshipMatchSuggestion(
          candidate: DiscoveryCandidate(
            uid: peer.candidate.uid,
            displayName: peer.candidate.displayName,
            age: peer.candidate.age,
            photos: peer.candidate.photos,
            city: peer.candidate.city,
            gender: peer.candidate.gender,
            isDemo: peer.candidate.isDemo,
            distanceKm: km,
            distanceLabel: '$km km',
            relationshipCompatibilityScore: 100,
            relationshipSharedViewCount: 3,
            relationshipAlignedCount: 3,
          ),
          score: 100,
          sharedQuestionCount: 3,
          alignedCount: 3,
          matchId: MatchEngine.matchId(selfUid, peer.candidate.uid),
        ),
      );
    }
    out.sort((a, b) {
      final left = a.candidate.distanceKm;
      final right = b.candidate.distanceKm;
      if (left == null && right == null) {
        return 0;
      }
      if (left == null) {
        return 1;
      }
      if (right == null) {
        return -1;
      }
      return left.compareTo(right);
    });
    return out.take(RelationshipQuestionConfig.resultLimit).toList();
  }

  RelationshipAnswerSnapshot _snapshot() {
    return RelationshipAnswerSnapshot(
      answeredIds: _answers.keys.toSet(),
      answerCount: _answers.length,
      offerCooldownUntil: _offerCooldownUntil,
      matchingEventCount: _matchingEventCount,
      matchingPaused: _matchingPaused,
    );
  }
}

class MockRelationshipPeer {
  const MockRelationshipPeer({required this.candidate, required this.answers});

  final DiscoveryCandidate candidate;
  final Map<String, String> answers;
}
