import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_server_payload.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_result.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_ui_status.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Resolved UI-facing state for Why You Matched — never invents reasons.
class WhyYouMatchedViewModel {
  const WhyYouMatchedViewModel({
    required this.status,
    required this.message,
    this.result = WhyYouMatchedResult.empty,
    this.canRetry = false,
  });

  final WhyYouMatchedUiStatus status;
  final String message;
  final WhyYouMatchedResult result;
  final bool canRetry;

  List<WhyYouMatchedReason> get reasons => result.reasons;
}

/// Maps engine / network outcomes to safe UI states.
///
/// Rules:
/// - Empty / thin / no-overlap → [WhyYouMatchedUiStatus.empty] + fallback copy
/// - Network / timeout → error + retry
/// - Invalid payload → error (or empty) — **no synthetic reasons**
abstract final class WhyYouMatchedEdgeCaseHandler {
  /// Safe fallback when there is not enough real overlap to explain a match.
  static String fallbackMessage(AppLocalizations l10n) =>
      l10n.wymInsufficientData;

  static WhyYouMatchedViewModel fromResult(
    AppLocalizations l10n,
    WhyYouMatchedResult result,
  ) {
    if (!result.available || result.reasons.isEmpty) {
      return WhyYouMatchedViewModel(
        status: WhyYouMatchedUiStatus.empty,
        message: fallbackMessage(l10n),
        result: WhyYouMatchedResult.empty,
      );
    }
    return WhyYouMatchedViewModel(
      status: WhyYouMatchedUiStatus.ready,
      message: '',
      result: result,
    );
  }

  static WhyYouMatchedViewModel fromPayload(
    AppLocalizations l10n,
    WhyYouMatchedServerPayload payload,
  ) {
    return fromResult(l10n, payload.toResult());
  }

  static WhyYouMatchedViewModel fromFailure(
    AppLocalizations l10n,
    Failure failure,
  ) {
    if (failure is NetworkFailure) {
      final lower = failure.message.toLowerCase();
      final isTimeout = lower.contains('timeout') ||
          lower.contains('deadline') ||
          lower.contains('timed out');
      return WhyYouMatchedViewModel(
        status: WhyYouMatchedUiStatus.error,
        message: isTimeout
            ? l10n.wymTimeoutErrorMessage
            : l10n.wymNetworkErrorMessage,
        canRetry: true,
      );
    }
    if (failure is ValidationFailure) {
      return WhyYouMatchedViewModel(
        status: WhyYouMatchedUiStatus.error,
        message: l10n.wymInvalidDataMessage,
        canRetry: true,
      );
    }
    return WhyYouMatchedViewModel(
      status: WhyYouMatchedUiStatus.error,
      message: l10n.wymErrorMessage,
      canRetry: true,
    );
  }

  static WhyYouMatchedViewModel fromFetchResult(
    AppLocalizations l10n,
    Result<WhyYouMatchedServerPayload> result,
  ) {
    return switch (result) {
      Success(:final value) => fromPayload(l10n, value),
      Err(:final failure) => fromFailure(l10n, failure),
    };
  }

  /// Loading placeholder — no reasons yet.
  static WhyYouMatchedViewModel loading(AppLocalizations l10n) {
    return WhyYouMatchedViewModel(
      status: WhyYouMatchedUiStatus.loading,
      message: l10n.wymLoadingMessage,
    );
  }
}
