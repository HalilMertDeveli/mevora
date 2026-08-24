import 'package:mevora/features/matching/domain/match_engine.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';

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
