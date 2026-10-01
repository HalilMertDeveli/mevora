import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';

/// Match-gated access for profile question answers.
abstract final class ProfileQuestionAnswerAccess {
  static String matchIdFor(String viewerUid, String profileUid) {
    return MatchEngine.matchId(viewerUid, profileUid);
  }

  static bool canView({
    required String viewerUid,
    required String profileUid,
    Match? match,
  }) {
    if (viewerUid.isEmpty || profileUid.isEmpty) {
      return false;
    }
    if (viewerUid == profileUid) {
      return true;
    }
    return match != null &&
        match.isActive &&
        match.isParticipant(viewerUid) &&
        match.isParticipant(profileUid);
  }

  /// Lookups already made this session, by viewer and profile.
  static final Map<String, bool> _hasVisibleAnswers = {};

  /// Whether [profileUid] has at least one answer [viewerUid] may read.
  ///
  /// Used to decide whether an entry point to those answers is worth
  /// offering. Looked up once per pair and session; an unreadable or slow
  /// answer list counts as "nothing to show" without being remembered.
  static Future<bool> hasVisibleAnswers({
    required ProfileQuestionAnswerRepository answers,
    required String viewerUid,
    required String profileUid,
  }) async {
    if (viewerUid.isEmpty || profileUid.isEmpty) {
      return false;
    }
    final key = '$viewerUid:$profileUid';
    final known = _hasVisibleAnswers[key];
    if (known != null) {
      return known;
    }
    try {
      final visible = await answers
          .watchAnswers(profileUid, visibleOnly: viewerUid != profileUid)
          .first
          .timeout(const Duration(seconds: 10));
      return _hasVisibleAnswers[key] = visible.any((item) => item.isVisible);
    } on Object {
      return false;
    }
  }

  /// Forgets every lookup. For tests.
  static void forgetVisibleAnswers() => _hasVisibleAnswers.clear();

  static Stream<bool> watchCanView({
    required MatchRepository matches,
    required String viewerUid,
    required String profileUid,
  }) {
    if (viewerUid.isEmpty || profileUid.isEmpty) {
      return Stream.value(false);
    }
    if (viewerUid == profileUid) {
      return Stream.value(true);
    }
    final matchId = matchIdFor(viewerUid, profileUid);
    return matches.watchMatch(matchId).map(
      (match) => canView(
        viewerUid: viewerUid,
        profileUid: profileUid,
        match: match,
      ),
    );
  }
}
