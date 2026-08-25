import 'package:mevora/core/constants/app_strings.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/features/calls/presentation/call_strings.dart';
import 'package:mevora/features/chat/presentation/chat_strings.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Maps error kinds to localized copy. Widgets pass [AppLocalizations], not raw codes.
abstract final class L10nErrors {
  static String auth(AppLocalizations l10n, AuthErrorKind kind) {
    return switch (kind) {
      AuthErrorKind.cancelled => l10n.authCancelled,
      AuthErrorKind.invalidPhone => l10n.authInvalidPhone,
      AuthErrorKind.smsFailed => l10n.authSmsFailed,
      AuthErrorKind.appVerification => l10n.authAppVerification,
      AuthErrorKind.invalidOtp => l10n.authInvalidOtp,
      AuthErrorKind.expiredOtp => l10n.authExpiredOtp,
      AuthErrorKind.sessionExpired => l10n.authSessionExpired,
      AuthErrorKind.tooManyAttempts => l10n.authTooManyAttempts,
      AuthErrorKind.smsQuota => l10n.authSmsQuota,
      AuthErrorKind.firebaseUnavailable => l10n.authFirebaseUnavailable,
      AuthErrorKind.network => l10n.authNetwork,
      AuthErrorKind.disabled => l10n.authDisabled,
      AuthErrorKind.banned => l10n.authBanned,
      AuthErrorKind.oauth => l10n.authGoogleFailed,
      AuthErrorKind.unknown => l10n.authUnknown,
      AuthErrorKind.accountExists => l10n.authAccountExists,
      AuthErrorKind.linkingBlocked => l10n.authLinkingBlocked,
      AuthErrorKind.notConfigured => l10n.authNotConfigured,
      AuthErrorKind.billingNotEnabled => l10n.authBillingNotEnabled,
      AuthErrorKind.invalidEmail => l10n.authInvalidEmail,
      AuthErrorKind.weakPassword => l10n.authWeakPassword,
      AuthErrorKind.userNotFound => l10n.authUserNotFound,
      AuthErrorKind.wrongPassword => l10n.authWrongPassword,
      AuthErrorKind.emailInUse => l10n.authEmailInUse,
    };
  }

  static String location(AppLocalizations l10n, LocationErrorKind kind) {
    return switch (kind) {
      LocationErrorKind.gpsDisabled => l10n.gpsDisabledMessage,
      LocationErrorKind.permissionDenied => l10n.locationDeniedMessage,
      LocationErrorKind.permissionPermanentlyDenied =>
        l10n.locationSettingsMessage,
      LocationErrorKind.timeout => l10n.locationTimeoutMessage,
      LocationErrorKind.network => l10n.locationNetworkMessage,
      LocationErrorKind.invalidCoordinates ||
      LocationErrorKind.unavailable ||
      LocationErrorKind.error => l10n.locationUnavailableTitle,
    };
  }

  static String purchase(AppLocalizations l10n, PurchaseErrorKind kind) {
    return switch (kind) {
      PurchaseErrorKind.cancelled => l10n.boostPurchaseCancelled,
      PurchaseErrorKind.failed => l10n.boostPurchaseFailed,
      PurchaseErrorKind.unavailable => l10n.boostStoreUnavailable,
      PurchaseErrorKind.storeDown => l10n.boostStoreDown,
      PurchaseErrorKind.network => l10n.boostNetworkError,
      PurchaseErrorKind.verificationFailed => l10n.boostVerificationFailed,
      PurchaseErrorKind.alreadyProcessed => l10n.boostAlreadyProcessed,
      PurchaseErrorKind.alreadyActive => l10n.boostAlreadyActive,
      PurchaseErrorKind.insufficientBalance => l10n.boostInsufficientBalance,
    };
  }

  static String failure(AppLocalizations l10n, Failure failure) {
    return switch (failure) {
      AuthFailure(:final kind) => auth(l10n, kind),
      LocationFailure(:final kind) => location(l10n, kind),
      PurchaseFailure(:final kind) => purchase(l10n, kind),
      AuthzFailure() => l10n.notAllowed,
      ValidationFailure(:final message) => message,
      PermissionFailure() => l10n.notAllowed,
      NotFoundFailure() => l10n.notFound,
      NetworkFailure() => l10n.networkError,
      CacheFailure() => l10n.somethingWentWrong,
      UnexpectedFailure() => l10n.somethingWentWrong,
    };
  }

  /// Maps data-layer fallback strings (Turkish/English constants) to the active locale.
  static String message(AppLocalizations l10n, String? raw) {
    if (raw == null || raw.isEmpty) {
      return l10n.somethingWentWrong;
    }
    if (raw == ChatStrings.needSignIn) return l10n.needSignIn;
    if (raw == ChatStrings.cannotMessageSelf) return l10n.cannotMessageSelf;
    if (raw == ChatStrings.blockedInteraction) return l10n.blockedInteraction;
    if (raw == ChatStrings.matchInactive || raw == ChatStrings.unmatchedBanner) {
      return l10n.matchInactive;
    }
    if (raw == ChatStrings.notMatched) return l10n.notMatched;
    if (raw == ChatStrings.alreadySwiped) return l10n.alreadySwiped;
    if (raw == ChatStrings.notAllowed) return l10n.notAllowed;
    if (raw == ChatStrings.notFound) return l10n.chatNotFound;
    if (raw == ChatStrings.network) return l10n.networkError;
    if (raw == ChatStrings.generic) return l10n.chatGeneric;
    if (raw == ChatStrings.encryptionNotReady) {
      return l10n.chatEncryptionNotReady;
    }
    if (raw == CallStrings.userBusy) return l10n.userBusy;
    if (raw == CallStrings.notConfigured) return l10n.callNotConfigured;
    if (raw == CallStrings.cameraDenied) return l10n.cameraDenied;
    if (raw == CallStrings.micDenied) return l10n.micDenied;
    if (raw == CallStrings.unstable) return l10n.connectionUnstable;
    if (raw == CallStrings.failed) return l10n.callFailed;
    if (raw == CallStrings.ended) return l10n.callEnded;
    if (raw == AppStrings.networkError) return l10n.networkError;
    if (raw == AppStrings.locationTimeoutMessage) return l10n.locationTimeoutMessage;
    if (raw == AppStrings.locationNetworkMessage) return l10n.locationNetworkMessage;
    if (raw == AppStrings.boostStoreUnavailable) return l10n.boostStoreUnavailable;
    return raw;
  }
}
