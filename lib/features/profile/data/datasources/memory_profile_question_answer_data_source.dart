import 'dart:async';

import 'package:mevora/features/profile/data/datasources/profile_question_answer_data_source.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';

class MemoryProfileQuestionAnswerDataSource
    implements ProfileQuestionAnswerDataSource {
  final Map<String, Map<String, ProfileQuestionAnswer>> _store = {};
  final Map<String, StreamController<List<ProfileQuestionAnswer>>> _controllers =
      {};

  PartnerQuestionAnswersSnapshot partnerSnapshot =
      PartnerQuestionAnswersSnapshot.empty;

  @override
  Stream<List<ProfileQuestionAnswer>> watchAnswers(
    String uid, {
    bool visibleOnly = false,
  }) {
    final controller = _controllers.putIfAbsent(
      uid,
      () => StreamController<List<ProfileQuestionAnswer>>.broadcast(),
    );
    scheduleMicrotask(() => controller.add(_list(uid, visibleOnly: visibleOnly)));
    return controller.stream;
  }

  @override
  Future<PartnerQuestionAnswersSnapshot> fetchPartnerAnswers(
    String partnerUid,
  ) async {
    return partnerSnapshot;
  }

  @override
  Future<void> syncFromMatching() async {}

  @override
  Future<void> setVisibility({
    required String questionId,
    required bool isVisible,
  }) async {
    for (final uid in _store.keys) {
      final current = _store[uid]?[questionId];
      if (current == null) {
        continue;
      }
      _store[uid]![questionId] = ProfileQuestionAnswer(
        questionId: current.questionId,
        answerId: current.answerId,
        isVisible: isVisible,
        answerLocked: current.answerLocked,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      _emit(uid);
    }
  }

  void upsert(String uid, ProfileQuestionAnswer answer) {
    _store.putIfAbsent(uid, () => {})[answer.questionId] = answer;
    _emit(uid);
  }

  List<ProfileQuestionAnswer> _list(String uid, {required bool visibleOnly}) {
    final items = (_store[uid]?.values ?? const Iterable.empty())
        .where((item) => !visibleOnly || item.isVisible)
        .toList(growable: false);
    items.sort((a, b) {
      final aTime = a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return items;
  }

  void _emit(String uid) {
    final controller = _controllers[uid];
    if (controller == null || controller.isClosed) {
      return;
    }
    controller.add(_list(uid, visibleOnly: false));
  }
}
