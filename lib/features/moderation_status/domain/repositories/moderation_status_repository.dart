import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';

/// The member's own moderation record and the appeal path. Backed by the
/// App Check-enforced consumer callables, which work for a suspended member.
abstract class ModerationStatusRepository {
  Future<ModerationStatus> fetchStatus();

  /// Files an appeal against [actionId]. Never throws: every outcome,
  /// including transport failure, is an [AppealSubmitOutcome].
  Future<AppealSubmitOutcome> submitAppeal({
    required String actionId,
    required String reason,
  });
}
