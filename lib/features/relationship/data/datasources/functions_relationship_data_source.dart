import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/data/datasources/firestore_relationship_answers_reader.dart';
import 'package:mevora/features/relationship/data/datasources/relationship_data_source.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';

class FunctionsRelationshipDataSource implements RelationshipDataSource {
  FunctionsRelationshipDataSource({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<RelationshipAnswerSnapshot> getAnswered() async {
    final data = await _invoke('getRelationshipAnswered');
    return _parseSnapshot(data);
  }

  @override
  Future<RelationshipAnswerSnapshot> saveAnswer({
    required String questionId,
    required String answerId,
  }) async {
    _debug('Saving answer $questionId=$answerId');
    final data = await _invoke('saveRelationshipAnswer', {
      'questionId': questionId,
      'answerId': answerId,
    });
    final snapshot = _parseSnapshot(data);
    _debug('Answers saved successfully (${snapshot.answerCount})');
    return snapshot;
  }

  @override
  Future<RelationshipAnswerSnapshot> dismissOffer({
    bool matchTaken = false,
    bool pauseMatching = false,
    bool continueMatching = false,
  }) async {
    _debug(
      'dismissOffer matchTaken=$matchTaken pause=$pauseMatching continue=$continueMatching',
    );
    final reason = pauseMatching
        ? 'pause_matching'
        : continueMatching
        ? 'continue_matching'
        : (matchTaken ? 'matched' : 'declined');
    return _parseSnapshot(
      await _invoke('dismissRelationshipTestOffer', {'reason': reason}),
    );
  }

  @override
  Future<List<RelationshipMatchSuggestion>> completeTest({
    required List<String> questionIds,
  }) async {
    _debug('Relationship pool query started for ${questionIds.join(',')}');
    final data = await _invoke('completeRelationshipTest', {
      'questionIds': questionIds,
    });
    final items = _parseItems(data);
    _debug('Candidates found: ${items.length}');
    _debug('Relationship matches created: ${data['matched'] == true ? 1 : 0}');
    return items;
  }

  @override
  Future<List<RelationshipMatchSuggestion>> getSuggestions() async {
    return _parseItems(await _invoke('getRelationshipMatches'));
  }

  @override
  Future<Map<String, String>> getSavedAnswers(String uid) {
    return FirestoreRelationshipAnswersReader().loadAnswers(uid);
  }

  Future<Map<String, dynamic>> _invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    try {
      return await _backend.invoke(name, data);
    } on FirebaseFunctionsException catch (error) {
      _debug('FirebaseFunctionsException ${error.code}: ${error.message}');
      rethrow;
    } on FirebaseException catch (error) {
      _debug('FirebaseException ${error.code}: ${error.message}');
      rethrow;
    } on Object catch (error) {
      _debug('$name failed: $error');
      rethrow;
    }
  }

  void _debug(String message) {
    if (kDebugMode) {
      debugPrint('[RELATIONSHIP_DEBUG] $message');
    }
  }

  List<RelationshipMatchSuggestion> _parseItems(Map<String, dynamic> data) {
    final raw = data['items'];
    if (raw is! List) {
      return const [];
    }
    final items = <RelationshipMatchSuggestion>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final candidate = _parseCandidate(map);
      if (candidate == null) {
        continue;
      }
      items.add(
        RelationshipMatchSuggestion(
          candidate: candidate,
          score: firestoreInt(map['score'], 0),
          sharedQuestionCount: firestoreInt(map['sharedQuestionCount'], 0),
          alignedCount: firestoreInt(map['alignedCount'], 0),
          topTopics: _topics(map['topTopics']),
          matchId: map['matchId'] as String?,
        ),
      );
    }
    return items;
  }

  RelationshipAnswerSnapshot _parseSnapshot(Map<String, dynamic> data) {
    final cooldownMs = firestoreInt(data['offerCooldownUntil'], 0);
    return RelationshipAnswerSnapshot(
      answeredIds: firestoreStringList(data['answeredIds']).toSet(),
      answerCount: firestoreInt(data['answerCount'], 0),
      offerCooldownUntil: cooldownMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(cooldownMs)
          : null,
      matchingEventCount: firestoreInt(data['matchingEventCount'], 0),
      matchingPaused: data['matchingPaused'] == true,
    );
  }

  List<RelationshipTopic> _topics(Object? raw) {
    final names = firestoreStringList(raw);
    final out = <RelationshipTopic>[];
    for (final name in names) {
      for (final topic in RelationshipTopic.values) {
        if (topic.name == name) {
          out.add(topic);
          break;
        }
      }
    }
    return out;
  }

  DiscoveryCandidate? _parseCandidate(Map<String, dynamic> raw) {
    final uid = raw['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    final profile = raw['profile'] is Map
        ? Map<String, dynamic>.from(raw['profile'] as Map)
        : raw;
    profile.remove('latitude');
    profile.remove('longitude');
    profile.remove('geohash');
    final photosRaw = profile['photos'];
    final photos = <String>[];
    if (photosRaw is List) {
      for (final item in photosRaw) {
        if (item is String) {
          photos.add(item);
        }
      }
    }
    final score = firestoreInt(raw['score'], 0);
    final shared = firestoreInt(raw['sharedQuestionCount'], 0);
    final aligned = firestoreInt(raw['alignedCount'], 0);
    final distanceKm = firestoreDouble(raw['distanceKm']);
    return DiscoveryCandidate(
      uid: uid,
      displayName: (profile['displayName'] as String?) ?? '',
      age: firestoreInt(profile['age'], 0),
      photos: photos,
      city: profile['city'] as String?,
      bio: profile['bio'] as String?,
      gender: profile['gender'] as String?,
      interests: firestoreStringList(profile['interests']),
      compatibilityScore: firestoreInt(raw['compatibilityScore'], 0),
      distanceKm: distanceKm,
      distanceLabel: raw['distanceLabel'] as String?,
      relationshipCompatibilityScore: score == 0 ? null : score,
      relationshipSharedViewCount: shared == 0 ? null : shared,
      relationshipAlignedCount: aligned == 0 ? null : aligned,
      relationshipSummaryTopics: firestoreStringList(raw['topTopics']),
    );
  }
}
