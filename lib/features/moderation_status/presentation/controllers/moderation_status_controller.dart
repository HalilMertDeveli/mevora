import 'package:flutter/foundation.dart';
import 'package:mevora/features/moderation_status/domain/models/moderation_status.dart';
import 'package:mevora/features/moderation_status/domain/repositories/moderation_status_repository.dart';

/// Loads the member's moderation record and files appeals. Page-scoped: the
/// page creates it, refreshes it on open, pull and resume, and disposes it.
class ModerationStatusController extends ChangeNotifier {
  ModerationStatusController({required ModerationStatusRepository repository})
    : _repository = repository;

  final ModerationStatusRepository _repository;

  ModerationStatus? status;
  bool isLoading = false;

  /// The last load failed. A previously loaded [status] stays on screen.
  bool loadFailed = false;

  /// The decision an appeal is being submitted for, if any.
  String? submittingActionId;

  bool _disposed = false;
  int _generation = 0;

  Future<void> refresh() async {
    final generation = ++_generation;
    isLoading = true;
    _notify();
    try {
      final next = await _repository.fetchStatus();
      if (generation != _generation) {
        return;
      }
      status = next;
      loadFailed = false;
    } on Object {
      if (generation != _generation) {
        return;
      }
      loadFailed = true;
    }
    isLoading = false;
    _notify();
  }

  /// Submits an appeal and, when one exists afterwards, reloads so the
  /// decision shows its appeal state.
  Future<AppealSubmitOutcome> submitAppeal({
    required String actionId,
    required String reason,
  }) async {
    if (submittingActionId != null) {
      return AppealSubmitOutcome.failed;
    }
    if (!AppealReasonRules.isValid(reason)) {
      return AppealSubmitOutcome.invalidReason;
    }
    submittingActionId = actionId;
    _notify();
    final outcome = await _repository.submitAppeal(
      actionId: actionId,
      reason: reason.trim(),
    );
    submittingActionId = null;
    _notify();
    if (outcome == AppealSubmitOutcome.created ||
        outcome == AppealSubmitOutcome.alreadySubmitted ||
        outcome == AppealSubmitOutcome.windowClosed ||
        outcome == AppealSubmitOutcome.notAllowed) {
      await refresh();
    }
    return outcome;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
