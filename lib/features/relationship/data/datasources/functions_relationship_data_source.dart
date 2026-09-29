import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/relationship/data/datasources/firestore_relationship_answers_reader.dart';
import 'package:mevora/features/relationship/data/datasources/relationship_data_source.dart';
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

  RelationshipAnswerSnapshot _parseSnapshot(Map<String, dynamic> data) {
    return RelationshipAnswerSnapshot(
      answeredIds: firestoreStringList(data['answeredIds']).toSet(),
      answerCount: firestoreInt(data['answerCount'], 0),
    );
  }
}
