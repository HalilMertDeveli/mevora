import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/profile/data/datasources/profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

class FirebaseProfileQuestionAnswerDataSource
    implements ProfileQuestionAnswerDataSource {
  FirebaseProfileQuestionAnswerDataSource({
    required BackendCallable backend,
    FirebaseFirestore? firestore,
  }) : _backend = backend,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final BackendCallable _backend;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _answers(String uid) {
    return _firestore.collection(FirestorePaths.userQuestionAnswers(uid));
  }

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) {
    Query<Map<String, dynamic>> query = _answers(uid);
    if (visibleOnly) {
      query = query.where('isVisible', isEqualTo: true);
    }
    return query.snapshots().map((snap) {
      final items = snap.docs.map(_fromDoc).toList(growable: false);
      items.sort((a, b) {
        final aTime = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return items;
    });
  }

  @override
  Future<void> syncFromMatching() {
    return _backend.invoke('syncProfileQuestionAnswers');
  }

  @override
  Future<void> setVisibility({
    required String questionId,
    required bool isVisible,
  }) {
    return _backend.invoke('updateQuestionAnswerVisibility', {
      'questionId': questionId,
      'isVisible': isVisible,
    });
  }

  ProfileQuestionAnswer _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return ProfileQuestionAnswer(
      questionId: data['questionId'] as String? ?? doc.id,
      answerId: data['answerId'] as String? ?? '',
      isVisible: data['isVisible'] != false,
      createdAt: firestoreDate(data['createdAt']),
      updatedAt: firestoreDate(data['updatedAt']),
    );
  }
}
