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
  String get loginSlogan =>
      'Don\'t just meet people.\nMeet someone compatible.';

  @override
  String get continueWithEmail => 'Continue with email';

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
  String get signingIn => 'Signing in...';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueWithSpotify => 'Continue with Spotify';

  @override
  String get continueWithPhone => 'Sign in with Phone Number';

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
  String get phoneTitle => 'Sign in with Phone Number';

  @override
  String get phoneSubtitle =>
      'Choose your country code and enter your phone number. We\'ll send a 6-digit verification code by SMS.';

  @override
  String get phoneHint => '555 000 0000';

  @override
  String get sendCode => 'Send verification code';

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
  String get authAppVerification =>
      'App verification failed. Check SHA certificates, try a physical device, or use a Firebase Console test phone number.';

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
  String get authNotConfigured =>
      'Phone sign-in is not enabled for this Firebase project yet.';

  @override
  String get authBillingNotEnabled =>
      'Firebase billing (Blaze) is required to send SMS verification codes.';

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
  String get googleSignInCancelled => 'Google Sign-In was cancelled.';

  @override
  String get googleSignInFailed => 'Google Sign-In could not be completed.';

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
  String onboardingStepProgress(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get onboardingBack => 'Back';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingEducation => 'Education';

  @override
  String get onboardingLifestyle => 'Lifestyle';

  @override
  String get onboardingSmoking => 'Smoking';

  @override
  String get onboardingDrinking => 'Drinking';

  @override
  String get onboardingExercise => 'Exercise';

  @override
  String get onboardingPets => 'Pets';

  @override
  String get onboardingInterestsHint =>
      'Pick at least 3 interests so Mevora can find compatible people.';

  @override
  String get onboardingBioHint => 'Share a little about yourself.';

  @override
  String get onboardingPhotosHint =>
      'Add at least 3 photos. Drag to reorder — your first photo is your main one.';

  @override
  String get onboardingPrimaryPhoto => 'Main photo';

  @override
  String onboardingPhotoNumber(int number) {
    return 'Photo $number';
  }

  @override
  String get onboardingCompleteTitle => 'You\'re all set';

  @override
  String get onboardingCompleteMessage =>
      'Your profile is ready. Mevora will start introducing compatible people.';

  @override
  String get onboardingStartDiscovering => 'Start discovering';

  @override
  String get onboardingGenderMan => 'Man';

  @override
  String get onboardingGenderWoman => 'Woman';

  @override
  String get onboardingGenderNonBinary => 'Non-binary';

  @override
  String get onboardingInterestedMen => 'Men';

  @override
  String get onboardingInterestedWomen => 'Women';

  @override
  String get onboardingInterestedEveryone => 'Everyone';

  @override
  String get onboardingEducationHighSchool => 'High school';

  @override
  String get onboardingEducationSomeCollege => 'Some college';

  @override
  String get onboardingEducationBachelors => 'Bachelor\'s degree';

  @override
  String get onboardingEducationMasters => 'Master\'s degree';

  @override
  String get onboardingEducationPhd => 'PhD';

  @override
  String get onboardingEducationPreferNotToSay => 'Prefer not to say';

  @override
  String get onboardingRelationshipLongTerm => 'Long-term relationship';

  @override
  String get onboardingRelationshipShortTerm => 'Short-term connection';

  @override
  String get onboardingRelationshipFriendship => 'New friends';

  @override
  String get onboardingRelationshipNotSure => 'Still figuring it out';

  @override
  String get onboardingRelationshipPreferNotToSay => 'Prefer not to say';

  @override
  String get onboardingLifestyleNever => 'Never';

  @override
  String get onboardingLifestyleSometimes => 'Sometimes';

  @override
  String get onboardingLifestyleRegularly => 'Regularly';

  @override
  String get onboardingLifestyleDaily => 'Daily';

  @override
  String get onboardingLifestyleNone => 'None';

  @override
  String get onboardingLifestyleCat => 'Cat';

  @override
  String get onboardingLifestyleDog => 'Dog';

  @override
  String get onboardingLifestyleBoth => 'Both';

  @override
  String get onboardingLifestyleOther => 'Other';

  @override
  String get interestMusic => 'Music';

  @override
  String get interestTravel => 'Travel';

  @override
  String get interestFitness => 'Fitness';

  @override
  String get interestFood => 'Food';

  @override
  String get interestArt => 'Art';

  @override
  String get interestMovies => 'Movies';

  @override
  String get interestBooks => 'Books';

  @override
  String get interestGaming => 'Gaming';

  @override
  String get interestNature => 'Nature';

  @override
  String get interestPhotography => 'Photography';

  @override
  String get interestCoffee => 'Coffee';

  @override
  String get interestDancing => 'Dancing';

  @override
  String get interestYoga => 'Yoga';

  @override
  String get interestTech => 'Tech';

  @override
  String get interestFashion => 'Fashion';

  @override
  String get interestPets => 'Pets';

  @override
  String get interestSports => 'Sports';

  @override
  String get interestCooking => 'Cooking';

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
  String get discoverySeenEveryoneTitle => 'You\'ve seen everyone for now';

  @override
  String get discoverySeenEveryoneMessage =>
      'Check back later for new people, or restart the demo to explore again.';

  @override
  String get exploreAgain => 'Explore again';

  @override
  String get restartDemo => 'Restart demo';

  @override
  String get discoveryFiltersTitle => 'Discovery filters';

  @override
  String get discoveryFiltersHint =>
      'Filters are saved locally. Server-side filtering arrives in a later update.';

  @override
  String get applyFilters => 'Apply filters';

  @override
  String get filterAge => 'Age range';

  @override
  String get filterDistance => 'Maximum distance';

  @override
  String get filterGender => 'Show me';

  @override
  String get filterRelationshipGoal => 'Relationship goal';

  @override
  String get genderWoman => 'Women';

  @override
  String get genderMan => 'Men';

  @override
  String get genderNonBinary => 'Non-binary';

  @override
  String get relationshipGoalLongTerm => 'Long-term';

  @override
  String get relationshipGoalCasual => 'Casual';

  @override
  String get relationshipGoalFiguringOut => 'Still figuring it out';

  @override
  String get compatibilityReasonsHeading => 'Why you might connect';

  @override
  String get whyYoureSeeingThis => 'Why this profile is shown';

  @override
  String get sharedInterests => 'Shared interests';

  @override
  String get profileDetailsTitle => 'Profile';

  @override
  String photoCounter(int current, int total) {
    return '$current / $total';
  }

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
    return 'Suggested · $percent% compatible';
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
  String get youLikedEachOther => 'You liked each other!';

  @override
  String get sendMessage => 'Send message';

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
  String get chatEmptyTitle => 'No messages yet';

  @override
  String get chatEmptyMessage => 'Send the first message.';

  @override
  String get send => 'Send';

  @override
  String get typing => 'is typing...';

  @override
  String get attachPhoto => 'Photo';

  @override
  String get takePhoto => 'Camera';

  @override
  String get recordVoice => 'Voice message';

  @override
  String get holdToRecord => 'Recording…';

  @override
  String get playVoice => 'Play';

  @override
  String get pauseVoice => 'Pause';

  @override
  String get previewPhoto => 'Send this photo?';

  @override
  String get messageDeleted => 'Message deleted';

  @override
  String get deleteMessage => 'Delete';

  @override
  String get deleteMessageConfirm =>
      'Delete this message? The other person will no longer see it.';

  @override
  String get micDeniedChat =>
      'Microphone permission is needed to send a voice message.';

  @override
  String get photoDeniedChat => 'Photo permission is needed to send an image.';

  @override
  String get callCancelled => 'Call cancelled';

  @override
  String get callRejected => 'Call declined';

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
  String get hideProfile => 'Hide profile';

  @override
  String get hideProfileTitle => 'Hide this profile?';

  @override
  String get hideProfileMessage =>
      'They will not appear in your discovery stack again.';

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
  String get boostDuration => 'Boost your profile';

  @override
  String get boostActivate => 'Use leftover Boost';

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
  String get boostAlreadyActive =>
      'You already have an active Boost. Buying another pack adds time to the remaining period.';

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
    return '$minutes min left';
  }

  @override
  String boostRemainingDays(int days) {
    return '$days days left';
  }

  @override
  String boostRemainingHours(int hours) {
    return '$hours hours left';
  }

  @override
  String get boostSpotlight => 'Boost Profile';

  @override
  String get boostPackOne => '1 Boost';

  @override
  String get boostPackFive => '5 Boost';

  @override
  String get boostPackTen => '10 Boost';

  @override
  String boostPackCount(int count) {
    return '$count Boost';
  }

  @override
  String get boostPackWeek => '1 Week';

  @override
  String get boostPackMonth => '1 Month';

  @override
  String get boostPackYear => '1 Year';

  @override
  String get boostPackWeekSubtitle => 'Boost your profile for 7 days';

  @override
  String get boostPackMonthSubtitle => 'Boost your profile for 30 days';

  @override
  String get boostPackYearSubtitle => 'Boost your profile for 365 days';

  @override
  String get boostBestValue => 'Best value';

  @override
  String boostBalance(int count) {
    return '$count leftover Boost';
  }

  @override
  String get boostBuyPack => 'Buy';

  @override
  String get boostCreditedTitle => 'Boosts added to your account';

  @override
  String boostCreditedMessage(int count) {
    return '$count Boost added. Activate when you are ready.';
  }

  @override
  String get boostInsufficientBalance =>
      'You need a Boost before you can go live.';

  @override
  String get boostHistoryTitle => 'Purchase history';

  @override
  String get boostHistoryEmpty => 'No purchases yet.';

  @override
  String get boostHistoryPurchase => 'Purchase';

  @override
  String get boostHistoryActivation => 'Activation';

  @override
  String get boostHistoryPlatformIos => 'App Store';

  @override
  String get boostHistoryPlatformAndroid => 'Google Play';

  @override
  String get boostActiveBadge => 'Boost on';

  @override
  String get boostActivating => 'Turning Boost on...';

  @override
  String get boostNoBalance => 'Choose a pack to Boost your profile.';

  @override
  String get boostPriceUnavailable => 'Price unavailable';

  @override
  String get boostRestoring => 'Restoring purchases...';

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
  String get photoEmptyHint => 'Add your first photo to continue.';

  @override
  String get photoMinRequired => 'You must add at least 3 photos.';

  @override
  String photoUploadingPercent(int percent) {
    return 'Uploading photo... $percent%';
  }

  @override
  String get photoUploadFailed =>
      'Photo could not be uploaded. Please try again.';

  @override
  String get photoUploaded => 'Photo uploaded';

  @override
  String get photoSelected => 'Photo selected';

  @override
  String get photoRetry => 'Try again';

  @override
  String get enableDeviceNotifications => 'Enable notifications';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsEmailUnavailable => 'No email on file';

  @override
  String get settingsReadOnly => 'Read-only';

  @override
  String get settingsPrivacySafety => 'Privacy & Safety';

  @override
  String get settingsPrivacyControls => 'Privacy';

  @override
  String get settingsLocation => 'Location';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsLogoutTitle => 'Log out?';

  @override
  String get settingsLogoutBody =>
      'You will need to sign in again to use Mevora.';

  @override
  String get settingsDeleteConfirmTitle => 'This is permanent';

  @override
  String get settingsDeleteConfirmBody =>
      'All matches, messages, and profile data will be deleted forever.';

  @override
  String get settingsReauthTitle => 'Confirm your identity';

  @override
  String get settingsCurrentPasswordRequired => 'Enter your current password.';

  @override
  String get settingsNewPasswordRequired => 'Enter a new password.';

  @override
  String get settingsConfirmPasswordRequired => 'Confirm your new password.';

  @override
  String get settingsPasswordsDoNotMatch => 'Passwords do not match.';

  @override
  String get settingsPhotoMinRequired => 'Keep at least 3 profile photos.';

  @override
  String get settingsPhotoMaxExceeded => 'You can add up to 6 photos.';

  @override
  String get settingsPhotoPrimaryDeleteBlocked =>
      'Set another photo as primary before deleting this one.';

  @override
  String get settingsPhotoPrimaryRequired => 'Choose a primary photo.';

  @override
  String get settingsFirstNameRequired => 'First name is required.';

  @override
  String get settingsFirstNameTooLong => 'First name is too long.';

  @override
  String get settingsBioTooLong => 'Bio is too long.';

  @override
  String get settingsInterestsTooMany => 'Choose fewer interests.';

  @override
  String get settingsMinAgeInvalid => 'Minimum age must be at least 18.';

  @override
  String get settingsMaxAgeInvalid => 'Maximum age is too high.';

  @override
  String get settingsAgeRangeInvalid =>
      'Maximum age must be greater than minimum age.';

  @override
  String get settingsDistanceInvalid =>
      'Distance must be between 1 and 500 km.';

  @override
  String get settingsGooglePasswordMessage =>
      'Your account uses Google Sign-In. Password changes are managed by Google.';

  @override
  String get settingsBirthDateLocked =>
      'Birthday cannot be changed after onboarding. Age is calculated from your birthday.';

  @override
  String get settingsSaveProfile => 'Save profile';

  @override
  String get settingsUnblock => 'Unblock';

  @override
  String get settingsBlockedEmptyTitle => 'No blocked users';

  @override
  String get settingsBlockedEmptyMessage =>
      'People you block will appear here.';

  @override
  String get settingsShowOnlineStatus => 'Show online status';

  @override
  String get settingsShowDistance => 'Show distance';

  @override
  String get settingsShowActivity => 'Show activity status';

  @override
  String get settingsPushNotifications => 'Push notifications';

  @override
  String get settingsSuperLikeNotifications => 'Super Like notifications';

  @override
  String get settingsSetPrimaryPhoto => 'Set as primary';

  @override
  String get settingsDeletePhoto => 'Remove photo';

  @override
  String get settingsAddPhoto => 'Add photo';

  @override
  String get settingsEducation => 'Education';

  @override
  String get settingsLifestyle => 'Lifestyle';

  @override
  String get settingsInterestedIn => 'Interested in';

  @override
  String get settingsRelationshipGoal => 'Relationship goal';

  @override
  String get settingsCity => 'City';

  @override
  String get settingsGender => 'Gender';

  @override
  String get settingsNewPassword => 'New password';

  @override
  String get settingsCurrentPassword => 'Current password';

  @override
  String get settingsConfirmPassword => 'Confirm password';

  @override
  String get settingsPasswordChanged => 'Password updated.';

  @override
  String get settingsProfileSaved => 'Profile saved.';

  @override
  String get citySelectTitle => 'Select City';

  @override
  String get citySelectSearch => 'Search province…';

  @override
  String get citySelectNone => 'No province found';

  @override
  String get discoveryLoading => 'Discovering people for you...';

  @override
  String get discoveryLoadErrorTitle => 'Couldn\'t load profiles';

  @override
  String get discoveryLoadErrorMessage =>
      'Something went wrong while loading profiles.';

  @override
  String get discoveryChangePreferences => 'Change discovery preferences';

  @override
  String get itsAMatchHeadline => 'IT\'S A MATCH';

  @override
  String get demoProfileBadge => 'Sample';

  @override
  String sharedHobbiesCount(int count) {
    return '$count shared interests';
  }

  @override
  String get tabSettings => 'Settings';

  @override
  String get tabMusic => 'Music';

  @override
  String get musicTitle => 'Music';

  @override
  String get musicConnectCta => '🎵 Connect Spotify';

  @override
  String get musicConnected => '✓ Spotify connected';

  @override
  String get musicUnconnectedCopy =>
      'Connect your Spotify account and discover people who fit your music taste.';

  @override
  String get musicConnecting => 'Connecting Spotify…';

  @override
  String get musicSyncing => 'Refreshing your music taste…';

  @override
  String get musicRefresh => 'Refresh music data';

  @override
  String get musicRefreshCooldown => 'You can refresh again later.';

  @override
  String get musicProfileTitle => 'Your music profile';

  @override
  String get musicSameTasteTitle => 'People who listen to the same music';

  @override
  String get musicSameTasteEmpty =>
      'No overlapping tastes yet. Refresh after you listen a bit more.';

  @override
  String get musicWeeklyTitle => 'This week\'s music';

  @override
  String get musicWeeklyEmpty =>
      'Weekly highlights will appear here once enough people connect Spotify.';

  @override
  String musicCompatibilityPercent(int percent) {
    return 'Similar music taste · up to $percent%';
  }

  @override
  String musicCompatibilityShort(int percent) {
    return 'Music · $percent%';
  }

  @override
  String musicSharedCounts(int tracks, int artists) {
    return '$tracks shared tracks · $artists shared artists';
  }

  @override
  String get musicOauthCancelled => 'Spotify connection was cancelled.';

  @override
  String get musicApiDenied =>
      'Spotify didn\'t allow access. You can try again later.';

  @override
  String get musicTokenExpired =>
      'Your Spotify connection expired. Please reconnect.';

  @override
  String get musicNetwork => 'Check your internet connection and try again.';

  @override
  String get musicNotConfigured =>
      'Spotify isn\'t configured in this build yet.';

  @override
  String get musicConnectError =>
      'Couldn\'t connect Spotify. The rest of Mevora still works.';

  @override
  String get settingsConnectSpotify => 'Connect Spotify';

  @override
  String get settingsSpotifySubtitle =>
      'Music taste matching — no playback in Mevora.';

  @override
  String get matchScoreTitle => 'Match points';

  @override
  String get matchScoreSubtitle => 'Your connection reputation';

  @override
  String matchScoreValue(int score) {
    return '$score points';
  }

  @override
  String get matchScoreHistoryTitle => 'Point history';

  @override
  String get matchScoreHistoryEmpty =>
      'New matches and conversations will add points here.';

  @override
  String get matchScoreHistoryMatch => 'New match +1';

  @override
  String get matchScoreHistoryInteraction => 'Conversation +1';

  @override
  String get matchFeedbackTitle => 'How did this match go?';

  @override
  String get matchFeedbackMessage =>
      'Optional. This note stays in your history — they will not see it, and it does not change anyone\'s points.';

  @override
  String get matchFeedbackHint => 'A short private note';

  @override
  String get matchFeedbackSubmit => 'Save note';

  @override
  String get matchFeedbackThanks => 'Saved to your history.';

  @override
  String get matchFeedbackTooShort => 'Write a short note, or skip.';

  @override
  String get matchFeedbackFailed => 'Couldn\'t save that note. Try again.';

  @override
  String get relationshipPromptTitle =>
      'What do you think about relationships?';

  @override
  String get relationshipQuestionsPreparing =>
      'New questions are being prepared. Please try again in a bit.';

  @override
  String get relationshipTestTitle => 'Relationship Test';

  @override
  String get relationshipTestHeadline => 'Discover people who share your views';

  @override
  String get relationshipTestMessage =>
      'Answer 3 short questions to see people who may think similarly.';

  @override
  String get relationshipTestStart => 'Start the Relationship Test';

  @override
  String get relationshipTestLater => 'Not now';

  @override
  String get relationshipTestDoneTitle => 'Your relationship test is complete';

  @override
  String get relationshipTestFound =>
      'We found someone whose views match yours.';

  @override
  String get relationshipTestAlign => 'Your answers overlap on several topics.';

  @override
  String get relationshipTestNearest => 'Closest to you:';

  @override
  String get relationshipTestEmpty =>
      'There\'s no one nearby who thinks like you right now.';

  @override
  String get relationshipTestViewProfile => 'View profile';

  @override
  String get relationshipTestOpenChat => 'Open chat';

  @override
  String get relationshipMatchBadge => 'Relationship Test';

  @override
  String relationshipPromptProgress(int answered, int total) {
    return '$answered / $total';
  }

  @override
  String relationshipCompatibilityPercent(int percent) {
    return 'Views overlap · $percent%';
  }

  @override
  String relationshipCompatibilityShort(int percent) {
    return 'Views · $percent%';
  }

  @override
  String relationshipSharedViews(int count) {
    return '$count shared views';
  }

  @override
  String get relationshipSimilarThinker =>
      'Someone who thinks similarly about relationships was found.';

  @override
  String get relationshipViewsAlign => 'Your relationship views overlap.';

  @override
  String get relationshipMatchesTitle => 'Relationship matches';

  @override
  String get relationshipMatchesEmpty =>
      'Answer a few relationship questions to find people who think like you — distance does not matter here.';

  @override
  String relationshipProfileSubtitle(int answered) {
    return '$answered relationship questions answered';
  }

  @override
  String get relationshipTopicJealousy => 'You think similarly about jealousy.';

  @override
  String get relationshipTopicTrust => 'You think similarly about trust.';

  @override
  String get relationshipTopicLoyalty => 'You think similarly about loyalty.';

  @override
  String get relationshipTopicCommunication =>
      'You think similarly about communication.';

  @override
  String get relationshipTopicBoundaries =>
      'You think similarly about boundaries.';

  @override
  String get relationshipTopicSocialLife =>
      'You think similarly about social life.';

  @override
  String get relationshipTopicFriendship =>
      'You think similarly about friendship.';

  @override
  String get relationshipTopicPersonalSpace =>
      'You think similarly about personal space.';

  @override
  String get relationshipTopicFuturePlans =>
      'You think similarly about future plans.';

  @override
  String get relationshipTopicMoney => 'You think similarly about money.';

  @override
  String get relationshipTopicFlirting => 'You think similarly about flirting.';

  @override
  String get relationshipTopicExes =>
      'You think similarly about past relationships.';

  @override
  String get relationshipTopicExpectations =>
      'You think similarly about relationship expectations.';

  @override
  String get verifyYourProfile => 'Verify your profile';

  @override
  String get verificationDescription =>
      'Verification helps us keep Mevora authentic and safer for everyone.';

  @override
  String get verificationBenefitFakeProfiles =>
      'Helps protect against fake profiles';

  @override
  String get verificationBenefitSpoofing => 'Helps prevent spoofing';

  @override
  String get verificationBenefitBadge =>
      'Adds a verified badge to your profile';

  @override
  String get startVerification => 'Start verification';

  @override
  String get verificationInProgress => 'Verification in progress';

  @override
  String get profileVerified => 'Profile verified';

  @override
  String get profileVerifiedBadge => 'Verified';

  @override
  String get verificationCouldNotComplete =>
      'Verification couldn\'t be completed';

  @override
  String get tryVerificationAgain => 'Try again';

  @override
  String get verificationStarted => 'Verification started';

  @override
  String get verificationPrivacyNote =>
      'Your verification is handled securely by our verification provider.';

  @override
  String get followVerificationInstructions =>
      'Please follow the instructions to verify yourself.';

  @override
  String get verificationNotConfigured =>
      'Verification is temporarily unavailable.';

  @override
  String get verificationCooldown =>
      'Please wait a few minutes before trying again.';

  @override
  String get verificationAttemptLimit =>
      'You\'ve reached today\'s verification limit. Try again tomorrow.';

  @override
  String get whyYouMatch => 'Why you match';

  @override
  String get compatWhyButton => 'Why?';

  @override
  String compatDiscoverBadge(int percent) {
    return '$percent% Compatible';
  }

  @override
  String get compatCalculating => 'Calculating...';

  @override
  String get compatUnavailable => 'Compatibility unavailable';

  @override
  String get profileEditSectionPhotos => 'Photos';

  @override
  String get profileEditSectionBasic => 'Basic information';

  @override
  String get profileEditSectionAbout => 'About you';

  @override
  String get profileEditSectionInterests => 'Your interests';

  @override
  String get profileEditSectionLifestyle => 'Lifestyle';

  @override
  String get profileEditSectionRelationship => 'Relationship preferences';

  @override
  String get profileEditSectionAnswers => 'Your answers';

  @override
  String get profileEditDiscoveryPrefs => 'Age range & distance';

  @override
  String get profileEditAnswersSubtitle =>
      'Update how you answer relationship questions';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesMessage =>
      'Your profile changes haven\'t been saved.';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get discard => 'Discard';

  @override
  String get interestsMinRequired => 'Select at least 3 interests';

  @override
  String get profileAnswersTitle => 'Your answers';

  @override
  String get profileAnswersEmpty =>
      'You haven\'t answered any relationship questions yet.';

  @override
  String get profileAnswersEdit => 'Edit';

  @override
  String compatOverallLabel(int percent) {
    return 'You\'re $percent% compatible';
  }

  @override
  String get compatNotEnoughData => 'Not enough data yet';

  @override
  String get compatStrongestConnection => 'Strongest connection';

  @override
  String get compatPotentialDifference => 'Potential difference';

  @override
  String get compatCategoryOverall => 'Overall';

  @override
  String get compatCategoryRelationship => 'Relationship';

  @override
  String get compatCategoryInterests => 'Interests';

  @override
  String get compatCategoryLifestyle => 'Lifestyle';

  @override
  String get compatCategoryQuestions => 'Questions';

  @override
  String get compatCategoryMusic => 'Music';

  @override
  String get compatCategoryCommunication => 'Communication';

  @override
  String get compatCategoryProximity => 'Proximity';

  @override
  String get compatCategoryActivity => 'Activity';

  @override
  String compatReasonSameRelationshipGoal(String goal) {
    return 'You both want a $goal relationship';
  }

  @override
  String compatReasonSharedInterests(String interests) {
    return 'You both like $interests';
  }

  @override
  String get compatReasonSimilarLifestyle => 'You have a similar lifestyle';

  @override
  String compatReasonSameAnswers(String aligned, String shared) {
    return 'You answered $aligned of $shared questions the same way';
  }

  @override
  String compatReasonSimilarMusic(String score) {
    return 'Your music taste is $score% aligned';
  }

  @override
  String get compatReasonCommunication => 'You communicate in similar ways';

  @override
  String get hiddenCompatTitle => 'Someone is thinking like you 👀';

  @override
  String hiddenCompatMessage(int count) {
    return 'Someone answered $count questions the same way you did.';
  }

  @override
  String hiddenCompatCompatibility(int percent) {
    return '$percent% compatibility';
  }

  @override
  String get hiddenCompatCta => 'Discover who';

  @override
  String get hiddenCompatDismiss => 'Not now';
}
