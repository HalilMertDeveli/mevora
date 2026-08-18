// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Mevora';

  @override
  String get tagline => 'Find compatible people, not just nearby people.';

  @override
  String get connectTagline => 'Connect with people who match you.';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get tryAgain => 'Try again';

  @override
  String get unexpectedError => 'The app hit an unexpected error.';

  @override
  String get firebaseUnavailableMessage =>
      'Mevora could not start. Check your connection and try again.';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get loading => 'Loading';

  @override
  String get save => 'Save';

  @override
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get continueAction => 'Continue';

  @override
  String get done => 'Done';

  @override
  String get you => 'You';

  @override
  String get emptyTitle => 'Nothing here yet';

  @override
  String get emptyMessage =>
      'When there is something to show, it will appear here.';

  @override
  String get networkError => 'Check your connection and try again.';

  @override
  String get notFound => 'We could not find that.';

  @override
  String get comingSoon => 'This part of Mevora is not ready yet.';

  @override
  String get notAllowed => 'You do not have permission to do that.';

  @override
  String get needSignIn => 'Sign in to continue.';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get loginSubtitle => 'Sign in to keep discovering compatible people.';

  @override
  String get createAccountTitle => 'Create your account';

  @override
  String get registerSubtitle =>
      'Join Mevora to meet people you are likely to connect with.';

  @override
  String get email => 'Email';

  @override
  String get emailHint => 'you@email.com';

  @override
  String get emailRequired => 'Email is required';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String passwordMinLength(int min) {
    return 'Password must be at least $min characters';
  }

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String fieldRequired(String field) {
    return '$field is required';
  }

  @override
  String fieldMinLength(String field, int min) {
    return '$field must be at least $min characters';
  }

  @override
  String get phoneRequired => 'Phone is required';

  @override
  String get codeRequired => 'Code is required';

  @override
  String get otpInvalidFormat => 'Enter the 6-digit code';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get resetPasswordTitle => 'Reset password';

  @override
  String get resetPasswordMessage =>
      'Enter your email and we will send a reset link.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String get resetEmailSentTitle => 'Check your email';

  @override
  String get resetEmailSentMessage =>
      'If an account exists for that email, a reset link is on the way.';

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get orContinueWith => 'or continue with';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithSpotify => 'Continue with Spotify';

  @override
  String get continueWithPhone => 'Continue with phone';

  @override
  String get legalPrefix => 'By continuing you agree to our';

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get legalConjunction => 'and';

  @override
  String get signInWithEmail => 'Sign in with email';

  @override
  String get newToMevora => 'New to Mevora?';

  @override
  String get alreadyHaveAccount => 'Already have an account?';

  @override
  String get createAnAccount => 'Create an account';

  @override
  String get preparingMevora => 'Preparing Mevora';

  @override
  String get logOut => 'Log out';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get appleSignInUnavailable =>
      'Apple Sign-In is available on iPhone and iPad.';

  @override
  String get phoneTitle => 'Enter your phone number';

  @override
  String get phoneSubtitle => 'We will text you a verification code.';

  @override
  String get phoneHint => '555 000 0000';

  @override
  String get sendCode => 'Send SMS code';

  @override
  String get countrySearchHint => 'Search country';

  @override
  String get otpTitle => 'Verify your phone';

  @override
  String get verify => 'Verify';

  @override
  String get resend => 'Resend code';

  @override
  String get sendingSms => 'Sending SMS...';

  @override
  String get verifying => 'Verifying...';

  @override
  String get phoneVerifiedSuccess => 'Your phone number is verified.';

  @override
  String get countryCode => 'Country code';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get otpFieldLabel => '6-digit verification code';

  @override
  String otpSentTo(String phone) {
    return 'Enter the 6-digit code sent to $phone.';
  }

  @override
  String resendCountdown(int seconds) {
    return 'You can request a new code in $seconds seconds.';
  }

  @override
  String get enterOtp => 'Enter the verification code.';

  @override
  String get authCancelled => 'Sign-in was cancelled.';

  @override
  String get authInvalidPhone => 'Enter a valid phone number.';

  @override
  String get authSmsFailed => 'We could not send the SMS. Please try again.';

  @override
  String get authInvalidOtp => 'Invalid verification code.';

  @override
  String get authExpiredOtp => 'That code has expired. Request a new one.';

  @override
  String get authSessionExpired =>
      'Your session expired. Please enter your number again.';

  @override
  String get authTooManyAttempts =>
      'Too many attempts. Please wait and try again.';

  @override
  String get authSmsQuota =>
      'SMS sending limit reached. Please try again later.';

  @override
  String get authFirebaseUnavailable =>
      'Verification is temporarily unavailable. Please try again later.';

  @override
  String get authNetwork => 'Check your internet connection.';

  @override
  String get authDisabled => 'This account has been disabled.';

  @override
  String get authBanned => 'This account has been suspended.';

  @override
  String get authOauth => 'We could not complete sign-in. Please try again.';

  @override
  String get authUnknown => 'Something unexpected happened. Please try again.';

  @override
  String get authAccountExists =>
      'That sign-in method is already tied to another Mevora account. Accounts are never merged automatically.';

  @override
  String get authLinkingBlocked =>
      'Accounts are linked only when you confirm. A matching email is not enough.';

  @override
  String get authNotConfigured => 'This sign-in method is not set up yet.';

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authWeakPassword =>
      'Choose a stronger password with at least 8 characters.';

  @override
  String get authUserNotFound => 'No account found for that email.';

  @override
  String get authWrongPassword =>
      'That email and password combination does not match.';

  @override
  String get authSpotifyCallbackExpired =>
      'The Spotify session timed out. Please try again.';

  @override
  String get authEmailInUse => 'An account already exists for that email.';

  @override
  String get authGeneric =>
      'We could not complete that request. Please try again.';

  @override
  String get authGoogleFailed => 'Google Sign-In could not be completed.';

  @override
  String get authAppleFailed => 'Apple Sign-In could not be completed.';

  @override
  String get onboardingTitle => 'A few more steps';

  @override
  String get onboardingMessage =>
      'Complete your profile so Mevora can introduce compatible people.';

  @override
  String get onboardingFirstName => 'First name';

  @override
  String get onboardingBirthDate => 'Birthday';

  @override
  String get onboardingGender => 'I am';

  @override
  String get onboardingInterestedIn => 'Interested in';

  @override
  String get onboardingCity => 'City';

  @override
  String get onboardingPhotos => 'Profile photos';

  @override
  String get onboardingBio => 'About you';

  @override
  String get onboardingInterests => 'Interests';

  @override
  String get onboardingRelationshipGoal => 'Looking for';

  @override
  String get onboardingAddPhoto => 'Add a photo';

  @override
  String get onboardingMustBeAdult => 'You must be 18 or older to use Mevora.';

  @override
  String get locationPermissionTitle => 'Discover people nearby';

  @override
  String get locationPermissionMessage =>
      'Mevora uses your location to show more compatible matches around you.';

  @override
  String get locationPermissionSub =>
      'Your exact location is never shown to others. It is only used for matching and distance.';

  @override
  String get useMyLocation => 'Turn on location';

  @override
  String get notNow => 'Skip for now';

  @override
  String get locationSkipHint =>
      'Location is needed for matching and discovery. You can turn it on later in Settings.';

  @override
  String get locationSettingsTitle => 'Location permission is off';

  @override
  String get locationSettingsMessage =>
      'You can turn on location permission in your device settings.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get gpsDisabledTitle => 'Location services are off';

  @override
  String get gpsDisabledMessage =>
      'Turn on location services on your device so we can show nearby matches.';

  @override
  String get locationDeniedMessage =>
      'Without location permission we cannot show matches near you.';

  @override
  String get locationSuccessTitle =>
      'Nice. We are ready to find matches nearby.';

  @override
  String get locationLocating => 'Finding your location...';

  @override
  String get locationPreparingMatches => 'Preparing nearby matches...';

  @override
  String get locationUnavailableTitle => 'Could not get your location';

  @override
  String get locationTimeoutMessage =>
      'The location request timed out. You can try again later.';

  @override
  String get locationNetworkMessage =>
      'Your location could not be saved because of a connection issue. Try again.';

  @override
  String get locationPreciseOffTitle => 'Precise location is off';

  @override
  String get locationPreciseOffMessage =>
      'Precise Location is off. Distance will be approximate; your exact coordinates are still not shared.';

  @override
  String get continueWithoutLocation => 'Continue without location';

  @override
  String get discoveryTitle => 'Your matches are next';

  @override
  String get discoveryMessage =>
      'Compatible people will appear here once discovery is ready.';

  @override
  String get discoveryEmptyTitle => 'No one new right now';

  @override
  String get discoveryEmptyMessage =>
      'Widen your distance or check back a little later.';

  @override
  String get tabDiscovery => 'Discover';

  @override
  String get tabMatches => 'Matches';

  @override
  String get tabProfile => 'Profile';

  @override
  String get radius => 'Radius';

  @override
  String distanceAway(String distance) {
    return '$distance km away';
  }

  @override
  String get distanceLessThanOne => 'Less than 1 km away';

  @override
  String get distanceFar => '100+ km away';

  @override
  String compatibilityPercent(int percent) {
    return '$percent% match';
  }

  @override
  String get like => 'Like';

  @override
  String get pass => 'Pass';

  @override
  String get superLike => 'Super Like';

  @override
  String get itsAMatch => 'It\'s a match';

  @override
  String get startChat => 'Say hello';

  @override
  String get keepSwiping => 'Keep exploring';

  @override
  String get profile => 'Profile';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get photos => 'Photos';

  @override
  String get bio => 'Bio';

  @override
  String get interests => 'Interests';

  @override
  String get preferences => 'Preferences';

  @override
  String get account => 'Account';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageTurkish => 'Türkçe 🇹🇷';

  @override
  String get languageEnglish => 'English 🇬🇧';

  @override
  String get theme => 'Theme';

  @override
  String get help => 'Help';

  @override
  String get communityGuidelines => 'Community Guidelines';

  @override
  String get blockedUsers => 'Blocked users';

  @override
  String get discoveryPreferences => 'Discovery preferences';

  @override
  String get minAge => 'Minimum age';

  @override
  String get maxAge => 'Maximum age';

  @override
  String get maxDistance => 'Maximum distance';

  @override
  String get matchesTitle => 'Matches';

  @override
  String get matchesEmptyTitle => 'No matches yet';

  @override
  String get matchesEmptyMessage =>
      'When you like each other, the conversation starts here.';

  @override
  String get newMatch => 'New match';

  @override
  String get chatHint => 'Write a message...';

  @override
  String get send => 'Send';

  @override
  String get typing => 'is typing...';

  @override
  String get unmatchedBanner => 'You are no longer matched with this person.';

  @override
  String get videoCall => 'Video call';

  @override
  String get more => 'More';

  @override
  String get cannotMessageSelf => 'You cannot message yourself.';

  @override
  String get blockedInteraction => 'You cannot message this person.';

  @override
  String get matchInactive => 'This match is no longer active.';

  @override
  String get notMatched =>
      'You can only chat with people you have matched with.';

  @override
  String get alreadySwiped => 'You already decided on this person.';

  @override
  String get chatNotFound => 'Chat not found.';

  @override
  String get chatGeneric => 'Message could not be sent. Please try again.';

  @override
  String get incomingCall => 'Incoming video call';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get endCall => 'End';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get cameraOn => 'Turn camera on';

  @override
  String get cameraOff => 'Turn camera off';

  @override
  String get speaker => 'Speaker';

  @override
  String get switchCamera => 'Flip camera';

  @override
  String get userBusy => 'This person is already on another call.';

  @override
  String get callNotConfigured => 'Video calling is not available right now.';

  @override
  String get cameraDenied => 'A video call needs camera permission.';

  @override
  String get micDenied => 'A call needs microphone permission.';

  @override
  String get connectionUnstable => 'Connection is unstable';

  @override
  String get reconnecting => 'Reconnecting…';

  @override
  String get callFailed => 'Could not connect the call. Please try again.';

  @override
  String get callEnded => 'Call ended';

  @override
  String get connecting => 'Connecting…';

  @override
  String get calling => 'Calling…';

  @override
  String get ringing => 'Ringing…';

  @override
  String get missedCall => 'Missed video call';

  @override
  String get callPermissionTitle => 'Camera and microphone';

  @override
  String get callPermissionBody =>
      'Video calls need camera and microphone permission.';

  @override
  String get presenceOnline => 'Online';

  @override
  String get presenceRecentlyActive => 'Active recently';

  @override
  String get presenceOffline => 'Offline';

  @override
  String get timeNow => 'now';

  @override
  String timeMinutes(int count) {
    return '${count}m';
  }

  @override
  String timeHours(int count) {
    return '${count}h';
  }

  @override
  String timeDays(int count) {
    return '${count}d';
  }

  @override
  String get unmatch => 'Unmatch';

  @override
  String get unmatchConfirmTitle => 'Unmatch this person?';

  @override
  String get unmatchConfirmMessage =>
      'You will not be able to message each other, and the chat will close.';

  @override
  String get block => 'Block';

  @override
  String get blockConfirmTitle => 'Block this person?';

  @override
  String get blockConfirmMessage =>
      'They will disappear from discovery, and you will not be able to message or call each other.';

  @override
  String get report => 'Report';

  @override
  String get reportTitle => 'Why are you reporting?';

  @override
  String get reportDescription => 'Details (optional)';

  @override
  String get submitReport => 'Submit report';

  @override
  String get reportThanks => 'Thanks. We received your report.';

  @override
  String get offerBlockTitle => 'Want to block them too?';

  @override
  String get offerBlockMessage =>
      'Blocking stops new messages, matches, and calls.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportHarassment => 'Harassment';

  @override
  String get reportInappropriate => 'Inappropriate content';

  @override
  String get reportScam => 'Scam';

  @override
  String get reportFakeProfile => 'Fake profile';

  @override
  String get reportUnderage => 'Underage';

  @override
  String get reportOther => 'Other';

  @override
  String get linkedAccounts => 'Linked accounts';

  @override
  String get link => 'Link';

  @override
  String get linked => 'Linked';

  @override
  String get linkEmailTitle => 'Link email and password';

  @override
  String get linkEmailSubtitle =>
      'This adds email sign-in to your current account. It does not merge another Mevora account.';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'This permanently deletes your Mevora account, profile, matches, and messages. This cannot be undone.';

  @override
  String get deleteConfirm => 'Delete forever';

  @override
  String get notificationsTitle => 'Notifications and privacy';

  @override
  String get messageNotifications => 'Message notifications';

  @override
  String get matchNotifications => 'Match notifications';

  @override
  String get callNotifications => 'Call notifications';

  @override
  String get hideOnlineStatus => 'Hide my online status';

  @override
  String get notificationNewMatch => 'You have a new match!';

  @override
  String get notificationNewMessage => 'You have a new message';

  @override
  String get notificationSuperLike => 'Someone Super Liked you';

  @override
  String get boostTitle => 'BOOST';

  @override
  String get boostSubtitle =>
      'Show your profile to more people and get discovered faster.';

  @override
  String get boostDuration => '30 minutes';

  @override
  String get boostActivate => 'Activate Boost';

  @override
  String get boostBuy => 'Buy Boost';

  @override
  String get boostPurchasing => 'Starting purchase...';

  @override
  String get boostVerifying => 'Confirming your purchase...';

  @override
  String get boostSuccessTitle => 'Boost is on! 🚀';

  @override
  String get boostSuccessMessage =>
      'Your profile will start appearing to more people.';

  @override
  String get boostAlreadyActive => 'You already have an active Boost.';

  @override
  String get boostPurchaseCancelled => 'Purchase cancelled.';

  @override
  String get boostPurchaseFailed =>
      'Purchase could not be completed. Please try again.';

  @override
  String get boostStoreUnavailable =>
      'The store is not available on this device right now.';

  @override
  String get boostStoreDown =>
      'The store is not responding. Try again in a moment.';

  @override
  String get boostNetworkError =>
      'We could not verify the purchase because of a connection issue.';

  @override
  String get boostVerificationFailed =>
      'We could not verify the purchase. Try again in a moment.';

  @override
  String get boostAlreadyProcessed => 'This purchase was already processed.';

  @override
  String get boostLoadingProduct => 'Loading store details...';

  @override
  String get boostBackToDiscovery => 'Back to Discover';

  @override
  String get boostTooltip => 'Boost';

  @override
  String boostRemainingMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String radiusKm(int km) {
    return '$km km';
  }

  @override
  String get paymentTitle => 'Payment';

  @override
  String get paymentProcessing => 'Processing payment...';

  @override
  String get paymentSuccess => 'Payment successful.';

  @override
  String get paymentFailed => 'Payment failed. Please try again.';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get startupUnavailable =>
      'Mevora could not start. Check your connection and try again.';

  @override
  String get permissionCameraTitle => 'Camera';

  @override
  String get permissionCameraDescription =>
      'Mevora uses your camera to take profile photos.';

  @override
  String get permissionMicrophoneTitle => 'Microphone';

  @override
  String get permissionMicrophoneDescription =>
      'Mevora uses your microphone for voice and audio features.';

  @override
  String get permissionPhotosTitle => 'Photos';

  @override
  String get permissionPhotosDescription =>
      'Mevora needs access to your photos so you can add profile pictures.';

  @override
  String get permissionLocationTitle => 'Location';

  @override
  String get permissionLocationDescription =>
      'Mevora uses your location to improve distance and nearby discovery.';

  @override
  String get permissionNotificationsTitle => 'Notifications';

  @override
  String get permissionNotificationsDescription =>
      'Notifications help you know when you receive a match or message.';

  @override
  String get permissionAllow => 'Continue';

  @override
  String get permissionDeniedTitle => 'Permission needed';

  @override
  String get permissionDeniedBody =>
      'This feature works better with permission. You can try again, or continue without it.';

  @override
  String get permissionPermanentlyDeniedBody =>
      'Permission is turned off. You can enable it in device settings.';

  @override
  String get permissionContinueWithout => 'Continue without permission';

  @override
  String get permissionStatusGranted => 'Allowed';

  @override
  String get permissionStatusDenied => 'Not allowed';

  @override
  String get permissionStatusRestricted => 'Restricted';

  @override
  String get permissionStatusLimited => 'Limited access';

  @override
  String get permissionStatusPermanentlyDenied => 'Off — open device settings';

  @override
  String get permissionStatusUnknown => 'Unknown';

  @override
  String get privacyPermissionsTitle => 'Privacy & Permissions';

  @override
  String get privacyPermissionsSubtitle =>
      'Mevora asks for each permission only when a feature needs it. You can use the app without granting optional access.';

  @override
  String get privacyOpenDeviceSettings => 'Open device settings';

  @override
  String get selectCityInstead => 'Choose a city instead';

  @override
  String get addPhotoCamera => 'Take photo';

  @override
  String get addPhotoGallery => 'Choose from gallery';

  @override
  String get enableDeviceNotifications => 'Enable notifications';
}
