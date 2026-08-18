import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Mevora'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Find compatible people, not just nearby people.'**
  String get tagline;

  /// No description provided for @connectTagline.
  ///
  /// In en, this message translates to:
  /// **'Connect with people who match you.'**
  String get connectTagline;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'The app hit an unexpected error.'**
  String get unexpectedError;

  /// No description provided for @firebaseUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Mevora could not start. Check your connection and try again.'**
  String get firebaseUnavailableMessage;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @emptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyTitle;

  /// No description provided for @emptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When there is something to show, it will appear here.'**
  String get emptyMessage;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get networkError;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'We could not find that.'**
  String get notFound;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'This part of Mevora is not ready yet.'**
  String get comingSoon;

  /// No description provided for @notAllowed.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do that.'**
  String get notAllowed;

  /// No description provided for @needSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue.'**
  String get needSignIn;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to keep discovering compatible people.'**
  String get loginSubtitle;

  /// No description provided for @createAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createAccountTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Mevora to meet people you are likely to connect with.'**
  String get registerSubtitle;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'you@email.com'**
  String get emailHint;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get emailInvalid;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {min} characters'**
  String passwordMinLength(int min);

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'{field} is required'**
  String fieldRequired(String field);

  /// No description provided for @fieldMinLength.
  ///
  /// In en, this message translates to:
  /// **'{field} must be at least {min} characters'**
  String fieldMinLength(String field, int min);

  /// No description provided for @phoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone is required'**
  String get phoneRequired;

  /// No description provided for @codeRequired.
  ///
  /// In en, this message translates to:
  /// **'Code is required'**
  String get codeRequired;

  /// No description provided for @otpInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get otpInvalidFormat;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we will send a reset link.'**
  String get resetPasswordMessage;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @resetEmailSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get resetEmailSentTitle;

  /// No description provided for @resetEmailSentMessage.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, a reset link is on the way.'**
  String get resetEmailSentMessage;

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn;

  /// No description provided for @orContinueWith.
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get orContinueWith;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @continueWithSpotify.
  ///
  /// In en, this message translates to:
  /// **'Continue with Spotify'**
  String get continueWithSpotify;

  /// No description provided for @continueWithPhone.
  ///
  /// In en, this message translates to:
  /// **'Continue with phone'**
  String get continueWithPhone;

  /// No description provided for @legalPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to our'**
  String get legalPrefix;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @legalConjunction.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get legalConjunction;

  /// No description provided for @signInWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Sign in with email'**
  String get signInWithEmail;

  /// No description provided for @newToMevora.
  ///
  /// In en, this message translates to:
  /// **'New to Mevora?'**
  String get newToMevora;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @createAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAnAccount;

  /// No description provided for @preparingMevora.
  ///
  /// In en, this message translates to:
  /// **'Preparing Mevora'**
  String get preparingMevora;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @appleSignInUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Apple Sign-In is available on iPhone and iPad.'**
  String get appleSignInUnavailable;

  /// No description provided for @phoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get phoneTitle;

  /// No description provided for @phoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will text you a verification code.'**
  String get phoneSubtitle;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'555 000 0000'**
  String get phoneHint;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send SMS code'**
  String get sendCode;

  /// No description provided for @countrySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search country'**
  String get countrySearchHint;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your phone'**
  String get otpTitle;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resend;

  /// No description provided for @sendingSms.
  ///
  /// In en, this message translates to:
  /// **'Sending SMS...'**
  String get sendingSms;

  /// No description provided for @verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get verifying;

  /// No description provided for @phoneVerifiedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your phone number is verified.'**
  String get phoneVerifiedSuccess;

  /// No description provided for @countryCode.
  ///
  /// In en, this message translates to:
  /// **'Country code'**
  String get countryCode;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @otpFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'6-digit verification code'**
  String get otpFieldLabel;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to {phone}.'**
  String otpSentTo(String phone);

  /// No description provided for @resendCountdown.
  ///
  /// In en, this message translates to:
  /// **'You can request a new code in {seconds} seconds.'**
  String resendCountdown(int seconds);

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter the verification code.'**
  String get enterOtp;

  /// No description provided for @authCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sign-in was cancelled.'**
  String get authCancelled;

  /// No description provided for @authInvalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get authInvalidPhone;

  /// No description provided for @authSmsFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not send the SMS. Please try again.'**
  String get authSmsFailed;

  /// No description provided for @authInvalidOtp.
  ///
  /// In en, this message translates to:
  /// **'Invalid verification code.'**
  String get authInvalidOtp;

  /// No description provided for @authExpiredOtp.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Request a new one.'**
  String get authExpiredOtp;

  /// No description provided for @authSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please enter your number again.'**
  String get authSessionExpired;

  /// No description provided for @authTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait and try again.'**
  String get authTooManyAttempts;

  /// No description provided for @authSmsQuota.
  ///
  /// In en, this message translates to:
  /// **'SMS sending limit reached. Please try again later.'**
  String get authSmsQuota;

  /// No description provided for @authFirebaseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Verification is temporarily unavailable. Please try again later.'**
  String get authFirebaseUnavailable;

  /// No description provided for @authNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection.'**
  String get authNetwork;

  /// No description provided for @authDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled.'**
  String get authDisabled;

  /// No description provided for @authBanned.
  ///
  /// In en, this message translates to:
  /// **'This account has been suspended.'**
  String get authBanned;

  /// No description provided for @authOauth.
  ///
  /// In en, this message translates to:
  /// **'We could not complete sign-in. Please try again.'**
  String get authOauth;

  /// No description provided for @authUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something unexpected happened. Please try again.'**
  String get authUnknown;

  /// No description provided for @authAccountExists.
  ///
  /// In en, this message translates to:
  /// **'That sign-in method is already tied to another Mevora account. Accounts are never merged automatically.'**
  String get authAccountExists;

  /// No description provided for @authLinkingBlocked.
  ///
  /// In en, this message translates to:
  /// **'Accounts are linked only when you confirm. A matching email is not enough.'**
  String get authLinkingBlocked;

  /// No description provided for @authNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'This sign-in method is not set up yet.'**
  String get authNotConfigured;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authInvalidEmail;

  /// No description provided for @authWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Choose a stronger password with at least 8 characters.'**
  String get authWeakPassword;

  /// No description provided for @authUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'No account found for that email.'**
  String get authUserNotFound;

  /// No description provided for @authWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'That email and password combination does not match.'**
  String get authWrongPassword;

  /// No description provided for @authSpotifyCallbackExpired.
  ///
  /// In en, this message translates to:
  /// **'The Spotify session timed out. Please try again.'**
  String get authSpotifyCallbackExpired;

  /// No description provided for @authEmailInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists for that email.'**
  String get authEmailInUse;

  /// No description provided for @authGeneric.
  ///
  /// In en, this message translates to:
  /// **'We could not complete that request. Please try again.'**
  String get authGeneric;

  /// No description provided for @authGoogleFailed.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In could not be completed.'**
  String get authGoogleFailed;

  /// No description provided for @authAppleFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple Sign-In could not be completed.'**
  String get authAppleFailed;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'A few more steps'**
  String get onboardingTitle;

  /// No description provided for @onboardingMessage.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile so Mevora can introduce compatible people.'**
  String get onboardingMessage;

  /// No description provided for @onboardingFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get onboardingFirstName;

  /// No description provided for @onboardingBirthDate.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get onboardingBirthDate;

  /// No description provided for @onboardingGender.
  ///
  /// In en, this message translates to:
  /// **'I am'**
  String get onboardingGender;

  /// No description provided for @onboardingInterestedIn.
  ///
  /// In en, this message translates to:
  /// **'Interested in'**
  String get onboardingInterestedIn;

  /// No description provided for @onboardingCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get onboardingCity;

  /// No description provided for @onboardingPhotos.
  ///
  /// In en, this message translates to:
  /// **'Profile photos'**
  String get onboardingPhotos;

  /// No description provided for @onboardingBio.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get onboardingBio;

  /// No description provided for @onboardingInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get onboardingInterests;

  /// No description provided for @onboardingRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'Looking for'**
  String get onboardingRelationshipGoal;

  /// No description provided for @onboardingAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get onboardingAddPhoto;

  /// No description provided for @onboardingMustBeAdult.
  ///
  /// In en, this message translates to:
  /// **'You must be 18 or older to use Mevora.'**
  String get onboardingMustBeAdult;

  /// No description provided for @locationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover people nearby'**
  String get locationPermissionTitle;

  /// No description provided for @locationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Mevora uses your location to show more compatible matches around you.'**
  String get locationPermissionMessage;

  /// No description provided for @locationPermissionSub.
  ///
  /// In en, this message translates to:
  /// **'Your exact location is never shown to others. It is only used for matching and distance.'**
  String get locationPermissionSub;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Turn on location'**
  String get useMyLocation;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get notNow;

  /// No description provided for @locationSkipHint.
  ///
  /// In en, this message translates to:
  /// **'Location is needed for matching and discovery. You can turn it on later in Settings.'**
  String get locationSkipHint;

  /// No description provided for @locationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Location permission is off'**
  String get locationSettingsTitle;

  /// No description provided for @locationSettingsMessage.
  ///
  /// In en, this message translates to:
  /// **'You can turn on location permission in your device settings.'**
  String get locationSettingsMessage;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @gpsDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Location services are off'**
  String get gpsDisabledTitle;

  /// No description provided for @gpsDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services on your device so we can show nearby matches.'**
  String get gpsDisabledMessage;

  /// No description provided for @locationDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Without location permission we cannot show matches near you.'**
  String get locationDeniedMessage;

  /// No description provided for @locationSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Nice. We are ready to find matches nearby.'**
  String get locationSuccessTitle;

  /// No description provided for @locationLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding your location...'**
  String get locationLocating;

  /// No description provided for @locationPreparingMatches.
  ///
  /// In en, this message translates to:
  /// **'Preparing nearby matches...'**
  String get locationPreparingMatches;

  /// No description provided for @locationUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not get your location'**
  String get locationUnavailableTitle;

  /// No description provided for @locationTimeoutMessage.
  ///
  /// In en, this message translates to:
  /// **'The location request timed out. You can try again later.'**
  String get locationTimeoutMessage;

  /// No description provided for @locationNetworkMessage.
  ///
  /// In en, this message translates to:
  /// **'Your location could not be saved because of a connection issue. Try again.'**
  String get locationNetworkMessage;

  /// No description provided for @locationPreciseOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Precise location is off'**
  String get locationPreciseOffTitle;

  /// No description provided for @locationPreciseOffMessage.
  ///
  /// In en, this message translates to:
  /// **'Precise Location is off. Distance will be approximate; your exact coordinates are still not shared.'**
  String get locationPreciseOffMessage;

  /// No description provided for @continueWithoutLocation.
  ///
  /// In en, this message translates to:
  /// **'Continue without location'**
  String get continueWithoutLocation;

  /// No description provided for @discoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Your matches are next'**
  String get discoveryTitle;

  /// No description provided for @discoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'Compatible people will appear here once discovery is ready.'**
  String get discoveryMessage;

  /// No description provided for @discoveryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No one new right now'**
  String get discoveryEmptyTitle;

  /// No description provided for @discoveryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Widen your distance or check back a little later.'**
  String get discoveryEmptyMessage;

  /// No description provided for @tabDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get tabDiscovery;

  /// No description provided for @tabMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get tabMatches;

  /// No description provided for @tabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get tabProfile;

  /// No description provided for @radius.
  ///
  /// In en, this message translates to:
  /// **'Radius'**
  String get radius;

  /// No description provided for @distanceAway.
  ///
  /// In en, this message translates to:
  /// **'{distance} km away'**
  String distanceAway(String distance);

  /// No description provided for @distanceLessThanOne.
  ///
  /// In en, this message translates to:
  /// **'Less than 1 km away'**
  String get distanceLessThanOne;

  /// No description provided for @distanceFar.
  ///
  /// In en, this message translates to:
  /// **'100+ km away'**
  String get distanceFar;

  /// No description provided for @compatibilityPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}% match'**
  String compatibilityPercent(int percent);

  /// No description provided for @like.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get like;

  /// No description provided for @pass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get pass;

  /// No description provided for @superLike.
  ///
  /// In en, this message translates to:
  /// **'Super Like'**
  String get superLike;

  /// No description provided for @itsAMatch.
  ///
  /// In en, this message translates to:
  /// **'It\'s a match'**
  String get itsAMatch;

  /// No description provided for @startChat.
  ///
  /// In en, this message translates to:
  /// **'Say hello'**
  String get startChat;

  /// No description provided for @keepSwiping.
  ///
  /// In en, this message translates to:
  /// **'Keep exploring'**
  String get keepSwiping;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @photos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get photos;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @interests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get interests;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageTurkish.
  ///
  /// In en, this message translates to:
  /// **'Türkçe 🇹🇷'**
  String get languageTurkish;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English 🇬🇧'**
  String get languageEnglish;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @help.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get help;

  /// No description provided for @communityGuidelines.
  ///
  /// In en, this message translates to:
  /// **'Community Guidelines'**
  String get communityGuidelines;

  /// No description provided for @blockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsers;

  /// No description provided for @discoveryPreferences.
  ///
  /// In en, this message translates to:
  /// **'Discovery preferences'**
  String get discoveryPreferences;

  /// No description provided for @minAge.
  ///
  /// In en, this message translates to:
  /// **'Minimum age'**
  String get minAge;

  /// No description provided for @maxAge.
  ///
  /// In en, this message translates to:
  /// **'Maximum age'**
  String get maxAge;

  /// No description provided for @maxDistance.
  ///
  /// In en, this message translates to:
  /// **'Maximum distance'**
  String get maxDistance;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matchesTitle;

  /// No description provided for @matchesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matches yet'**
  String get matchesEmptyTitle;

  /// No description provided for @matchesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When you like each other, the conversation starts here.'**
  String get matchesEmptyMessage;

  /// No description provided for @newMatch.
  ///
  /// In en, this message translates to:
  /// **'New match'**
  String get newMatch;

  /// No description provided for @chatHint.
  ///
  /// In en, this message translates to:
  /// **'Write a message...'**
  String get chatHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'is typing...'**
  String get typing;

  /// No description provided for @unmatchedBanner.
  ///
  /// In en, this message translates to:
  /// **'You are no longer matched with this person.'**
  String get unmatchedBanner;

  /// No description provided for @videoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get videoCall;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @cannotMessageSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot message yourself.'**
  String get cannotMessageSelf;

  /// No description provided for @blockedInteraction.
  ///
  /// In en, this message translates to:
  /// **'You cannot message this person.'**
  String get blockedInteraction;

  /// No description provided for @matchInactive.
  ///
  /// In en, this message translates to:
  /// **'This match is no longer active.'**
  String get matchInactive;

  /// No description provided for @notMatched.
  ///
  /// In en, this message translates to:
  /// **'You can only chat with people you have matched with.'**
  String get notMatched;

  /// No description provided for @alreadySwiped.
  ///
  /// In en, this message translates to:
  /// **'You already decided on this person.'**
  String get alreadySwiped;

  /// No description provided for @chatNotFound.
  ///
  /// In en, this message translates to:
  /// **'Chat not found.'**
  String get chatNotFound;

  /// No description provided for @chatGeneric.
  ///
  /// In en, this message translates to:
  /// **'Message could not be sent. Please try again.'**
  String get chatGeneric;

  /// No description provided for @incomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming video call'**
  String get incomingCall;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @endCall.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endCall;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @cameraOn.
  ///
  /// In en, this message translates to:
  /// **'Turn camera on'**
  String get cameraOn;

  /// No description provided for @cameraOff.
  ///
  /// In en, this message translates to:
  /// **'Turn camera off'**
  String get cameraOff;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @switchCamera.
  ///
  /// In en, this message translates to:
  /// **'Flip camera'**
  String get switchCamera;

  /// No description provided for @userBusy.
  ///
  /// In en, this message translates to:
  /// **'This person is already on another call.'**
  String get userBusy;

  /// No description provided for @callNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Video calling is not available right now.'**
  String get callNotConfigured;

  /// No description provided for @cameraDenied.
  ///
  /// In en, this message translates to:
  /// **'A video call needs camera permission.'**
  String get cameraDenied;

  /// No description provided for @micDenied.
  ///
  /// In en, this message translates to:
  /// **'A call needs microphone permission.'**
  String get micDenied;

  /// No description provided for @connectionUnstable.
  ///
  /// In en, this message translates to:
  /// **'Connection is unstable'**
  String get connectionUnstable;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get reconnecting;

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect the call. Please try again.'**
  String get callFailed;

  /// No description provided for @callEnded.
  ///
  /// In en, this message translates to:
  /// **'Call ended'**
  String get callEnded;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connecting;

  /// No description provided for @calling.
  ///
  /// In en, this message translates to:
  /// **'Calling…'**
  String get calling;

  /// No description provided for @ringing.
  ///
  /// In en, this message translates to:
  /// **'Ringing…'**
  String get ringing;

  /// No description provided for @missedCall.
  ///
  /// In en, this message translates to:
  /// **'Missed video call'**
  String get missedCall;

  /// No description provided for @callPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera and microphone'**
  String get callPermissionTitle;

  /// No description provided for @callPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'Video calls need camera and microphone permission.'**
  String get callPermissionBody;

  /// No description provided for @presenceOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get presenceOnline;

  /// No description provided for @presenceRecentlyActive.
  ///
  /// In en, this message translates to:
  /// **'Active recently'**
  String get presenceRecentlyActive;

  /// No description provided for @presenceOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get presenceOffline;

  /// No description provided for @timeNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get timeNow;

  /// No description provided for @timeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String timeMinutes(int count);

  /// No description provided for @timeHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String timeHours(int count);

  /// No description provided for @timeDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String timeDays(int count);

  /// No description provided for @unmatch.
  ///
  /// In en, this message translates to:
  /// **'Unmatch'**
  String get unmatch;

  /// No description provided for @unmatchConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Unmatch this person?'**
  String get unmatchConfirmTitle;

  /// No description provided for @unmatchConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will not be able to message each other, and the chat will close.'**
  String get unmatchConfirmMessage;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @blockConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Block this person?'**
  String get blockConfirmTitle;

  /// No description provided for @blockConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'They will disappear from discovery, and you will not be able to message or call each other.'**
  String get blockConfirmMessage;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting?'**
  String get reportTitle;

  /// No description provided for @reportDescription.
  ///
  /// In en, this message translates to:
  /// **'Details (optional)'**
  String get reportDescription;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get submitReport;

  /// No description provided for @reportThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks. We received your report.'**
  String get reportThanks;

  /// No description provided for @offerBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Want to block them too?'**
  String get offerBlockTitle;

  /// No description provided for @offerBlockMessage.
  ///
  /// In en, this message translates to:
  /// **'Blocking stops new messages, matches, and calls.'**
  String get offerBlockMessage;

  /// No description provided for @reportSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportSpam;

  /// No description provided for @reportHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get reportHarassment;

  /// No description provided for @reportInappropriate.
  ///
  /// In en, this message translates to:
  /// **'Inappropriate content'**
  String get reportInappropriate;

  /// No description provided for @reportScam.
  ///
  /// In en, this message translates to:
  /// **'Scam'**
  String get reportScam;

  /// No description provided for @reportFakeProfile.
  ///
  /// In en, this message translates to:
  /// **'Fake profile'**
  String get reportFakeProfile;

  /// No description provided for @reportUnderage.
  ///
  /// In en, this message translates to:
  /// **'Underage'**
  String get reportUnderage;

  /// No description provided for @reportOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportOther;

  /// No description provided for @linkedAccounts.
  ///
  /// In en, this message translates to:
  /// **'Linked accounts'**
  String get linkedAccounts;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @linked.
  ///
  /// In en, this message translates to:
  /// **'Linked'**
  String get linked;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your Mevora account, profile, matches, and messages. This cannot be undone.'**
  String get deleteAccountBody;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete forever'**
  String get deleteConfirm;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications and privacy'**
  String get notificationsTitle;

  /// No description provided for @messageNotifications.
  ///
  /// In en, this message translates to:
  /// **'Message notifications'**
  String get messageNotifications;

  /// No description provided for @matchNotifications.
  ///
  /// In en, this message translates to:
  /// **'Match notifications'**
  String get matchNotifications;

  /// No description provided for @callNotifications.
  ///
  /// In en, this message translates to:
  /// **'Call notifications'**
  String get callNotifications;

  /// No description provided for @hideOnlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Hide my online status'**
  String get hideOnlineStatus;

  /// No description provided for @notificationNewMatch.
  ///
  /// In en, this message translates to:
  /// **'You have a new match!'**
  String get notificationNewMatch;

  /// No description provided for @notificationNewMessage.
  ///
  /// In en, this message translates to:
  /// **'You have a new message'**
  String get notificationNewMessage;

  /// No description provided for @notificationSuperLike.
  ///
  /// In en, this message translates to:
  /// **'Someone Super Liked you'**
  String get notificationSuperLike;

  /// No description provided for @boostTitle.
  ///
  /// In en, this message translates to:
  /// **'BOOST'**
  String get boostTitle;

  /// No description provided for @boostSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show your profile to more people and get discovered faster.'**
  String get boostSubtitle;

  /// No description provided for @boostDuration.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get boostDuration;

  /// No description provided for @boostActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate Boost'**
  String get boostActivate;

  /// No description provided for @boostBuy.
  ///
  /// In en, this message translates to:
  /// **'Buy Boost'**
  String get boostBuy;

  /// No description provided for @boostPurchasing.
  ///
  /// In en, this message translates to:
  /// **'Starting purchase...'**
  String get boostPurchasing;

  /// No description provided for @boostVerifying.
  ///
  /// In en, this message translates to:
  /// **'Confirming your purchase...'**
  String get boostVerifying;

  /// No description provided for @boostSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Boost is on! 🚀'**
  String get boostSuccessTitle;

  /// No description provided for @boostSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Your profile will start appearing to more people.'**
  String get boostSuccessMessage;

  /// No description provided for @boostAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'You already have an active Boost.'**
  String get boostAlreadyActive;

  /// No description provided for @boostPurchaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled.'**
  String get boostPurchaseCancelled;

  /// No description provided for @boostPurchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase could not be completed. Please try again.'**
  String get boostPurchaseFailed;

  /// No description provided for @boostStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store is not available on this device right now.'**
  String get boostStoreUnavailable;

  /// No description provided for @boostStoreDown.
  ///
  /// In en, this message translates to:
  /// **'The store is not responding. Try again in a moment.'**
  String get boostStoreDown;

  /// No description provided for @boostNetworkError.
  ///
  /// In en, this message translates to:
  /// **'We could not verify the purchase because of a connection issue.'**
  String get boostNetworkError;

  /// No description provided for @boostVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not verify the purchase. Try again in a moment.'**
  String get boostVerificationFailed;

  /// No description provided for @boostAlreadyProcessed.
  ///
  /// In en, this message translates to:
  /// **'This purchase was already processed.'**
  String get boostAlreadyProcessed;

  /// No description provided for @boostLoadingProduct.
  ///
  /// In en, this message translates to:
  /// **'Loading store details...'**
  String get boostLoadingProduct;

  /// No description provided for @boostBackToDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Back to Discover'**
  String get boostBackToDiscovery;

  /// No description provided for @boostTooltip.
  ///
  /// In en, this message translates to:
  /// **'Boost'**
  String get boostTooltip;

  /// No description provided for @boostRemainingMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String boostRemainingMinutes(int minutes);

  /// No description provided for @radiusKm.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String radiusKm(int km);

  /// No description provided for @paymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentTitle;

  /// No description provided for @paymentProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing payment...'**
  String get paymentProcessing;

  /// No description provided for @paymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment successful.'**
  String get paymentSuccess;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed. Please try again.'**
  String get paymentFailed;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @startupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Mevora could not start. Check your connection and try again.'**
  String get startupUnavailable;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
