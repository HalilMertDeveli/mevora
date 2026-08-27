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

  /// Welcome/login hero slogan. Keep the line break.
  ///
  /// In en, this message translates to:
  /// **'Don\'t just meet people.\nMeet someone compatible.'**
  String get loginSlogan;

  /// No description provided for @continueWithEmail.
  ///
  /// In en, this message translates to:
  /// **'Continue with email'**
  String get continueWithEmail;

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

  /// No description provided for @signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get signingIn;

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
  /// **'Sign in with Phone Number'**
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
  /// **'Sign in with Phone Number'**
  String get phoneTitle;

  /// No description provided for @phoneSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your country code and enter your phone number. We\'ll send a 6-digit verification code by SMS.'**
  String get phoneSubtitle;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'555 000 0000'**
  String get phoneHint;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send verification code'**
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
  /// **'Phone number is invalid.'**
  String get authInvalidPhone;

  /// No description provided for @authSmsFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not send the SMS. Please try again.'**
  String get authSmsFailed;

  /// No description provided for @authAppVerification.
  ///
  /// In en, this message translates to:
  /// **'App verification failed. Check your connection, try on a physical device, then request a new code.'**
  String get authAppVerification;

  /// No description provided for @authInvalidOtp.
  ///
  /// In en, this message translates to:
  /// **'The verification code is incorrect.'**
  String get authInvalidOtp;

  /// No description provided for @authExpiredOtp.
  ///
  /// In en, this message translates to:
  /// **'The verification code expired. Request a new one.'**
  String get authExpiredOtp;

  /// No description provided for @authSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Please enter your number again.'**
  String get authSessionExpired;

  /// No description provided for @authTooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please try again later.'**
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
  /// **'Phone sign-in is not enabled for this Firebase project yet.'**
  String get authNotConfigured;

  /// No description provided for @authBillingNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'Firebase billing (Blaze) is required to send SMS verification codes.'**
  String get authBillingNotEnabled;

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

  /// No description provided for @googleSignInCancelled.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In was cancelled.'**
  String get googleSignInCancelled;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google Sign-In could not be completed.'**
  String get googleSignInFailed;

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

  /// No description provided for @onboardingStepProgress.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepProgress(int current, int total);

  /// No description provided for @onboardingBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onboardingBack;

  /// No description provided for @onboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get onboardingContinue;

  /// No description provided for @onboardingEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get onboardingEducation;

  /// No description provided for @onboardingLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get onboardingLifestyle;

  /// No description provided for @onboardingSmoking.
  ///
  /// In en, this message translates to:
  /// **'Smoking'**
  String get onboardingSmoking;

  /// No description provided for @onboardingDrinking.
  ///
  /// In en, this message translates to:
  /// **'Drinking'**
  String get onboardingDrinking;

  /// No description provided for @onboardingExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get onboardingExercise;

  /// No description provided for @onboardingPets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get onboardingPets;

  /// No description provided for @onboardingInterestsHint.
  ///
  /// In en, this message translates to:
  /// **'Pick at least 3 interests so Mevora can find compatible people.'**
  String get onboardingInterestsHint;

  /// No description provided for @onboardingBioHint.
  ///
  /// In en, this message translates to:
  /// **'Share a little about yourself.'**
  String get onboardingBioHint;

  /// No description provided for @onboardingPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Add at least 3 photos. Drag to reorder — your first photo is your main one.'**
  String get onboardingPhotosHint;

  /// No description provided for @onboardingPrimaryPhoto.
  ///
  /// In en, this message translates to:
  /// **'Main photo'**
  String get onboardingPrimaryPhoto;

  /// No description provided for @onboardingPhotoNumber.
  ///
  /// In en, this message translates to:
  /// **'Photo {number}'**
  String onboardingPhotoNumber(int number);

  /// No description provided for @onboardingCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set'**
  String get onboardingCompleteTitle;

  /// No description provided for @onboardingCompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Your profile is ready. Mevora will start introducing compatible people.'**
  String get onboardingCompleteMessage;

  /// No description provided for @onboardingStartDiscovering.
  ///
  /// In en, this message translates to:
  /// **'Start discovering'**
  String get onboardingStartDiscovering;

  /// No description provided for @onboardingGenderMan.
  ///
  /// In en, this message translates to:
  /// **'Man'**
  String get onboardingGenderMan;

  /// No description provided for @onboardingGenderWoman.
  ///
  /// In en, this message translates to:
  /// **'Woman'**
  String get onboardingGenderWoman;

  /// No description provided for @onboardingGenderNonBinary.
  ///
  /// In en, this message translates to:
  /// **'Non-binary'**
  String get onboardingGenderNonBinary;

  /// No description provided for @onboardingInterestedMen.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get onboardingInterestedMen;

  /// No description provided for @onboardingInterestedWomen.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get onboardingInterestedWomen;

  /// No description provided for @onboardingInterestedEveryone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get onboardingInterestedEveryone;

  /// No description provided for @onboardingEducationHighSchool.
  ///
  /// In en, this message translates to:
  /// **'High school'**
  String get onboardingEducationHighSchool;

  /// No description provided for @onboardingEducationSomeCollege.
  ///
  /// In en, this message translates to:
  /// **'Some college'**
  String get onboardingEducationSomeCollege;

  /// No description provided for @onboardingEducationBachelors.
  ///
  /// In en, this message translates to:
  /// **'Bachelor\'s degree'**
  String get onboardingEducationBachelors;

  /// No description provided for @onboardingEducationMasters.
  ///
  /// In en, this message translates to:
  /// **'Master\'s degree'**
  String get onboardingEducationMasters;

  /// No description provided for @onboardingEducationPhd.
  ///
  /// In en, this message translates to:
  /// **'PhD'**
  String get onboardingEducationPhd;

  /// No description provided for @onboardingEducationPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get onboardingEducationPreferNotToSay;

  /// No description provided for @onboardingRelationshipLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long-term relationship'**
  String get onboardingRelationshipLongTerm;

  /// No description provided for @onboardingRelationshipShortTerm.
  ///
  /// In en, this message translates to:
  /// **'Short-term relationship'**
  String get onboardingRelationshipShortTerm;

  /// No description provided for @onboardingRelationshipFriendship.
  ///
  /// In en, this message translates to:
  /// **'New friends'**
  String get onboardingRelationshipFriendship;

  /// No description provided for @onboardingRelationshipNotSure.
  ///
  /// In en, this message translates to:
  /// **'Still figuring it out'**
  String get onboardingRelationshipNotSure;

  /// No description provided for @onboardingRelationshipPreferNotToSay.
  ///
  /// In en, this message translates to:
  /// **'Prefer not to say'**
  String get onboardingRelationshipPreferNotToSay;

  /// No description provided for @onboardingLifestyleNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get onboardingLifestyleNever;

  /// No description provided for @onboardingLifestyleSometimes.
  ///
  /// In en, this message translates to:
  /// **'Sometimes'**
  String get onboardingLifestyleSometimes;

  /// No description provided for @onboardingLifestyleRegularly.
  ///
  /// In en, this message translates to:
  /// **'Regularly'**
  String get onboardingLifestyleRegularly;

  /// No description provided for @onboardingLifestyleDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get onboardingLifestyleDaily;

  /// No description provided for @onboardingLifestyleNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get onboardingLifestyleNone;

  /// No description provided for @onboardingLifestyleCat.
  ///
  /// In en, this message translates to:
  /// **'Cat'**
  String get onboardingLifestyleCat;

  /// No description provided for @onboardingLifestyleDog.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get onboardingLifestyleDog;

  /// No description provided for @onboardingLifestyleBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get onboardingLifestyleBoth;

  /// No description provided for @onboardingLifestyleOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get onboardingLifestyleOther;

  /// No description provided for @onboardingAlcoholNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get onboardingAlcoholNone;

  /// No description provided for @onboardingAlcoholRarely.
  ///
  /// In en, this message translates to:
  /// **'Rarely'**
  String get onboardingAlcoholRarely;

  /// No description provided for @onboardingAlcoholSocial.
  ///
  /// In en, this message translates to:
  /// **'Socially'**
  String get onboardingAlcoholSocial;

  /// No description provided for @onboardingAlcoholSpecialOccasion.
  ///
  /// In en, this message translates to:
  /// **'Special occasions'**
  String get onboardingAlcoholSpecialOccasion;

  /// No description provided for @onboardingAlcoholFrequently.
  ///
  /// In en, this message translates to:
  /// **'Frequently'**
  String get onboardingAlcoholFrequently;

  /// No description provided for @interestMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get interestMusic;

  /// No description provided for @interestTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get interestTravel;

  /// No description provided for @interestFitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get interestFitness;

  /// No description provided for @interestFood.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get interestFood;

  /// No description provided for @interestArt.
  ///
  /// In en, this message translates to:
  /// **'Art'**
  String get interestArt;

  /// No description provided for @interestMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get interestMovies;

  /// No description provided for @interestBooks.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get interestBooks;

  /// No description provided for @interestGaming.
  ///
  /// In en, this message translates to:
  /// **'Gaming'**
  String get interestGaming;

  /// No description provided for @interestNature.
  ///
  /// In en, this message translates to:
  /// **'Nature'**
  String get interestNature;

  /// No description provided for @interestPhotography.
  ///
  /// In en, this message translates to:
  /// **'Photography'**
  String get interestPhotography;

  /// No description provided for @interestCoffee.
  ///
  /// In en, this message translates to:
  /// **'Coffee'**
  String get interestCoffee;

  /// No description provided for @interestDancing.
  ///
  /// In en, this message translates to:
  /// **'Dancing'**
  String get interestDancing;

  /// No description provided for @interestYoga.
  ///
  /// In en, this message translates to:
  /// **'Yoga'**
  String get interestYoga;

  /// No description provided for @interestTech.
  ///
  /// In en, this message translates to:
  /// **'Tech'**
  String get interestTech;

  /// No description provided for @interestFashion.
  ///
  /// In en, this message translates to:
  /// **'Fashion'**
  String get interestFashion;

  /// No description provided for @interestPets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get interestPets;

  /// No description provided for @interestSports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get interestSports;

  /// No description provided for @interestCooking.
  ///
  /// In en, this message translates to:
  /// **'Cooking'**
  String get interestCooking;

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

  /// No description provided for @discoverySeenEveryoneTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve seen everyone for now'**
  String get discoverySeenEveryoneTitle;

  /// No description provided for @discoverySeenEveryoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Check back later for new people, or restart the demo to explore again.'**
  String get discoverySeenEveryoneMessage;

  /// No description provided for @exploreAgain.
  ///
  /// In en, this message translates to:
  /// **'Explore again'**
  String get exploreAgain;

  /// No description provided for @restartDemo.
  ///
  /// In en, this message translates to:
  /// **'Restart demo'**
  String get restartDemo;

  /// No description provided for @discoveryFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery filters'**
  String get discoveryFiltersTitle;

  /// No description provided for @discoveryFiltersHint.
  ///
  /// In en, this message translates to:
  /// **'Filters are saved locally. Server-side filtering arrives in a later update.'**
  String get discoveryFiltersHint;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get applyFilters;

  /// No description provided for @filterAge.
  ///
  /// In en, this message translates to:
  /// **'Age range'**
  String get filterAge;

  /// No description provided for @filterDistance.
  ///
  /// In en, this message translates to:
  /// **'Maximum distance'**
  String get filterDistance;

  /// No description provided for @filterGender.
  ///
  /// In en, this message translates to:
  /// **'Show me'**
  String get filterGender;

  /// No description provided for @filterRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'Relationship goal'**
  String get filterRelationshipGoal;

  /// No description provided for @genderWoman.
  ///
  /// In en, this message translates to:
  /// **'Women'**
  String get genderWoman;

  /// No description provided for @genderMan.
  ///
  /// In en, this message translates to:
  /// **'Men'**
  String get genderMan;

  /// No description provided for @genderNonBinary.
  ///
  /// In en, this message translates to:
  /// **'Non-binary'**
  String get genderNonBinary;

  /// No description provided for @relationshipGoalLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long-term'**
  String get relationshipGoalLongTerm;

  /// No description provided for @relationshipGoalCasual.
  ///
  /// In en, this message translates to:
  /// **'Casual'**
  String get relationshipGoalCasual;

  /// No description provided for @relationshipGoalFiguringOut.
  ///
  /// In en, this message translates to:
  /// **'Still figuring it out'**
  String get relationshipGoalFiguringOut;

  /// No description provided for @compatibilityReasonsHeading.
  ///
  /// In en, this message translates to:
  /// **'Why you might connect'**
  String get compatibilityReasonsHeading;

  /// No description provided for @whyYoureSeeingThis.
  ///
  /// In en, this message translates to:
  /// **'Why this profile is shown'**
  String get whyYoureSeeingThis;

  /// No description provided for @sharedInterests.
  ///
  /// In en, this message translates to:
  /// **'Shared interests'**
  String get sharedInterests;

  /// No description provided for @profileDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileDetailsTitle;

  /// No description provided for @photoCounter.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String photoCounter(int current, int total);

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
  /// **'Suggested · {percent}% compatible'**
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

  /// No description provided for @youLikedEachOther.
  ///
  /// In en, this message translates to:
  /// **'You liked each other!'**
  String get youLikedEachOther;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

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

  /// No description provided for @chatEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get chatEmptyTitle;

  /// No description provided for @chatEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Send the first message.'**
  String get chatEmptyMessage;

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

  /// No description provided for @attachPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get attachPhoto;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get takePhoto;

  /// No description provided for @recordVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice message'**
  String get recordVoice;

  /// No description provided for @holdToRecord.
  ///
  /// In en, this message translates to:
  /// **'Recording…'**
  String get holdToRecord;

  /// No description provided for @slideToCancelVoice.
  ///
  /// In en, this message translates to:
  /// **'Slide left to cancel'**
  String get slideToCancelVoice;

  /// No description provided for @releaseToSendVoice.
  ///
  /// In en, this message translates to:
  /// **'Release to send'**
  String get releaseToSendVoice;

  /// No description provided for @holdAgainToRecord.
  ///
  /// In en, this message translates to:
  /// **'Microphone ready — hold to record'**
  String get holdAgainToRecord;

  /// No description provided for @voiceTooShort.
  ///
  /// In en, this message translates to:
  /// **'Hold a bit longer to send a voice message.'**
  String get voiceTooShort;

  /// No description provided for @playVoice.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playVoice;

  /// No description provided for @pauseVoice.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseVoice;

  /// No description provided for @previewPhoto.
  ///
  /// In en, this message translates to:
  /// **'Send this photo?'**
  String get previewPhoto;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get messageDeleted;

  /// No description provided for @messageDecryptFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not decrypt this message.'**
  String get messageDecryptFailed;

  /// No description provided for @chatE2eeTitle.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get chatE2eeTitle;

  /// No description provided for @chatE2eeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only you and this person can read your messages.'**
  String get chatE2eeSubtitle;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteMessage;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this message? The other person will no longer see it.'**
  String get deleteMessageConfirm;

  /// No description provided for @micDeniedChat.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is needed to send a voice message.'**
  String get micDeniedChat;

  /// No description provided for @photoDeniedChat.
  ///
  /// In en, this message translates to:
  /// **'Photo permission is needed to send an image.'**
  String get photoDeniedChat;

  /// No description provided for @callCancelled.
  ///
  /// In en, this message translates to:
  /// **'Call cancelled'**
  String get callCancelled;

  /// No description provided for @callRejected.
  ///
  /// In en, this message translates to:
  /// **'Call declined'**
  String get callRejected;

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

  /// No description provided for @chatEncryptionNotReady.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encryption is not ready yet. Try again once your match has published their key.'**
  String get chatEncryptionNotReady;

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

  /// No description provided for @presenceTyping.
  ///
  /// In en, this message translates to:
  /// **'typing...'**
  String get presenceTyping;

  /// No description provided for @lastSeenToday.
  ///
  /// In en, this message translates to:
  /// **'Last seen today at {time}'**
  String lastSeenToday(String time);

  /// No description provided for @lastSeenYesterday.
  ///
  /// In en, this message translates to:
  /// **'Last seen yesterday at {time}'**
  String lastSeenYesterday(String time);

  /// No description provided for @lastSeenOnDate.
  ///
  /// In en, this message translates to:
  /// **'Last seen {date} at {time}'**
  String lastSeenOnDate(String date, String time);

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

  /// No description provided for @hideProfile.
  ///
  /// In en, this message translates to:
  /// **'Hide profile'**
  String get hideProfile;

  /// No description provided for @hideProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Hide this profile?'**
  String get hideProfileTitle;

  /// No description provided for @hideProfileMessage.
  ///
  /// In en, this message translates to:
  /// **'They will not appear in your discovery stack again.'**
  String get hideProfileMessage;

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

  /// No description provided for @linkEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Link email and password'**
  String get linkEmailTitle;

  /// No description provided for @linkEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This adds email sign-in to your current account. It does not merge another Mevora account.'**
  String get linkEmailSubtitle;

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

  /// No description provided for @exportMyData.
  ///
  /// In en, this message translates to:
  /// **'Download my data'**
  String get exportMyData;

  /// No description provided for @exportMyDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Export your data?'**
  String get exportMyDataTitle;

  /// No description provided for @exportMyDataBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora prepares a JSON file with your account, profile, preferences, matches, likes, blocks, reports you filed, and purchases. Exact location, message contents, and secrets are excluded.'**
  String get exportMyDataBody;

  /// No description provided for @exportMyDataSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export saved to: {path}'**
  String exportMyDataSuccess(String path);

  /// No description provided for @exportMyDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not export your data. Try again later.'**
  String get exportMyDataFailed;

  /// No description provided for @settingsShowAge.
  ///
  /// In en, this message translates to:
  /// **'Show age on profile'**
  String get settingsShowAge;

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
  /// **'Boost your profile'**
  String get boostDuration;

  /// No description provided for @boostActivate.
  ///
  /// In en, this message translates to:
  /// **'Use leftover Boost'**
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
  /// **'You already have an active Boost. Buying another pack adds time to the remaining period.'**
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
  /// **'{minutes} min left'**
  String boostRemainingMinutes(int minutes);

  /// No description provided for @boostRemainingDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days left'**
  String boostRemainingDays(int days);

  /// No description provided for @boostRemainingHours.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours left'**
  String boostRemainingHours(int hours);

  /// No description provided for @boostSpotlight.
  ///
  /// In en, this message translates to:
  /// **'Boost Profile'**
  String get boostSpotlight;

  /// No description provided for @boostPackOne.
  ///
  /// In en, this message translates to:
  /// **'1 Boost'**
  String get boostPackOne;

  /// No description provided for @boostPackFive.
  ///
  /// In en, this message translates to:
  /// **'5 Boost'**
  String get boostPackFive;

  /// No description provided for @boostPackTen.
  ///
  /// In en, this message translates to:
  /// **'10 Boost'**
  String get boostPackTen;

  /// No description provided for @boostPackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Boost'**
  String boostPackCount(int count);

  /// No description provided for @boostPackWeek.
  ///
  /// In en, this message translates to:
  /// **'1 Week'**
  String get boostPackWeek;

  /// No description provided for @boostPackMonth.
  ///
  /// In en, this message translates to:
  /// **'1 Month'**
  String get boostPackMonth;

  /// No description provided for @boostPackYear.
  ///
  /// In en, this message translates to:
  /// **'1 Year'**
  String get boostPackYear;

  /// No description provided for @boostPackWeekSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Boost your profile for 7 days'**
  String get boostPackWeekSubtitle;

  /// No description provided for @boostPackMonthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Boost your profile for 30 days'**
  String get boostPackMonthSubtitle;

  /// No description provided for @boostPackYearSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Boost your profile for 365 days'**
  String get boostPackYearSubtitle;

  /// No description provided for @boostBestValue.
  ///
  /// In en, this message translates to:
  /// **'Best value'**
  String get boostBestValue;

  /// No description provided for @boostBalance.
  ///
  /// In en, this message translates to:
  /// **'{count} leftover Boost'**
  String boostBalance(int count);

  /// No description provided for @boostBuyPack.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get boostBuyPack;

  /// No description provided for @boostCreditedTitle.
  ///
  /// In en, this message translates to:
  /// **'Boosts added to your account'**
  String get boostCreditedTitle;

  /// No description provided for @boostCreditedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} Boost added. Activate when you are ready.'**
  String boostCreditedMessage(int count);

  /// No description provided for @boostInsufficientBalance.
  ///
  /// In en, this message translates to:
  /// **'You need a Boost before you can go live.'**
  String get boostInsufficientBalance;

  /// No description provided for @boostHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase history'**
  String get boostHistoryTitle;

  /// No description provided for @boostHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No purchases yet.'**
  String get boostHistoryEmpty;

  /// No description provided for @boostHistoryPurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get boostHistoryPurchase;

  /// No description provided for @boostHistoryActivation.
  ///
  /// In en, this message translates to:
  /// **'Activation'**
  String get boostHistoryActivation;

  /// No description provided for @boostHistoryPlatformIos.
  ///
  /// In en, this message translates to:
  /// **'App Store'**
  String get boostHistoryPlatformIos;

  /// No description provided for @boostHistoryPlatformAndroid.
  ///
  /// In en, this message translates to:
  /// **'Google Play'**
  String get boostHistoryPlatformAndroid;

  /// No description provided for @boostActiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Boost on'**
  String get boostActiveBadge;

  /// No description provided for @boostDiscoverBadge.
  ///
  /// In en, this message translates to:
  /// **'BOOST'**
  String get boostDiscoverBadge;

  /// No description provided for @boostActivating.
  ///
  /// In en, this message translates to:
  /// **'Turning Boost on...'**
  String get boostActivating;

  /// No description provided for @boostNoBalance.
  ///
  /// In en, this message translates to:
  /// **'Choose a pack to Boost your profile.'**
  String get boostNoBalance;

  /// No description provided for @boostPriceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Price unavailable'**
  String get boostPriceUnavailable;

  /// No description provided for @boostRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring purchases...'**
  String get boostRestoring;

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

  /// No description provided for @permissionCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get permissionCameraTitle;

  /// No description provided for @permissionCameraDescription.
  ///
  /// In en, this message translates to:
  /// **'Mevora uses your camera to take profile photos.'**
  String get permissionCameraDescription;

  /// No description provided for @permissionMicrophoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Microphone'**
  String get permissionMicrophoneTitle;

  /// No description provided for @permissionMicrophoneDescription.
  ///
  /// In en, this message translates to:
  /// **'Mevora uses your microphone for voice and audio features.'**
  String get permissionMicrophoneDescription;

  /// No description provided for @permissionPhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get permissionPhotosTitle;

  /// No description provided for @permissionPhotosDescription.
  ///
  /// In en, this message translates to:
  /// **'Mevora needs access to your photos so you can add profile pictures.'**
  String get permissionPhotosDescription;

  /// No description provided for @permissionLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get permissionLocationTitle;

  /// No description provided for @permissionLocationDescription.
  ///
  /// In en, this message translates to:
  /// **'Mevora uses your location to improve distance and nearby discovery.'**
  String get permissionLocationDescription;

  /// No description provided for @permissionNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get permissionNotificationsTitle;

  /// No description provided for @permissionNotificationsDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifications help you know when you receive a match or message.'**
  String get permissionNotificationsDescription;

  /// No description provided for @permissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get permissionAllow;

  /// No description provided for @permissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission needed'**
  String get permissionDeniedTitle;

  /// No description provided for @permissionDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'This feature works better with permission. You can try again, or continue without it.'**
  String get permissionDeniedBody;

  /// No description provided for @permissionPermanentlyDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Permission is turned off. You can enable it in device settings.'**
  String get permissionPermanentlyDeniedBody;

  /// No description provided for @permissionContinueWithout.
  ///
  /// In en, this message translates to:
  /// **'Continue without permission'**
  String get permissionContinueWithout;

  /// No description provided for @permissionStatusGranted.
  ///
  /// In en, this message translates to:
  /// **'Allowed'**
  String get permissionStatusGranted;

  /// No description provided for @permissionStatusDenied.
  ///
  /// In en, this message translates to:
  /// **'Not allowed'**
  String get permissionStatusDenied;

  /// No description provided for @permissionStatusRestricted.
  ///
  /// In en, this message translates to:
  /// **'Restricted'**
  String get permissionStatusRestricted;

  /// No description provided for @permissionStatusLimited.
  ///
  /// In en, this message translates to:
  /// **'Limited access'**
  String get permissionStatusLimited;

  /// No description provided for @permissionStatusPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Off — open device settings'**
  String get permissionStatusPermanentlyDenied;

  /// No description provided for @permissionStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get permissionStatusUnknown;

  /// No description provided for @privacyPermissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Permissions'**
  String get privacyPermissionsTitle;

  /// No description provided for @privacyPermissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mevora asks for each permission only when a feature needs it. You can use the app without granting optional access.'**
  String get privacyPermissionsSubtitle;

  /// No description provided for @privacyOpenDeviceSettings.
  ///
  /// In en, this message translates to:
  /// **'Open device settings'**
  String get privacyOpenDeviceSettings;

  /// No description provided for @selectCityInstead.
  ///
  /// In en, this message translates to:
  /// **'Choose a city instead'**
  String get selectCityInstead;

  /// No description provided for @addPhotoCamera.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get addPhotoCamera;

  /// No description provided for @addPhotoGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get addPhotoGallery;

  /// No description provided for @photoEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add your first photo to continue.'**
  String get photoEmptyHint;

  /// No description provided for @photoMinRequired.
  ///
  /// In en, this message translates to:
  /// **'You must add at least 3 photos.'**
  String get photoMinRequired;

  /// No description provided for @photoUploadingPercent.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo... {percent}%'**
  String photoUploadingPercent(int percent);

  /// No description provided for @photoUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Photo could not be uploaded. Please try again.'**
  String get photoUploadFailed;

  /// No description provided for @photoUploaded.
  ///
  /// In en, this message translates to:
  /// **'Photo uploaded'**
  String get photoUploaded;

  /// No description provided for @photoSelected.
  ///
  /// In en, this message translates to:
  /// **'Photo selected'**
  String get photoSelected;

  /// No description provided for @photoRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get photoRetry;

  /// No description provided for @enableDeviceNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get enableDeviceNotifications;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// No description provided for @settingsEmailUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No email on file'**
  String get settingsEmailUnavailable;

  /// No description provided for @settingsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get settingsReadOnly;

  /// No description provided for @settingsPrivacySafety.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Safety'**
  String get settingsPrivacySafety;

  /// No description provided for @settingsPrivacyControls.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsPrivacyControls;

  /// No description provided for @settingsLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get settingsLocation;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsLogoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get settingsLogoutTitle;

  /// No description provided for @settingsLogoutBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to use Mevora.'**
  String get settingsLogoutBody;

  /// No description provided for @settingsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'This is permanent'**
  String get settingsDeleteConfirmTitle;

  /// No description provided for @settingsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All matches, messages, and profile data will be deleted forever.'**
  String get settingsDeleteConfirmBody;

  /// No description provided for @settingsReauthTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm your identity'**
  String get settingsReauthTitle;

  /// No description provided for @settingsCurrentPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your current password.'**
  String get settingsCurrentPasswordRequired;

  /// No description provided for @settingsNewPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a new password.'**
  String get settingsNewPasswordRequired;

  /// No description provided for @settingsConfirmPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Confirm your new password.'**
  String get settingsConfirmPasswordRequired;

  /// No description provided for @settingsPasswordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match.'**
  String get settingsPasswordsDoNotMatch;

  /// No description provided for @settingsPhotoMinRequired.
  ///
  /// In en, this message translates to:
  /// **'Keep at least 3 profile photos.'**
  String get settingsPhotoMinRequired;

  /// No description provided for @settingsPhotoMaxExceeded.
  ///
  /// In en, this message translates to:
  /// **'You can add up to 6 photos.'**
  String get settingsPhotoMaxExceeded;

  /// No description provided for @settingsPhotoPrimaryDeleteBlocked.
  ///
  /// In en, this message translates to:
  /// **'Set another photo as primary before deleting this one.'**
  String get settingsPhotoPrimaryDeleteBlocked;

  /// No description provided for @settingsPhotoPrimaryRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a primary photo.'**
  String get settingsPhotoPrimaryRequired;

  /// No description provided for @settingsFirstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required.'**
  String get settingsFirstNameRequired;

  /// No description provided for @settingsFirstNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'First name is too long.'**
  String get settingsFirstNameTooLong;

  /// No description provided for @settingsBioTooLong.
  ///
  /// In en, this message translates to:
  /// **'Bio is too long.'**
  String get settingsBioTooLong;

  /// No description provided for @settingsInterestsTooMany.
  ///
  /// In en, this message translates to:
  /// **'Choose fewer interests.'**
  String get settingsInterestsTooMany;

  /// No description provided for @settingsMinAgeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Minimum age must be at least 18.'**
  String get settingsMinAgeInvalid;

  /// No description provided for @settingsMaxAgeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Maximum age is too high.'**
  String get settingsMaxAgeInvalid;

  /// No description provided for @settingsAgeRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Maximum age must be greater than minimum age.'**
  String get settingsAgeRangeInvalid;

  /// No description provided for @settingsDistanceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Distance must be between 1 and 500 km.'**
  String get settingsDistanceInvalid;

  /// No description provided for @settingsGooglePasswordMessage.
  ///
  /// In en, this message translates to:
  /// **'Your account uses Google Sign-In. Password changes are managed by Google.'**
  String get settingsGooglePasswordMessage;

  /// No description provided for @settingsBirthDateLocked.
  ///
  /// In en, this message translates to:
  /// **'Birthday cannot be changed after onboarding. Age is calculated from your birthday.'**
  String get settingsBirthDateLocked;

  /// No description provided for @settingsSaveProfile.
  ///
  /// In en, this message translates to:
  /// **'Save profile'**
  String get settingsSaveProfile;

  /// No description provided for @settingsUnblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get settingsUnblock;

  /// No description provided for @settingsBlockedEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No blocked users'**
  String get settingsBlockedEmptyTitle;

  /// No description provided for @settingsBlockedEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'People you block will appear here.'**
  String get settingsBlockedEmptyMessage;

  /// No description provided for @settingsShowOnlineStatus.
  ///
  /// In en, this message translates to:
  /// **'Show online status'**
  String get settingsShowOnlineStatus;

  /// No description provided for @settingsShowLastSeen.
  ///
  /// In en, this message translates to:
  /// **'Show last seen'**
  String get settingsShowLastSeen;

  /// No description provided for @settingsShowTypingStatus.
  ///
  /// In en, this message translates to:
  /// **'Show typing status'**
  String get settingsShowTypingStatus;

  /// No description provided for @settingsShowDistance.
  ///
  /// In en, this message translates to:
  /// **'Show distance'**
  String get settingsShowDistance;

  /// No description provided for @settingsShowActivity.
  ///
  /// In en, this message translates to:
  /// **'Show activity status'**
  String get settingsShowActivity;

  /// No description provided for @settingsPushNotifications.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get settingsPushNotifications;

  /// No description provided for @settingsSuperLikeNotifications.
  ///
  /// In en, this message translates to:
  /// **'Super Like notifications'**
  String get settingsSuperLikeNotifications;

  /// No description provided for @settingsSetPrimaryPhoto.
  ///
  /// In en, this message translates to:
  /// **'Set as primary'**
  String get settingsSetPrimaryPhoto;

  /// No description provided for @settingsDeletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get settingsDeletePhoto;

  /// No description provided for @settingsAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get settingsAddPhoto;

  /// No description provided for @settingsEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get settingsEducation;

  /// No description provided for @settingsLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get settingsLifestyle;

  /// No description provided for @settingsInterestedIn.
  ///
  /// In en, this message translates to:
  /// **'Interested in'**
  String get settingsInterestedIn;

  /// No description provided for @settingsRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'Relationship goal'**
  String get settingsRelationshipGoal;

  /// No description provided for @settingsCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get settingsCity;

  /// No description provided for @settingsGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get settingsGender;

  /// No description provided for @settingsNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get settingsNewPassword;

  /// No description provided for @settingsCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get settingsCurrentPassword;

  /// No description provided for @settingsConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get settingsConfirmPassword;

  /// No description provided for @settingsPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password updated.'**
  String get settingsPasswordChanged;

  /// No description provided for @settingsProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved.'**
  String get settingsProfileSaved;

  /// No description provided for @citySelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Select City'**
  String get citySelectTitle;

  /// No description provided for @citySelectSearch.
  ///
  /// In en, this message translates to:
  /// **'Search province…'**
  String get citySelectSearch;

  /// No description provided for @citySelectNone.
  ///
  /// In en, this message translates to:
  /// **'No province found'**
  String get citySelectNone;

  /// No description provided for @discoveryLoading.
  ///
  /// In en, this message translates to:
  /// **'Discovering people for you...'**
  String get discoveryLoading;

  /// No description provided for @discoveryLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load profiles'**
  String get discoveryLoadErrorTitle;

  /// No description provided for @discoveryLoadErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading profiles.'**
  String get discoveryLoadErrorMessage;

  /// No description provided for @discoveryChangePreferences.
  ///
  /// In en, this message translates to:
  /// **'Change discovery preferences'**
  String get discoveryChangePreferences;

  /// No description provided for @itsAMatchHeadline.
  ///
  /// In en, this message translates to:
  /// **'IT\'S A MATCH'**
  String get itsAMatchHeadline;

  /// No description provided for @demoProfileBadge.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get demoProfileBadge;

  /// No description provided for @sharedHobbiesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} shared interests'**
  String sharedHobbiesCount(int count);

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @tabMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get tabMusic;

  /// No description provided for @musicTitle.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get musicTitle;

  /// No description provided for @musicConnectCta.
  ///
  /// In en, this message translates to:
  /// **'🎵 Connect Spotify'**
  String get musicConnectCta;

  /// No description provided for @musicConnected.
  ///
  /// In en, this message translates to:
  /// **'✓ Spotify connected'**
  String get musicConnected;

  /// No description provided for @musicUnconnectedCopy.
  ///
  /// In en, this message translates to:
  /// **'Connect your Spotify account and discover people who fit your music taste.'**
  String get musicUnconnectedCopy;

  /// No description provided for @musicConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting Spotify…'**
  String get musicConnecting;

  /// No description provided for @musicSyncing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing your music taste…'**
  String get musicSyncing;

  /// No description provided for @musicRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh music data'**
  String get musicRefresh;

  /// No description provided for @musicRefreshCooldown.
  ///
  /// In en, this message translates to:
  /// **'You can refresh again later.'**
  String get musicRefreshCooldown;

  /// No description provided for @musicProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Your music profile'**
  String get musicProfileTitle;

  /// No description provided for @musicSameTasteTitle.
  ///
  /// In en, this message translates to:
  /// **'People who listen to the same music'**
  String get musicSameTasteTitle;

  /// No description provided for @musicSameTasteEmpty.
  ///
  /// In en, this message translates to:
  /// **'No overlapping tastes yet. Refresh after you listen a bit more.'**
  String get musicSameTasteEmpty;

  /// No description provided for @musicWeeklyTitle.
  ///
  /// In en, this message translates to:
  /// **'This week\'s music'**
  String get musicWeeklyTitle;

  /// No description provided for @musicWeeklyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Weekly highlights will appear here once enough people connect Spotify.'**
  String get musicWeeklyEmpty;

  /// No description provided for @musicCompatibilityPercent.
  ///
  /// In en, this message translates to:
  /// **'Similar music taste · up to {percent}%'**
  String musicCompatibilityPercent(int percent);

  /// No description provided for @musicCompatibilityShort.
  ///
  /// In en, this message translates to:
  /// **'Music · {percent}%'**
  String musicCompatibilityShort(int percent);

  /// No description provided for @musicSharedCounts.
  ///
  /// In en, this message translates to:
  /// **'{tracks} shared tracks · {artists} shared artists'**
  String musicSharedCounts(int tracks, int artists);

  /// No description provided for @musicOauthCancelled.
  ///
  /// In en, this message translates to:
  /// **'Spotify connection was cancelled.'**
  String get musicOauthCancelled;

  /// No description provided for @musicApiDenied.
  ///
  /// In en, this message translates to:
  /// **'Spotify didn\'t allow access. You can try again later.'**
  String get musicApiDenied;

  /// No description provided for @musicTokenExpired.
  ///
  /// In en, this message translates to:
  /// **'Your Spotify connection expired. Please reconnect.'**
  String get musicTokenExpired;

  /// No description provided for @musicNetwork.
  ///
  /// In en, this message translates to:
  /// **'Check your internet connection and try again.'**
  String get musicNetwork;

  /// No description provided for @musicNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Spotify isn\'t configured in this build yet.'**
  String get musicNotConfigured;

  /// No description provided for @musicConnectError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect Spotify. The rest of Mevora still works.'**
  String get musicConnectError;

  /// No description provided for @settingsConnectSpotify.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify'**
  String get settingsConnectSpotify;

  /// No description provided for @settingsSpotifySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Music taste matching — no playback in Mevora.'**
  String get settingsSpotifySubtitle;

  /// No description provided for @matchScoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Match points'**
  String get matchScoreTitle;

  /// No description provided for @matchScoreSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your connection reputation'**
  String get matchScoreSubtitle;

  /// No description provided for @matchScoreValue.
  ///
  /// In en, this message translates to:
  /// **'{score} points'**
  String matchScoreValue(int score);

  /// No description provided for @matchScoreHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Point history'**
  String get matchScoreHistoryTitle;

  /// No description provided for @matchScoreHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'New matches and conversations will add points here.'**
  String get matchScoreHistoryEmpty;

  /// No description provided for @matchScoreHistoryMatch.
  ///
  /// In en, this message translates to:
  /// **'New match +1'**
  String get matchScoreHistoryMatch;

  /// No description provided for @matchScoreHistoryInteraction.
  ///
  /// In en, this message translates to:
  /// **'Conversation +1'**
  String get matchScoreHistoryInteraction;

  /// No description provided for @matchFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'How did this match go?'**
  String get matchFeedbackTitle;

  /// No description provided for @matchFeedbackMessage.
  ///
  /// In en, this message translates to:
  /// **'Optional. This note stays in your history — they will not see it, and it does not change anyone\'s points.'**
  String get matchFeedbackMessage;

  /// No description provided for @matchFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'A short private note'**
  String get matchFeedbackHint;

  /// No description provided for @matchFeedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save note'**
  String get matchFeedbackSubmit;

  /// No description provided for @matchFeedbackThanks.
  ///
  /// In en, this message translates to:
  /// **'Saved to your history.'**
  String get matchFeedbackThanks;

  /// No description provided for @matchFeedbackTooShort.
  ///
  /// In en, this message translates to:
  /// **'Write a short note, or skip.'**
  String get matchFeedbackTooShort;

  /// No description provided for @matchFeedbackFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that note. Try again.'**
  String get matchFeedbackFailed;

  /// No description provided for @relationshipPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'What do you think about relationships?'**
  String get relationshipPromptTitle;

  /// No description provided for @relationshipQuestionsPreparing.
  ///
  /// In en, this message translates to:
  /// **'New questions are being prepared. Please try again in a bit.'**
  String get relationshipQuestionsPreparing;

  /// No description provided for @relationshipTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Matching Game'**
  String get relationshipTestTitle;

  /// No description provided for @relationshipTestHeadline.
  ///
  /// In en, this message translates to:
  /// **'This hour\'s Matching Game'**
  String get relationshipTestHeadline;

  /// No description provided for @relationshipTestMessage.
  ///
  /// In en, this message translates to:
  /// **'Take this round\'s personality test — same answers, stronger match.'**
  String get relationshipTestMessage;

  /// No description provided for @relationshipTestStart.
  ///
  /// In en, this message translates to:
  /// **'Join the Matching Game'**
  String get relationshipTestStart;

  /// No description provided for @relationshipTestLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get relationshipTestLater;

  /// No description provided for @matchingGameCountdown.
  ///
  /// In en, this message translates to:
  /// **'Next Match Game: {countdown}'**
  String matchingGameCountdown(String countdown);

  /// No description provided for @matchingGameRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'{hour}:00 Matching Game'**
  String matchingGameRoundLabel(String hour);

  /// No description provided for @relationshipContinueTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep matching?'**
  String get relationshipContinueTitle;

  /// No description provided for @relationshipContinueMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve completed 5 matching rounds. Do you want to continue finding people who share your answers?'**
  String get relationshipContinueMessage;

  /// No description provided for @relationshipContinueYes.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get relationshipContinueYes;

  /// No description provided for @relationshipContinueNo.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get relationshipContinueNo;

  /// No description provided for @likesYouTitle.
  ///
  /// In en, this message translates to:
  /// **'Likes you'**
  String get likesYouTitle;

  /// No description provided for @likesYouEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'See who liked your profile'**
  String get likesYouEntrySubtitle;

  /// No description provided for @likesYouLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Someone likes you'**
  String get likesYouLockedTitle;

  /// No description provided for @likesYouLockedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} people like you'**
  String likesYouLockedCount(int count);

  /// No description provided for @likesYouLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium to see who liked you. Photos and names stay hidden until then.'**
  String get likesYouLockedMessage;

  /// No description provided for @likesYouUnlockCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Premium'**
  String get likesYouUnlockCta;

  /// No description provided for @likesYouBlurredHint.
  ///
  /// In en, this message translates to:
  /// **'People who liked you'**
  String get likesYouBlurredHint;

  /// No description provided for @likesYouHiddenName.
  ///
  /// In en, this message translates to:
  /// **'Someone special'**
  String get likesYouHiddenName;

  /// No description provided for @likesYouHiddenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock to see their profile'**
  String get likesYouHiddenSubtitle;

  /// No description provided for @likesYouEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No new likes yet'**
  String get likesYouEmptyTitle;

  /// No description provided for @likesYouEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When someone likes you, they\'ll show up here.'**
  String get likesYouEmptyMessage;

  /// No description provided for @likesYouLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load likes. Please try again.'**
  String get likesYouLoadError;

  /// No description provided for @relationshipTestDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Your relationship test is complete'**
  String get relationshipTestDoneTitle;

  /// No description provided for @relationshipTestFound.
  ///
  /// In en, this message translates to:
  /// **'We found someone whose views match yours.'**
  String get relationshipTestFound;

  /// No description provided for @relationshipTestAlign.
  ///
  /// In en, this message translates to:
  /// **'Your answers overlap on several topics.'**
  String get relationshipTestAlign;

  /// No description provided for @relationshipTestNearest.
  ///
  /// In en, this message translates to:
  /// **'Closest to you:'**
  String get relationshipTestNearest;

  /// No description provided for @relationshipTestEmpty.
  ///
  /// In en, this message translates to:
  /// **'There\'s no one nearby who thinks like you right now.'**
  String get relationshipTestEmpty;

  /// No description provided for @relationshipTestViewProfile.
  ///
  /// In en, this message translates to:
  /// **'View profile'**
  String get relationshipTestViewProfile;

  /// No description provided for @relationshipTestOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get relationshipTestOpenChat;

  /// No description provided for @relationshipMatchBadge.
  ///
  /// In en, this message translates to:
  /// **'Matching Game'**
  String get relationshipMatchBadge;

  /// No description provided for @relationshipPromptProgress.
  ///
  /// In en, this message translates to:
  /// **'{answered} / {total}'**
  String relationshipPromptProgress(int answered, int total);

  /// No description provided for @relationshipCompatibilityPercent.
  ///
  /// In en, this message translates to:
  /// **'Views overlap · {percent}%'**
  String relationshipCompatibilityPercent(int percent);

  /// No description provided for @relationshipCompatibilityShort.
  ///
  /// In en, this message translates to:
  /// **'Views · {percent}%'**
  String relationshipCompatibilityShort(int percent);

  /// No description provided for @relationshipSharedViews.
  ///
  /// In en, this message translates to:
  /// **'{count} shared views'**
  String relationshipSharedViews(int count);

  /// No description provided for @relationshipSimilarThinker.
  ///
  /// In en, this message translates to:
  /// **'Someone who thinks similarly about relationships was found.'**
  String get relationshipSimilarThinker;

  /// No description provided for @relationshipViewsAlign.
  ///
  /// In en, this message translates to:
  /// **'Your relationship views overlap.'**
  String get relationshipViewsAlign;

  /// No description provided for @relationshipMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Relationship matches'**
  String get relationshipMatchesTitle;

  /// No description provided for @relationshipMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Answer a few relationship questions to find people who think like you — distance does not matter here.'**
  String get relationshipMatchesEmpty;

  /// No description provided for @relationshipProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{answered} relationship questions answered'**
  String relationshipProfileSubtitle(int answered);

  /// No description provided for @relationshipTopicJealousy.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about jealousy.'**
  String get relationshipTopicJealousy;

  /// No description provided for @relationshipTopicTrust.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about trust.'**
  String get relationshipTopicTrust;

  /// No description provided for @relationshipTopicLoyalty.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about loyalty.'**
  String get relationshipTopicLoyalty;

  /// No description provided for @relationshipTopicCommunication.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about communication.'**
  String get relationshipTopicCommunication;

  /// No description provided for @relationshipTopicBoundaries.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about boundaries.'**
  String get relationshipTopicBoundaries;

  /// No description provided for @relationshipTopicSocialLife.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about social life.'**
  String get relationshipTopicSocialLife;

  /// No description provided for @relationshipTopicFriendship.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about friendship.'**
  String get relationshipTopicFriendship;

  /// No description provided for @relationshipTopicPersonalSpace.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about personal space.'**
  String get relationshipTopicPersonalSpace;

  /// No description provided for @relationshipTopicFuturePlans.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about future plans.'**
  String get relationshipTopicFuturePlans;

  /// No description provided for @relationshipTopicMoney.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about money.'**
  String get relationshipTopicMoney;

  /// No description provided for @relationshipTopicFlirting.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about flirting.'**
  String get relationshipTopicFlirting;

  /// No description provided for @relationshipTopicExes.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about past relationships.'**
  String get relationshipTopicExes;

  /// No description provided for @relationshipTopicExpectations.
  ///
  /// In en, this message translates to:
  /// **'You think similarly about relationship expectations.'**
  String get relationshipTopicExpectations;

  /// No description provided for @verifyYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Verify your profile'**
  String get verifyYourProfile;

  /// No description provided for @verificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Verification helps us keep Mevora authentic and safer for everyone.'**
  String get verificationDescription;

  /// No description provided for @verificationBenefitFakeProfiles.
  ///
  /// In en, this message translates to:
  /// **'Helps protect against fake profiles'**
  String get verificationBenefitFakeProfiles;

  /// No description provided for @verificationBenefitSpoofing.
  ///
  /// In en, this message translates to:
  /// **'Helps prevent spoofing'**
  String get verificationBenefitSpoofing;

  /// No description provided for @verificationBenefitBadge.
  ///
  /// In en, this message translates to:
  /// **'Adds a verified badge to your profile'**
  String get verificationBenefitBadge;

  /// No description provided for @startVerification.
  ///
  /// In en, this message translates to:
  /// **'Start verification'**
  String get startVerification;

  /// No description provided for @verificationInProgress.
  ///
  /// In en, this message translates to:
  /// **'Verification in progress'**
  String get verificationInProgress;

  /// No description provided for @profileVerified.
  ///
  /// In en, this message translates to:
  /// **'Profile verified'**
  String get profileVerified;

  /// No description provided for @profileVerifiedBadge.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get profileVerifiedBadge;

  /// No description provided for @verificationCouldNotComplete.
  ///
  /// In en, this message translates to:
  /// **'Verification couldn\'t be completed'**
  String get verificationCouldNotComplete;

  /// No description provided for @tryVerificationAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryVerificationAgain;

  /// No description provided for @verificationStarted.
  ///
  /// In en, this message translates to:
  /// **'Verification started'**
  String get verificationStarted;

  /// No description provided for @verificationPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Your verification is handled securely by our verification provider.'**
  String get verificationPrivacyNote;

  /// No description provided for @followVerificationInstructions.
  ///
  /// In en, this message translates to:
  /// **'Please follow the instructions to verify yourself.'**
  String get followVerificationInstructions;

  /// No description provided for @verificationNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Verification is temporarily unavailable.'**
  String get verificationNotConfigured;

  /// No description provided for @verificationCooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait a few minutes before trying again.'**
  String get verificationCooldown;

  /// No description provided for @verificationAttemptLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reached today\'s verification limit. Try again tomorrow.'**
  String get verificationAttemptLimit;

  /// No description provided for @whyYouMatch.
  ///
  /// In en, this message translates to:
  /// **'Why you match'**
  String get whyYouMatch;

  /// No description provided for @compatWhyButton.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get compatWhyButton;

  /// No description provided for @compatDiscoverBadge.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Compatible'**
  String compatDiscoverBadge(int percent);

  /// No description provided for @compatCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating...'**
  String get compatCalculating;

  /// No description provided for @compatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Compatibility unavailable'**
  String get compatUnavailable;

  /// No description provided for @profileEditSectionPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get profileEditSectionPhotos;

  /// No description provided for @profileEditSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic information'**
  String get profileEditSectionBasic;

  /// No description provided for @profileEditSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About you'**
  String get profileEditSectionAbout;

  /// No description provided for @profileEditSectionInterests.
  ///
  /// In en, this message translates to:
  /// **'Your interests'**
  String get profileEditSectionInterests;

  /// No description provided for @profileEditSectionLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get profileEditSectionLifestyle;

  /// No description provided for @profileEditSectionRelationship.
  ///
  /// In en, this message translates to:
  /// **'Relationship preferences'**
  String get profileEditSectionRelationship;

  /// No description provided for @profileEditSectionAnswers.
  ///
  /// In en, this message translates to:
  /// **'Your answers'**
  String get profileEditSectionAnswers;

  /// No description provided for @profileEditDiscoveryPrefs.
  ///
  /// In en, this message translates to:
  /// **'Age range & distance'**
  String get profileEditDiscoveryPrefs;

  /// No description provided for @profileEditAnswersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update how you answer relationship questions'**
  String get profileEditAnswersSubtitle;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @discardChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// No description provided for @discardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Your profile changes haven\'t been saved.'**
  String get discardChangesMessage;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @interestsMinRequired.
  ///
  /// In en, this message translates to:
  /// **'Select at least 3 interests'**
  String get interestsMinRequired;

  /// No description provided for @profileAnswersTitle.
  ///
  /// In en, this message translates to:
  /// **'Your answers'**
  String get profileAnswersTitle;

  /// No description provided for @profileAnswersEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t answered any relationship questions yet.'**
  String get profileAnswersEmpty;

  /// No description provided for @profileAnswersEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get profileAnswersEdit;

  /// No description provided for @questionAnswersTitle.
  ///
  /// In en, this message translates to:
  /// **'Question & Answers'**
  String get questionAnswersTitle;

  /// No description provided for @questionAnswersEmpty.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t answered any questions yet.'**
  String get questionAnswersEmpty;

  /// No description provided for @questionAnswersEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Answer a few relationship questions to make your profile more personal. You can edit them anytime.'**
  String get questionAnswersEmptyHint;

  /// No description provided for @questionAnswersSaveError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save your answer. Check your connection and try again.'**
  String get questionAnswersSaveError;

  /// No description provided for @seeAllAnswers.
  ///
  /// In en, this message translates to:
  /// **'{count} more answers'**
  String seeAllAnswers(int count);

  /// No description provided for @showOnProfile.
  ///
  /// In en, this message translates to:
  /// **'Show on profile'**
  String get showOnProfile;

  /// No description provided for @questionAnswersLoadError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading answers.'**
  String get questionAnswersLoadError;

  /// No description provided for @questionAnswersMatchRequired.
  ///
  /// In en, this message translates to:
  /// **'Match with this person to see their answers.'**
  String get questionAnswersMatchRequired;

  /// No description provided for @questionAnswersMatchedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Discover what you have in common.'**
  String get questionAnswersMatchedSubtitle;

  /// No description provided for @questionAnswersPeerEmpty.
  ///
  /// In en, this message translates to:
  /// **'This person hasn\'t shared any profile answers yet.'**
  String get questionAnswersPeerEmpty;

  /// No description provided for @matchViewAnswers.
  ///
  /// In en, this message translates to:
  /// **'View answers'**
  String get matchViewAnswers;

  /// No description provided for @chatDiscoverAnswersPrompt.
  ///
  /// In en, this message translates to:
  /// **'Learn more about them'**
  String get chatDiscoverAnswersPrompt;

  /// No description provided for @compatOverallLabel.
  ///
  /// In en, this message translates to:
  /// **'You\'re {percent}% compatible'**
  String compatOverallLabel(int percent);

  /// No description provided for @compatNotEnoughData.
  ///
  /// In en, this message translates to:
  /// **'Not enough data yet'**
  String get compatNotEnoughData;

  /// No description provided for @compatStrongestConnection.
  ///
  /// In en, this message translates to:
  /// **'Strongest connection'**
  String get compatStrongestConnection;

  /// No description provided for @compatPotentialDifference.
  ///
  /// In en, this message translates to:
  /// **'Potential difference'**
  String get compatPotentialDifference;

  /// No description provided for @compatCategoryOverall.
  ///
  /// In en, this message translates to:
  /// **'Overall'**
  String get compatCategoryOverall;

  /// No description provided for @compatCategoryRelationship.
  ///
  /// In en, this message translates to:
  /// **'Relationship'**
  String get compatCategoryRelationship;

  /// No description provided for @compatCategoryInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get compatCategoryInterests;

  /// No description provided for @compatCategoryLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get compatCategoryLifestyle;

  /// No description provided for @compatCategoryQuestions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get compatCategoryQuestions;

  /// No description provided for @compatCategoryMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get compatCategoryMusic;

  /// No description provided for @compatCategoryCommunication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get compatCategoryCommunication;

  /// No description provided for @compatCategoryProximity.
  ///
  /// In en, this message translates to:
  /// **'Proximity'**
  String get compatCategoryProximity;

  /// No description provided for @compatCategoryActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get compatCategoryActivity;

  /// No description provided for @compatReasonSameRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'You both want a {goal} relationship'**
  String compatReasonSameRelationshipGoal(String goal);

  /// No description provided for @compatReasonSharedInterests.
  ///
  /// In en, this message translates to:
  /// **'You both like {interests}'**
  String compatReasonSharedInterests(String interests);

  /// No description provided for @compatReasonSimilarLifestyle.
  ///
  /// In en, this message translates to:
  /// **'You have a similar lifestyle'**
  String get compatReasonSimilarLifestyle;

  /// No description provided for @compatReasonSameAnswers.
  ///
  /// In en, this message translates to:
  /// **'You answered {aligned} of {shared} questions the same way'**
  String compatReasonSameAnswers(String aligned, String shared);

  /// No description provided for @compatReasonSimilarMusic.
  ///
  /// In en, this message translates to:
  /// **'Your music taste is {score}% aligned'**
  String compatReasonSimilarMusic(String score);

  /// No description provided for @compatReasonCommunication.
  ///
  /// In en, this message translates to:
  /// **'You communicate in similar ways'**
  String get compatReasonCommunication;

  /// No description provided for @hiddenCompatTitle.
  ///
  /// In en, this message translates to:
  /// **'Someone is thinking like you 👀'**
  String get hiddenCompatTitle;

  /// No description provided for @hiddenCompatMessage.
  ///
  /// In en, this message translates to:
  /// **'Someone answered {count} questions the same way you did.'**
  String hiddenCompatMessage(int count);

  /// No description provided for @hiddenCompatCompatibility.
  ///
  /// In en, this message translates to:
  /// **'{percent}% compatibility'**
  String hiddenCompatCompatibility(int percent);

  /// No description provided for @hiddenCompatCta.
  ///
  /// In en, this message translates to:
  /// **'Discover who'**
  String get hiddenCompatCta;

  /// No description provided for @hiddenCompatDismiss.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get hiddenCompatDismiss;

  /// No description provided for @supportCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get supportCenterTitle;

  /// No description provided for @supportCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find answers, review policies, or contact our team.'**
  String get supportCenterSubtitle;

  /// No description provided for @supportHelpSection.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get supportHelpSection;

  /// No description provided for @supportTopicsSection.
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get supportTopicsSection;

  /// No description provided for @supportFaqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get supportFaqTitle;

  /// No description provided for @supportFaqSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quick answers to common questions'**
  String get supportFaqSubtitle;

  /// No description provided for @supportFaqSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search questions'**
  String get supportFaqSearchHint;

  /// No description provided for @supportFaqEmpty.
  ///
  /// In en, this message translates to:
  /// **'No questions matched your search.'**
  String get supportFaqEmpty;

  /// No description provided for @supportCreateTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Support Request'**
  String get supportCreateTicket;

  /// No description provided for @supportCreateTicketSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue and optionally attach a screenshot'**
  String get supportCreateTicketSubtitle;

  /// No description provided for @supportMyTickets.
  ///
  /// In en, this message translates to:
  /// **'My Support Requests'**
  String get supportMyTickets;

  /// No description provided for @supportTicketsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No support requests yet'**
  String get supportTicketsEmptyTitle;

  /// No description provided for @supportTicketsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When you contact support, your requests will appear here.'**
  String get supportTicketsEmptyMessage;

  /// No description provided for @supportTicketCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get supportTicketCategory;

  /// No description provided for @supportTicketSubject.
  ///
  /// In en, this message translates to:
  /// **'Subject'**
  String get supportTicketSubject;

  /// No description provided for @supportTicketMessage.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get supportTicketMessage;

  /// No description provided for @supportTicketAddScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Add screenshot (optional)'**
  String get supportTicketAddScreenshot;

  /// No description provided for @supportTicketScreenshotAttached.
  ///
  /// In en, this message translates to:
  /// **'Screenshot attached'**
  String get supportTicketScreenshotAttached;

  /// No description provided for @supportTicketSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get supportTicketSubmit;

  /// No description provided for @supportTicketSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Your support request was sent.'**
  String get supportTicketSubmitted;

  /// No description provided for @supportTicketFailed.
  ///
  /// In en, this message translates to:
  /// **'We could not send your request. Try again.'**
  String get supportTicketFailed;

  /// No description provided for @supportTicketValidation.
  ///
  /// In en, this message translates to:
  /// **'Subject and message are required.'**
  String get supportTicketValidation;

  /// No description provided for @supportTicketDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Support request'**
  String get supportTicketDetailTitle;

  /// No description provided for @supportTicketStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get supportTicketStatusLabel;

  /// No description provided for @supportTicketAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get supportTicketAttachments;

  /// No description provided for @supportTicketStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supportTicketStatusOpen;

  /// No description provided for @supportTicketStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get supportTicketStatusInProgress;

  /// No description provided for @supportTicketStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supportTicketStatusResolved;

  /// No description provided for @supportTicketStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get supportTicketStatusClosed;

  /// No description provided for @supportCategoryAccount.
  ///
  /// In en, this message translates to:
  /// **'Account & profile'**
  String get supportCategoryAccount;

  /// No description provided for @supportCategoryMatches.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get supportCategoryMatches;

  /// No description provided for @supportCategoryMessaging.
  ///
  /// In en, this message translates to:
  /// **'Messaging'**
  String get supportCategoryMessaging;

  /// No description provided for @supportCategoryPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos & profile'**
  String get supportCategoryPhotos;

  /// No description provided for @supportCategorySafety.
  ///
  /// In en, this message translates to:
  /// **'Reporting & blocking'**
  String get supportCategorySafety;

  /// No description provided for @supportCategoryTechnical.
  ///
  /// In en, this message translates to:
  /// **'Technical issues'**
  String get supportCategoryTechnical;

  /// No description provided for @supportCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get supportCategoryOther;

  /// No description provided for @faqDeleteAccountQ.
  ///
  /// In en, this message translates to:
  /// **'How do I delete my account?'**
  String get faqDeleteAccountQ;

  /// No description provided for @faqDeleteAccountA.
  ///
  /// In en, this message translates to:
  /// **'Go to Settings → Account → Delete Account. Confirm the dialog to permanently delete your Mevora account and associated data. This cannot be undone.'**
  String get faqDeleteAccountA;

  /// No description provided for @faqChangePhotoQ.
  ///
  /// In en, this message translates to:
  /// **'How do I change my profile photo?'**
  String get faqChangePhotoQ;

  /// No description provided for @faqChangePhotoA.
  ///
  /// In en, this message translates to:
  /// **'Open Settings → Edit Profile. You can add, remove, or replace photos from your gallery or camera. Photos may be reviewed before they appear to others.'**
  String get faqChangePhotoA;

  /// No description provided for @faqCloseAccountQ.
  ///
  /// In en, this message translates to:
  /// **'How do I close my account?'**
  String get faqCloseAccountQ;

  /// No description provided for @faqCloseAccountA.
  ///
  /// In en, this message translates to:
  /// **'Closing your account is the same as deleting it. Use Settings → Account → Delete Account. Logging out alone does not delete your data.'**
  String get faqCloseAccountA;

  /// No description provided for @faqHowMatchQ.
  ///
  /// In en, this message translates to:
  /// **'How does matching work?'**
  String get faqHowMatchQ;

  /// No description provided for @faqHowMatchA.
  ///
  /// In en, this message translates to:
  /// **'When you and another person both like each other in Discover, Mevora creates a mutual match. You can then chat from the Matches tab.'**
  String get faqHowMatchA;

  /// No description provided for @faqMatchPercentQ.
  ///
  /// In en, this message translates to:
  /// **'What does the match percentage mean?'**
  String get faqMatchPercentQ;

  /// No description provided for @faqMatchPercentA.
  ///
  /// In en, this message translates to:
  /// **'It is a compatibility estimate based on profile answers, interests, lifestyle, music taste, and other signals Mevora uses. It helps you understand why you might connect, but it is not a guarantee.'**
  String get faqMatchPercentA;

  /// No description provided for @faqCantMessageQ.
  ///
  /// In en, this message translates to:
  /// **'Why can\'t I send a message?'**
  String get faqCantMessageQ;

  /// No description provided for @faqCantMessageA.
  ///
  /// In en, this message translates to:
  /// **'Messaging is only available in active mutual matches. You cannot message if the match ended, you blocked each other, or the conversation was closed.'**
  String get faqCantMessageA;

  /// No description provided for @faqNotificationsQ.
  ///
  /// In en, this message translates to:
  /// **'How do I manage notifications?'**
  String get faqNotificationsQ;

  /// No description provided for @faqNotificationsA.
  ///
  /// In en, this message translates to:
  /// **'Open Settings → Notifications to control match, message, and other alerts. You may also need to allow notifications in your device settings.'**
  String get faqNotificationsA;

  /// No description provided for @faqBlockQ.
  ///
  /// In en, this message translates to:
  /// **'How do I block someone?'**
  String get faqBlockQ;

  /// No description provided for @faqBlockA.
  ///
  /// In en, this message translates to:
  /// **'From a chat, tap More → Block. From a profile, open the safety menu → Block. Blocked users cannot message you or appear in your matches.'**
  String get faqBlockA;

  /// No description provided for @faqReportQ.
  ///
  /// In en, this message translates to:
  /// **'How do I report someone?'**
  String get faqReportQ;

  /// No description provided for @faqReportA.
  ///
  /// In en, this message translates to:
  /// **'From a chat or profile safety menu, choose Report, select a reason, and optionally add details. Reports are reviewed by our team.'**
  String get faqReportA;

  /// No description provided for @faqStaySafeQ.
  ///
  /// In en, this message translates to:
  /// **'How can I stay safe on Mevora?'**
  String get faqStaySafeQ;

  /// No description provided for @faqStaySafeA.
  ///
  /// In en, this message translates to:
  /// **'Meet in public places, keep personal details private until you trust someone, use block and report tools, and review our Community Guidelines.'**
  String get faqStaySafeA;

  /// No description provided for @guidelinesIntro.
  ///
  /// In en, this message translates to:
  /// **'Mevora is built for respectful connections. These rules apply to profiles, messages, calls, and all in-app behavior.'**
  String get guidelinesIntro;

  /// No description provided for @guidelinesRespectTitle.
  ///
  /// In en, this message translates to:
  /// **'Respectful communication'**
  String get guidelinesRespectTitle;

  /// No description provided for @guidelinesRespectBody.
  ///
  /// In en, this message translates to:
  /// **'Treat others with respect. Disagreement is not an excuse for insults, bullying, or degrading language.'**
  String get guidelinesRespectBody;

  /// No description provided for @guidelinesHarassmentTitle.
  ///
  /// In en, this message translates to:
  /// **'No harassment or bullying'**
  String get guidelinesHarassmentTitle;

  /// No description provided for @guidelinesHarassmentBody.
  ///
  /// In en, this message translates to:
  /// **'Repeated unwanted contact, intimidation, stalking, or pressuring someone is not allowed.'**
  String get guidelinesHarassmentBody;

  /// No description provided for @guidelinesHateTitle.
  ///
  /// In en, this message translates to:
  /// **'No hate speech'**
  String get guidelinesHateTitle;

  /// No description provided for @guidelinesHateBody.
  ///
  /// In en, this message translates to:
  /// **'Content attacking people based on protected characteristics is prohibited.'**
  String get guidelinesHateBody;

  /// No description provided for @guidelinesThreatsTitle.
  ///
  /// In en, this message translates to:
  /// **'No threats or violence'**
  String get guidelinesThreatsTitle;

  /// No description provided for @guidelinesThreatsBody.
  ///
  /// In en, this message translates to:
  /// **'Threats, glorification of violence, or encouragement of self-harm are forbidden.'**
  String get guidelinesThreatsBody;

  /// No description provided for @guidelinesSpamTitle.
  ///
  /// In en, this message translates to:
  /// **'No spam'**
  String get guidelinesSpamTitle;

  /// No description provided for @guidelinesSpamBody.
  ///
  /// In en, this message translates to:
  /// **'Unsolicited promotions, repetitive messages, or automated solicitation are not allowed.'**
  String get guidelinesSpamBody;

  /// No description provided for @guidelinesFakeTitle.
  ///
  /// In en, this message translates to:
  /// **'No fake accounts'**
  String get guidelinesFakeTitle;

  /// No description provided for @guidelinesFakeBody.
  ///
  /// In en, this message translates to:
  /// **'Impersonation, misleading identity, or profiles that are not authentically you are prohibited.'**
  String get guidelinesFakeBody;

  /// No description provided for @guidelinesScamTitle.
  ///
  /// In en, this message translates to:
  /// **'No fraud'**
  String get guidelinesScamTitle;

  /// No description provided for @guidelinesScamBody.
  ///
  /// In en, this message translates to:
  /// **'Scams, financial fraud, phishing, or asking for money or sensitive financial data are forbidden.'**
  String get guidelinesScamBody;

  /// No description provided for @guidelinesInappropriateTitle.
  ///
  /// In en, this message translates to:
  /// **'No inappropriate content'**
  String get guidelinesInappropriateTitle;

  /// No description provided for @guidelinesInappropriateBody.
  ///
  /// In en, this message translates to:
  /// **'Offensive, graphic, or otherwise unsuitable content is not allowed in profiles or messages.'**
  String get guidelinesInappropriateBody;

  /// No description provided for @guidelinesSexualTitle.
  ///
  /// In en, this message translates to:
  /// **'Sexual content and exploitation'**
  String get guidelinesSexualTitle;

  /// No description provided for @guidelinesSexualBody.
  ///
  /// In en, this message translates to:
  /// **'Non-consensual sexual content, exploitation, or sexual content involving minors is strictly prohibited and will be reported to authorities.'**
  String get guidelinesSexualBody;

  /// No description provided for @guidelinesMinorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Protecting minors'**
  String get guidelinesMinorsTitle;

  /// No description provided for @guidelinesMinorsBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora is for adults 18+. Profiles or behavior targeting minors are banned.'**
  String get guidelinesMinorsBody;

  /// No description provided for @guidelinesPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Protect personal information'**
  String get guidelinesPrivacyTitle;

  /// No description provided for @guidelinesPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Do not share another person\'s private contact details, address, documents, or passwords without consent.'**
  String get guidelinesPrivacyBody;

  /// No description provided for @guidelinesMisuseTitle.
  ///
  /// In en, this message translates to:
  /// **'No platform misuse'**
  String get guidelinesMisuseTitle;

  /// No description provided for @guidelinesMisuseBody.
  ///
  /// In en, this message translates to:
  /// **'Do not attempt to bypass safety systems, scrape data, or use Mevora for unauthorized commercial activity.'**
  String get guidelinesMisuseBody;

  /// No description provided for @guidelinesReportTitle.
  ///
  /// In en, this message translates to:
  /// **'How to report'**
  String get guidelinesReportTitle;

  /// No description provided for @guidelinesReportBody.
  ///
  /// In en, this message translates to:
  /// **'Use Report from a profile or chat. Choose the closest reason and add context. You can also contact support from Settings.'**
  String get guidelinesReportBody;

  /// No description provided for @guidelinesEnforcementTitle.
  ///
  /// In en, this message translates to:
  /// **'Enforcement'**
  String get guidelinesEnforcementTitle;

  /// No description provided for @guidelinesEnforcementBody.
  ///
  /// In en, this message translates to:
  /// **'Violations may result in warnings, feature limits, suspension, or permanent removal. Serious violations may be reported to law enforcement.'**
  String get guidelinesEnforcementBody;

  /// No description provided for @termsIntro.
  ///
  /// In en, this message translates to:
  /// **'These Terms of Service govern your use of the Mevora mobile application and related services.'**
  String get termsIntro;

  /// No description provided for @termsScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Scope of service'**
  String get termsScopeTitle;

  /// No description provided for @termsScopeBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora helps adults discover compatible people, match through mutual likes, chat, and use optional features such as Boost and profile verification.'**
  String get termsScopeBody;

  /// No description provided for @termsAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Your account'**
  String get termsAccountTitle;

  /// No description provided for @termsAccountBody.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 18 years old. You are responsible for keeping your login credentials secure and for activity on your account.'**
  String get termsAccountBody;

  /// No description provided for @termsResponsibilitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your responsibilities'**
  String get termsResponsibilitiesTitle;

  /// No description provided for @termsResponsibilitiesBody.
  ///
  /// In en, this message translates to:
  /// **'You agree to provide accurate information, follow applicable laws, and use Mevora respectfully and safely.'**
  String get termsResponsibilitiesBody;

  /// No description provided for @termsContentTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile and content'**
  String get termsContentTitle;

  /// No description provided for @termsContentBody.
  ///
  /// In en, this message translates to:
  /// **'You own the content you submit, but grant Mevora a license to host, display, and process it to operate the service, including moderation and safety review.'**
  String get termsContentBody;

  /// No description provided for @termsProhibitedTitle.
  ///
  /// In en, this message translates to:
  /// **'Prohibited behavior'**
  String get termsProhibitedTitle;

  /// No description provided for @termsProhibitedBody.
  ///
  /// In en, this message translates to:
  /// **'Harassment, hate speech, scams, fake profiles, sexual exploitation, spam, and attempts to harm other users or the platform are prohibited.'**
  String get termsProhibitedBody;

  /// No description provided for @termsMatchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Matching and messaging'**
  String get termsMatchingTitle;

  /// No description provided for @termsMatchingBody.
  ///
  /// In en, this message translates to:
  /// **'Matches are created through mutual likes. Messaging is available only in active matches and may be limited by safety, blocking, or moderation actions.'**
  String get termsMatchingBody;

  /// No description provided for @termsSafetyTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety tools'**
  String get termsSafetyTitle;

  /// No description provided for @termsSafetyBody.
  ///
  /// In en, this message translates to:
  /// **'You can block and report users. We may review reports and take action to protect the community.'**
  String get termsSafetyBody;

  /// No description provided for @termsSuspensionTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspension or termination'**
  String get termsSuspensionTitle;

  /// No description provided for @termsSuspensionBody.
  ///
  /// In en, this message translates to:
  /// **'We may suspend or terminate accounts that violate these Terms or create risk for other users.'**
  String get termsSuspensionBody;

  /// No description provided for @termsDeletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Account deletion'**
  String get termsDeletionTitle;

  /// No description provided for @termsDeletionBody.
  ///
  /// In en, this message translates to:
  /// **'You may delete your account in Settings → Account → Delete Account. Deletion is permanent and removes your profile and associated app data subject to legal retention limits.'**
  String get termsDeletionBody;

  /// No description provided for @termsPaidTitle.
  ///
  /// In en, this message translates to:
  /// **'Paid features'**
  String get termsPaidTitle;

  /// No description provided for @termsPaidBody.
  ///
  /// In en, this message translates to:
  /// **'Boost and other purchases are processed through your app store. Refunds follow the store\'s policies unless required otherwise by law.'**
  String get termsPaidBody;

  /// No description provided for @termsThirdPartyTitle.
  ///
  /// In en, this message translates to:
  /// **'Third-party services'**
  String get termsThirdPartyTitle;

  /// No description provided for @termsThirdPartyBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora may integrate with services such as Google Sign-In, Apple Sign-In, Spotify, Firebase, and identity verification providers. Their terms also apply.'**
  String get termsThirdPartyBody;

  /// No description provided for @termsAvailabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Service availability'**
  String get termsAvailabilityTitle;

  /// No description provided for @termsAvailabilityBody.
  ///
  /// In en, this message translates to:
  /// **'We strive for reliable service but do not guarantee uninterrupted availability. Features may change or be discontinued.'**
  String get termsAvailabilityBody;

  /// No description provided for @termsLiabilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Limitation of liability'**
  String get termsLiabilityTitle;

  /// No description provided for @termsLiabilityBody.
  ///
  /// In en, this message translates to:
  /// **'To the extent permitted by law, Mevora is provided as is. We are not liable for user conduct or offline interactions between users.'**
  String get termsLiabilityBody;

  /// No description provided for @termsChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Changes'**
  String get termsChangesTitle;

  /// No description provided for @termsChangesBody.
  ///
  /// In en, this message translates to:
  /// **'We may update these Terms. Material changes will be communicated in the app or on our policy pages.'**
  String get termsChangesBody;

  /// No description provided for @termsContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get termsContactTitle;

  /// No description provided for @termsContactBody.
  ///
  /// In en, this message translates to:
  /// **'For legal questions, contact support from Settings or email halilmertdeveliii@gmail.com.'**
  String get termsContactBody;

  /// No description provided for @termsEffectiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get termsEffectiveTitle;

  /// No description provided for @termsEffectiveBody.
  ///
  /// In en, this message translates to:
  /// **'These Terms are effective as of August 23, 2026.'**
  String get termsEffectiveBody;

  /// No description provided for @privacyIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Introduction'**
  String get privacyIntroTitle;

  /// No description provided for @privacyIntroBody.
  ///
  /// In en, this message translates to:
  /// **'This Privacy Policy explains how Mevora collects, uses, stores, and deletes personal data when you use our app.'**
  String get privacyIntroBody;

  /// No description provided for @privacyDataCollectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get privacyDataCollectedTitle;

  /// No description provided for @privacyDataCollectedBody.
  ///
  /// In en, this message translates to:
  /// **'We collect only data needed to operate matching, messaging, safety, optional music features, and account management.'**
  String get privacyDataCollectedBody;

  /// No description provided for @privacyAuthTitle.
  ///
  /// In en, this message translates to:
  /// **'Account and authentication data'**
  String get privacyAuthTitle;

  /// No description provided for @privacyAuthBody.
  ///
  /// In en, this message translates to:
  /// **'Depending on how you sign in, we may process email, phone number, authentication provider identifiers (Google, Apple, Spotify), and Firebase Authentication user ID.'**
  String get privacyAuthBody;

  /// No description provided for @privacyProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile data and photos'**
  String get privacyProfileTitle;

  /// No description provided for @privacyProfileBody.
  ///
  /// In en, this message translates to:
  /// **'Profile details you provide (name, bio, preferences, relationship answers, photos) are stored in Firebase Firestore and Firebase Storage to display your profile and power matching.'**
  String get privacyProfileBody;

  /// No description provided for @privacyLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location data'**
  String get privacyLocationTitle;

  /// No description provided for @privacyLocationBody.
  ///
  /// In en, this message translates to:
  /// **'With your permission, we use approximate location to show nearby compatible people. Precise coordinates are not exposed to other users in discovery results.'**
  String get privacyLocationBody;

  /// No description provided for @privacyMessagingTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages and calls'**
  String get privacyMessagingTitle;

  /// No description provided for @privacyMessagingBody.
  ///
  /// In en, this message translates to:
  /// **'Chat messages, voice notes, images, typing indicators, and call metadata are stored to deliver the service. Messages may be end-to-end encrypted when both users have published encryption keys.'**
  String get privacyMessagingBody;

  /// No description provided for @privacyMatchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Matching and interactions'**
  String get privacyMatchingTitle;

  /// No description provided for @privacyMatchingBody.
  ///
  /// In en, this message translates to:
  /// **'Likes, passes, matches, compatibility signals, and interaction history are stored to operate discovery and matches.'**
  String get privacyMatchingBody;

  /// No description provided for @privacyPreferencesTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings and preferences'**
  String get privacyPreferencesTitle;

  /// No description provided for @privacyPreferencesBody.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences, privacy controls (online status, last seen, typing), discovery filters, and language settings are stored to honor your choices.'**
  String get privacyPreferencesBody;

  /// No description provided for @privacySpotifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Spotify data'**
  String get privacySpotifyTitle;

  /// No description provided for @privacySpotifyBody.
  ///
  /// In en, this message translates to:
  /// **'If you connect Spotify, we store linked account metadata and music taste signals used for compatibility and music features. You can disconnect Spotify in settings.'**
  String get privacySpotifyBody;

  /// No description provided for @privacyDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Device and technical data'**
  String get privacyDeviceTitle;

  /// No description provided for @privacyDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'We process device tokens for push notifications, app diagnostics, and security logs through Firebase and related infrastructure.'**
  String get privacyDeviceBody;

  /// No description provided for @privacyWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why we use data'**
  String get privacyWhyTitle;

  /// No description provided for @privacyWhyBody.
  ///
  /// In en, this message translates to:
  /// **'To authenticate you, show matches, deliver messages, improve safety, provide support, process optional purchases, and comply with law.'**
  String get privacyWhyBody;

  /// No description provided for @privacyStorageTitle.
  ///
  /// In en, this message translates to:
  /// **'Where data is stored'**
  String get privacyStorageTitle;

  /// No description provided for @privacyStorageBody.
  ///
  /// In en, this message translates to:
  /// **'Data is primarily stored in Google Firebase (Firestore, Storage, Authentication, Cloud Functions) in the EU region where configured.'**
  String get privacyStorageBody;

  /// No description provided for @privacyRetentionTitle.
  ///
  /// In en, this message translates to:
  /// **'Retention'**
  String get privacyRetentionTitle;

  /// No description provided for @privacyRetentionBody.
  ///
  /// In en, this message translates to:
  /// **'We keep data while your account is active. When you delete your account, we delete or anonymize associated data except where law or fraud prevention requires limited retention.'**
  String get privacyRetentionBody;

  /// No description provided for @privacySharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get privacySharingTitle;

  /// No description provided for @privacySharingBody.
  ///
  /// In en, this message translates to:
  /// **'We do not sell personal data. We share data with service providers (Firebase, app stores, Spotify, verification vendors) only as needed to operate Mevora.'**
  String get privacySharingBody;

  /// No description provided for @privacyRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyRightsTitle;

  /// No description provided for @privacyRightsBody.
  ///
  /// In en, this message translates to:
  /// **'Depending on your region, you may request access, correction, deletion, or restriction of your data. Account deletion is available in Settings.'**
  String get privacyRightsBody;

  /// No description provided for @privacyDeletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting your data'**
  String get privacyDeletionTitle;

  /// No description provided for @privacyDeletionBody.
  ///
  /// In en, this message translates to:
  /// **'Use Settings → Account → Delete Account for permanent deletion. Support tickets you created are also removed as part of account deletion.'**
  String get privacyDeletionBody;

  /// No description provided for @privacySecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get privacySecurityTitle;

  /// No description provided for @privacySecurityBody.
  ///
  /// In en, this message translates to:
  /// **'We use access controls, encryption in transit, optional message encryption, and Firebase security rules. No system is perfectly secure; report issues to support.'**
  String get privacySecurityBody;

  /// No description provided for @privacyChildrenTitle.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get privacyChildrenTitle;

  /// No description provided for @privacyChildrenBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora is not for users under 18. We delete accounts identified as underage.'**
  String get privacyChildrenBody;

  /// No description provided for @privacyChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Policy changes'**
  String get privacyChangesTitle;

  /// No description provided for @privacyChangesBody.
  ///
  /// In en, this message translates to:
  /// **'We may update this policy. The latest version is always available in the app and on our public policy page.'**
  String get privacyChangesBody;

  /// No description provided for @privacyContactTitle.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get privacyContactTitle;

  /// No description provided for @privacyContactBody.
  ///
  /// In en, this message translates to:
  /// **'Privacy questions: halilmertdeveliii@gmail.com or create a support request in Settings.'**
  String get privacyContactBody;

  /// No description provided for @musicMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'🎵 Music Match — {percent}%'**
  String musicMatchTitle(int percent);

  /// No description provided for @musicInsightBandHigh.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes are quite similar.'**
  String get musicInsightBandHigh;

  /// No description provided for @musicInsightBandMid.
  ///
  /// In en, this message translates to:
  /// **'You share some strong music tastes.'**
  String get musicInsightBandMid;

  /// No description provided for @musicInsightBandLow.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes differ, but you still share a few artists.'**
  String get musicInsightBandLow;

  /// No description provided for @musicInsightSharedTracks.
  ///
  /// In en, this message translates to:
  /// **'🎵 You have {count} shared songs.'**
  String musicInsightSharedTracks(int count);

  /// No description provided for @musicInsightSharedArtists.
  ///
  /// In en, this message translates to:
  /// **'🎤 You have {count} shared artists.'**
  String musicInsightSharedArtists(int count);

  /// No description provided for @musicInsightSharedPlaylistTracks.
  ///
  /// In en, this message translates to:
  /// **'🎧 Your playlists share {count} songs.'**
  String musicInsightSharedPlaylistTracks(int count);

  /// No description provided for @musicInsightSharedRecentTracks.
  ///
  /// In en, this message translates to:
  /// **'🎵 You recently listened to {count} of the same songs.'**
  String musicInsightSharedRecentTracks(int count);

  /// No description provided for @musicInsightTopSharedArtist.
  ///
  /// In en, this message translates to:
  /// **'🎵 You both listen to {name} a lot.'**
  String musicInsightTopSharedArtist(String name);

  /// No description provided for @musicInsightTopSharedGenres.
  ///
  /// In en, this message translates to:
  /// **'🎶 Your tastes overlap most in {genres}.'**
  String musicInsightTopSharedGenres(String genres);

  /// No description provided for @musicInsightDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Not enough Spotify taste data to compare yet.'**
  String get musicInsightDataUnavailable;

  /// No description provided for @musicSpotifyNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Spotify not connected'**
  String get musicSpotifyNotConnected;

  /// No description provided for @musicSharedTracksHeading.
  ///
  /// In en, this message translates to:
  /// **'🎵 Songs you both like'**
  String get musicSharedTracksHeading;

  /// No description provided for @musicSharedArtistsHeading.
  ///
  /// In en, this message translates to:
  /// **'🎤 Artists you both like'**
  String get musicSharedArtistsHeading;

  /// No description provided for @musicSharedGenresHeading.
  ///
  /// In en, this message translates to:
  /// **'🎶 Shared genres'**
  String get musicSharedGenresHeading;

  /// No description provided for @musicViewAllShared.
  ///
  /// In en, this message translates to:
  /// **'View all ({count})'**
  String musicViewAllShared(int count);

  /// No description provided for @musicMatchDetailsCta.
  ///
  /// In en, this message translates to:
  /// **'Why this music match?'**
  String get musicMatchDetailsCta;

  /// No description provided for @profileEditSectionLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages you speak'**
  String get profileEditSectionLanguages;

  /// No description provided for @profileEditSectionHobbies.
  ///
  /// In en, this message translates to:
  /// **'Hobbies'**
  String get profileEditSectionHobbies;

  /// No description provided for @profileEditSectionExtended.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get profileEditSectionExtended;

  /// No description provided for @profileLanguagesHint.
  ///
  /// In en, this message translates to:
  /// **'Select the languages you speak.'**
  String get profileLanguagesHint;

  /// No description provided for @profileHobbiesHint.
  ///
  /// In en, this message translates to:
  /// **'Pick hobbies that describe you.'**
  String get profileHobbiesHint;

  /// No description provided for @profileHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get profileHeightLabel;

  /// No description provided for @profileHeightCm.
  ///
  /// In en, this message translates to:
  /// **'{cm} cm'**
  String profileHeightCm(int cm);

  /// No description provided for @profileHeight200Plus.
  ///
  /// In en, this message translates to:
  /// **'220+ cm'**
  String get profileHeight200Plus;

  /// No description provided for @profileOccupationLabel.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get profileOccupationLabel;

  /// No description provided for @profileCompletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Your profile is {percent}% complete'**
  String profileCompletionTitle(int percent);

  /// No description provided for @profileCompletionMissing.
  ///
  /// In en, this message translates to:
  /// **'Still missing: {fields}'**
  String profileCompletionMissing(String fields);

  /// No description provided for @profileFieldDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get profileFieldDisplayName;

  /// No description provided for @profileFieldBirthDate.
  ///
  /// In en, this message translates to:
  /// **'Birth date'**
  String get profileFieldBirthDate;

  /// No description provided for @profileFieldGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get profileFieldGender;

  /// No description provided for @profileFieldInterestedIn.
  ///
  /// In en, this message translates to:
  /// **'Interested in'**
  String get profileFieldInterestedIn;

  /// No description provided for @profileFieldCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get profileFieldCity;

  /// No description provided for @profileFieldPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get profileFieldPhotos;

  /// No description provided for @profileFieldInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get profileFieldInterests;

  /// No description provided for @profileFieldRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'Relationship goal'**
  String get profileFieldRelationshipGoal;

  /// No description provided for @profileFieldLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get profileFieldLanguages;

  /// No description provided for @profileFieldHeightCm.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get profileFieldHeightCm;

  /// No description provided for @profileFieldBio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get profileFieldBio;

  /// No description provided for @profileFieldEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get profileFieldEducation;

  /// No description provided for @profileFieldOccupation.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get profileFieldOccupation;

  /// No description provided for @profileFieldHobbies.
  ///
  /// In en, this message translates to:
  /// **'Hobbies'**
  String get profileFieldHobbies;

  /// No description provided for @profileFieldLifestyleHabits.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle habits'**
  String get profileFieldLifestyleHabits;

  /// No description provided for @profileFieldLifestyleValues.
  ///
  /// In en, this message translates to:
  /// **'Future preferences'**
  String get profileFieldLifestyleValues;

  /// No description provided for @onboardingHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get onboardingHeight;

  /// No description provided for @onboardingLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get onboardingLanguages;

  /// No description provided for @profilePartnerSmokingPref.
  ///
  /// In en, this message translates to:
  /// **'Partner smoking preference'**
  String get profilePartnerSmokingPref;

  /// No description provided for @profilePartnerDrinkingPref.
  ///
  /// In en, this message translates to:
  /// **'Partner drinking preference'**
  String get profilePartnerDrinkingPref;

  /// No description provided for @profileChildrenPreference.
  ///
  /// In en, this message translates to:
  /// **'Do you want children?'**
  String get profileChildrenPreference;

  /// No description provided for @profilePartnerChildrenPref.
  ///
  /// In en, this message translates to:
  /// **'Partner children preference'**
  String get profilePartnerChildrenPref;

  /// No description provided for @profileSocialRhythm.
  ///
  /// In en, this message translates to:
  /// **'Morning or night person?'**
  String get profileSocialRhythm;

  /// No description provided for @profileSocialLevel.
  ///
  /// In en, this message translates to:
  /// **'Social life'**
  String get profileSocialLevel;

  /// No description provided for @profileWeekendPreferences.
  ///
  /// In en, this message translates to:
  /// **'Weekend preferences'**
  String get profileWeekendPreferences;

  /// No description provided for @profileCohabitationPreference.
  ///
  /// In en, this message translates to:
  /// **'Living together'**
  String get profileCohabitationPreference;

  /// No description provided for @partnerPrefNoIssue.
  ///
  /// In en, this message translates to:
  /// **'Not important'**
  String get partnerPrefNoIssue;

  /// No description provided for @partnerPrefPrefer.
  ///
  /// In en, this message translates to:
  /// **'Prefer'**
  String get partnerPrefPrefer;

  /// No description provided for @partnerPrefPreferNot.
  ///
  /// In en, this message translates to:
  /// **'Prefer not'**
  String get partnerPrefPreferNot;

  /// No description provided for @partnerPrefNever.
  ///
  /// In en, this message translates to:
  /// **'Dealbreaker'**
  String get partnerPrefNever;

  /// No description provided for @childrenPrefYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get childrenPrefYes;

  /// No description provided for @childrenPrefNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get childrenPrefNo;

  /// No description provided for @childrenPrefMaybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get childrenPrefMaybe;

  /// No description provided for @childrenPrefUndecided.
  ///
  /// In en, this message translates to:
  /// **'Not decided yet'**
  String get childrenPrefUndecided;

  /// No description provided for @socialRhythmMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning person'**
  String get socialRhythmMorning;

  /// No description provided for @socialRhythmNight.
  ///
  /// In en, this message translates to:
  /// **'Night owl'**
  String get socialRhythmNight;

  /// No description provided for @socialRhythmVaries.
  ///
  /// In en, this message translates to:
  /// **'It varies'**
  String get socialRhythmVaries;

  /// No description provided for @socialLevelVerySocial.
  ///
  /// In en, this message translates to:
  /// **'Very social'**
  String get socialLevelVerySocial;

  /// No description provided for @socialLevelBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get socialLevelBalanced;

  /// No description provided for @socialLevelQuiet.
  ///
  /// In en, this message translates to:
  /// **'More quiet'**
  String get socialLevelQuiet;

  /// No description provided for @weekendFriendsOut.
  ///
  /// In en, this message translates to:
  /// **'Going out with friends'**
  String get weekendFriendsOut;

  /// No description provided for @weekendHomeRelax.
  ///
  /// In en, this message translates to:
  /// **'Relaxing at home'**
  String get weekendHomeRelax;

  /// No description provided for @weekendSports.
  ///
  /// In en, this message translates to:
  /// **'Sports'**
  String get weekendSports;

  /// No description provided for @weekendTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get weekendTravel;

  /// No description provided for @weekendNature.
  ///
  /// In en, this message translates to:
  /// **'Nature'**
  String get weekendNature;

  /// No description provided for @weekendParty.
  ///
  /// In en, this message translates to:
  /// **'Parties'**
  String get weekendParty;

  /// No description provided for @weekendFamily.
  ///
  /// In en, this message translates to:
  /// **'Family time'**
  String get weekendFamily;

  /// No description provided for @weekendMovies.
  ///
  /// In en, this message translates to:
  /// **'Movies & series'**
  String get weekendMovies;

  /// No description provided for @cohabitationYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get cohabitationYes;

  /// No description provided for @cohabitationMaybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get cohabitationMaybeLater;

  /// No description provided for @cohabitationUnsure.
  ///
  /// In en, this message translates to:
  /// **'Not sure'**
  String get cohabitationUnsure;

  /// No description provided for @cohabitationNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get cohabitationNo;

  /// No description provided for @languageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get languageGerman;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get languageFrench;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get languageSpanish;

  /// No description provided for @languageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get languageItalian;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get languageRussian;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get languagePersian;

  /// No description provided for @languageKurdish.
  ///
  /// In en, this message translates to:
  /// **'Kurdish'**
  String get languageKurdish;

  /// No description provided for @languageGreek.
  ///
  /// In en, this message translates to:
  /// **'Greek'**
  String get languageGreek;

  /// No description provided for @languageDutch.
  ///
  /// In en, this message translates to:
  /// **'Dutch'**
  String get languageDutch;

  /// No description provided for @languagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get languagePortuguese;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get languageChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get languageKorean;

  /// No description provided for @hobbyWorkingOut.
  ///
  /// In en, this message translates to:
  /// **'Working out'**
  String get hobbyWorkingOut;

  /// No description provided for @hobbyRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get hobbyRunning;

  /// No description provided for @hobbyFitness.
  ///
  /// In en, this message translates to:
  /// **'Fitness'**
  String get hobbyFitness;

  /// No description provided for @hobbySwimming.
  ///
  /// In en, this message translates to:
  /// **'Swimming'**
  String get hobbySwimming;

  /// No description provided for @hobbyDancing.
  ///
  /// In en, this message translates to:
  /// **'Dancing'**
  String get hobbyDancing;

  /// No description provided for @hobbyPhotography.
  ///
  /// In en, this message translates to:
  /// **'Photography'**
  String get hobbyPhotography;

  /// No description provided for @hobbyPainting.
  ///
  /// In en, this message translates to:
  /// **'Painting'**
  String get hobbyPainting;

  /// No description provided for @hobbyGaming.
  ///
  /// In en, this message translates to:
  /// **'Gaming'**
  String get hobbyGaming;

  /// No description provided for @hobbyCoding.
  ///
  /// In en, this message translates to:
  /// **'Coding'**
  String get hobbyCoding;

  /// No description provided for @hobbyCooking.
  ///
  /// In en, this message translates to:
  /// **'Cooking'**
  String get hobbyCooking;

  /// No description provided for @hobbyTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get hobbyTravel;

  /// No description provided for @hobbyCamping.
  ///
  /// In en, this message translates to:
  /// **'Camping'**
  String get hobbyCamping;

  /// No description provided for @hobbyHiking.
  ///
  /// In en, this message translates to:
  /// **'Hiking'**
  String get hobbyHiking;

  /// No description provided for @hobbyPlayingInstrument.
  ///
  /// In en, this message translates to:
  /// **'Playing an instrument'**
  String get hobbyPlayingInstrument;

  /// No description provided for @hobbyReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get hobbyReading;

  /// No description provided for @hobbyYoga.
  ///
  /// In en, this message translates to:
  /// **'Yoga'**
  String get hobbyYoga;

  /// No description provided for @hobbyCycling.
  ///
  /// In en, this message translates to:
  /// **'Cycling'**
  String get hobbyCycling;

  /// No description provided for @hobbyTeamSports.
  ///
  /// In en, this message translates to:
  /// **'Team sports'**
  String get hobbyTeamSports;

  /// No description provided for @compatCategoryLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get compatCategoryLanguages;

  /// No description provided for @compatCategoryHobbies.
  ///
  /// In en, this message translates to:
  /// **'Hobbies'**
  String get compatCategoryHobbies;

  /// No description provided for @compatCategoryValues.
  ///
  /// In en, this message translates to:
  /// **'Values & future'**
  String get compatCategoryValues;

  /// No description provided for @compatReasonSharedLanguages.
  ///
  /// In en, this message translates to:
  /// **'You both speak {languages}'**
  String compatReasonSharedLanguages(String languages);

  /// No description provided for @compatReasonSharedHobbies.
  ///
  /// In en, this message translates to:
  /// **'You both enjoy {hobbies}'**
  String compatReasonSharedHobbies(String hobbies);
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
