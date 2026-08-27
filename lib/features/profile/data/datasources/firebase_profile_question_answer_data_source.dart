import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/constants/firestore_paths.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/profile/data/datasources/profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

/// Maps `getPartnerQuestionAnswers` CF payload → UI snapshot.
/// Free clients never receive answer fields even if a buggy payload includes them.
PartnerQuestionAnswersSnapshot parsePartnerQuestionAnswersPayload(
  Map<String, dynamic> raw,
) {
  final isPremium = raw['isPremium'] == true;
  final premiumRequired = raw['premiumRequired'] == true;
  final matchRequired = raw['matchRequired'] == true;
  final locked = raw['locked'] == true || premiumRequired || matchRequired;

  final answersRaw = raw['answers'];
  final questionsRaw = raw['questions'];

  if (isPremium && !locked && answersRaw is List) {
    final items = <ProfileQuestionAnswer>[];
    for (final row in answersRaw) {
      if (row is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(row);
      final questionId = map['questionId'] as String? ?? '';
      final answerId = map['answerId'] as String? ?? '';
      if (questionId.isEmpty || answerId.isEmpty) {
        continue;
      }
      items.add(
        ProfileQuestionAnswer(
          questionId: questionId,
          answerId: answerId,
          isVisible: map['isVisible'] != false,
        ),
      );
    }
    return PartnerQuestionAnswersSnapshot(
      locked: false,
      matchRequired: false,
      premiumRequired: false,
      isPremium: true,
      items: items,
    );
  }

  // Free / locked: question ids only — never trust answer fields from payload.
  final items = <ProfileQuestionAnswer>[];
  if (questionsRaw is List) {
    for (final row in questionsRaw) {
      if (row is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(row);
      final questionId = map['questionId'] as String? ?? '';
      if (questionId.isEmpty) {
        continue;
      }
      items.add(
        ProfileQuestionAnswer(
          questionId: questionId,
          answerId: '',
          isVisible: true,
          answerLocked: true,
        ),
      );
    }
  }

  return PartnerQuestionAnswersSnapshot(
    locked: locked || !isPremium,
    matchRequired: matchRequired,
    premiumRequired: premiumRequired || (!matchRequired && !isPremium),
    isPremium: isPremium,
    items: items,
  );
}

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
    // Owner path only. Peer UIs must use [fetchPartnerAnswers] (CF) — never
    // Firestore-watch another user's questionAnswers (rules deny peer reads).
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
  Future<PartnerQuestionAnswersSnapshot> fetchPartnerAnswers(
    String partnerUid,
  ) async {
    final raw = await _backend.invoke('getPartnerQuestionAnswers', {
      'partnerUid': partnerUid,
    });
    return parsePartnerQuestionAnswersPayload(raw);
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
