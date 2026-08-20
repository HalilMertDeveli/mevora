import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';

/// Maps domain failures to user-visible copy. Raw SDK / Firebase messages
/// must never reach the UI.
abstract final class FailureMessages {
  static String of(Failure failure) {
    return switch (failure) {
      AuthFailure(:final message) => message,
      AuthzFailure(:final message) => message,
      ValidationFailure(:final message) => message,
      PermissionFailure(:final message) => message,
      LocationFailure(:final kind) => switch (kind) {
        LocationErrorKind.gpsDisabled => AppStrings.gpsDisabledMessage,
        LocationErrorKind.permissionDenied => AppStrings.locationDeniedMessage,
        LocationErrorKind.permissionPermanentlyDenied =>
          AppStrings.locationSettingsMessage,
        LocationErrorKind.timeout => AppStrings.locationTimeoutMessage,
        LocationErrorKind.network => AppStrings.locationNetworkMessage,
        LocationErrorKind.invalidCoordinates ||
        LocationErrorKind.unavailable ||
        LocationErrorKind.error => AppStrings.locationUnavailableTitle,
      },
      PurchaseFailure(:final kind) => switch (kind) {
        PurchaseErrorKind.cancelled => AppStrings.boostPurchaseCancelled,
        PurchaseErrorKind.failed => AppStrings.boostPurchaseFailed,
        PurchaseErrorKind.unavailable => AppStrings.boostStoreUnavailable,
        PurchaseErrorKind.storeDown => AppStrings.boostStoreDown,
        PurchaseErrorKind.network => AppStrings.boostNetworkError,
        PurchaseErrorKind.verificationFailed =>
          AppStrings.boostVerificationFailed,
        PurchaseErrorKind.alreadyProcessed => AppStrings.boostAlreadyProcessed,
        PurchaseErrorKind.alreadyActive => AppStrings.boostAlreadyActive,
        PurchaseErrorKind.insufficientBalance =>
          AppStrings.boostInsufficientBalance,
      },
      NotFoundFailure() => AppStrings.notFound,
      NetworkFailure() => AppStrings.networkError,
      CacheFailure() => AppStrings.somethingWentWrong,
      UnexpectedFailure() => AppStrings.somethingWentWrong,
    };
  }
}
