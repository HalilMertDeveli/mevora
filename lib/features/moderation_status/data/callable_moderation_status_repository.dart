import 'package:cloud_functions/cloud_functions.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/domain/repositories/moderation_status_repository.dart';

class CallableModerationStatusRepository implements ModerationStatusRepository {
  const CallableModerationStatusRepository({required BackendCallable backend})
    : _backend = backend;

  static const String statusCallable = 'getMyModerationStatus';
  static const String appealCallable = 'submitModerationAppeal';

  final BackendCallable _backend;

  @override
  Future<ModerationStatus> fetchStatus() async {
    final payload = await _backend.invoke(statusCallable);
    return ModerationStatus.fromMap(payload);
  }

  @override
  Future<AppealSubmitOutcome> submitAppeal({
    required String actionId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (!AppealReasonRules.isValid(trimmed)) {
      return AppealSubmitOutcome.invalidReason;
    }
    try {
      final payload = await _backend.invoke(appealCallable, {
        'actionId': actionId,
        'reason': trimmed,
      });
      // Idempotent per decision: a second submit returns the first appeal.
      return payload['created'] == false
          ? AppealSubmitOutcome.alreadySubmitted
          : AppealSubmitOutcome.created;
    } on FirebaseFunctionsException catch (error) {
      return outcomeForError(error.code, error.message, error.details);
    } on Object {
      return AppealSubmitOutcome.failed;
    }
  }

  /// Maps the callable's HttpsError (code + domain code in the message) to
  /// an outcome the member can be told about.
  static AppealSubmitOutcome outcomeForError(
    String code,
    String? message,
    Object? details,
  ) {
    final domain = '${message ?? ''} ${details ?? ''}';
    switch (code) {
      case 'failed-precondition':
        if (domain.contains('appeal_window_closed')) {
          return AppealSubmitOutcome.windowClosed;
        }
        return AppealSubmitOutcome.notAllowed;
      case 'invalid-argument':
        return domain.contains('reason')
            ? AppealSubmitOutcome.invalidReason
            : AppealSubmitOutcome.notAllowed;
      case 'not-found':
      case 'permission-denied':
        return AppealSubmitOutcome.notAllowed;
      default:
        return AppealSubmitOutcome.failed;
    }
  }
}
