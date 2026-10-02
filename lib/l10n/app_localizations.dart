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
  /// **'Instead of showing you hundreds of people, Mevora tries to pick the ones you might actually click with.'**
  String get tagline;

  /// No description provided for @connectTagline.
  ///
  /// In en, this message translates to:
  /// **'Connect with people who match you.'**
  String get connectTagline;

  /// Welcome/login hero slogan.
  ///
  /// In en, this message translates to:
  /// **'Not more people. Better matches for you.'**
  String get loginSlogan;

  /// No description provided for @discoverBestMatchesTitle.
  ///
  /// In en, this message translates to:
  /// **'For You'**
  String get discoverBestMatchesTitle;

  /// No description provided for @discoverBestMatchesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People who may be right for you'**
  String get discoverBestMatchesSubtitle;

  /// No description provided for @onboardingUnderstandingMessage.
  ///
  /// In en, this message translates to:
  /// **'We use your answers to choose people who may be a better fit for you.'**
  String get onboardingUnderstandingMessage;

  /// No description provided for @onboardingWhyRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'This helps us find people who want the same thing.'**
  String get onboardingWhyRelationshipGoal;

  /// No description provided for @onboardingWhyLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Everyday habits matter more over time than they seem.'**
  String get onboardingWhyLifestyle;

  /// No description provided for @onboardingWhyBio.
  ///
  /// In en, this message translates to:
  /// **'Even a few lines give people somewhere to start.'**
  String get onboardingWhyBio;

  /// No description provided for @discoveryActionConnect.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get discoveryActionConnect;

  /// No description provided for @discoveryActionPriorityIntro.
  ///
  /// In en, this message translates to:
  /// **'Priority intro'**
  String get discoveryActionPriorityIntro;

  /// No description provided for @picksTitle.
  ///
  /// In en, this message translates to:
  /// **'Mevora Picks'**
  String get picksTitle;

  /// No description provided for @picksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chosen for you'**
  String get picksSubtitle;

  /// No description provided for @picksHeadline.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Mevora Picks'**
  String get picksHeadline;

  /// No description provided for @picksIntroCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{One person we think could be right for you.} other{{count} people we think could be right for you.}}'**
  String picksIntroCount(int count);

  /// No description provided for @picksIntroNote.
  ///
  /// In en, this message translates to:
  /// **'Chosen from your compatibility, not at random. Refreshed daily.'**
  String get picksIntroNote;

  /// No description provided for @picksLowSupplyNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{We found one strong match today. Rather than lower the bar, we\'re showing fewer.} other{We found {count} strong matches today. Rather than lower the bar, we\'re showing fewer.}}'**
  String picksLowSupplyNote(int count);

  /// No description provided for @picksLoading.
  ///
  /// In en, this message translates to:
  /// **'Choosing people for you…'**
  String get picksLoading;

  /// No description provided for @picksLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load your Picks.'**
  String get picksLoadErrorTitle;

  /// No description provided for @picksEmptyPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t choose anyone for you today.'**
  String get picksEmptyPreparingTitle;

  /// No description provided for @picksEmptyPreparingMessage.
  ///
  /// In en, this message translates to:
  /// **'Instead of showing you random profiles, we\'re finding more meaningful matches.'**
  String get picksEmptyPreparingMessage;

  /// No description provided for @picksEmptyDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve seen today\'s picks.'**
  String get picksEmptyDoneTitle;

  /// No description provided for @picksDiscoveryOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery is off'**
  String get picksDiscoveryOffTitle;

  /// No description provided for @picksDiscoveryOffMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn discovery on in settings to get Picks.'**
  String get picksDiscoveryOffMessage;

  /// No description provided for @picksLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get picksLike;

  /// No description provided for @picksPass.
  ///
  /// In en, this message translates to:
  /// **'Pass'**
  String get picksPass;

  /// No description provided for @picksLikeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Like {name}'**
  String picksLikeSemantics(String name);

  /// No description provided for @picksPassSemantics.
  ///
  /// In en, this message translates to:
  /// **'Pass on {name}'**
  String picksPassSemantics(String name);

  /// No description provided for @picksOpenProfileSemantics.
  ///
  /// In en, this message translates to:
  /// **'Open {name}\'s profile'**
  String picksOpenProfileSemantics(String name);

  /// No description provided for @picksActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That didn\'t go through. Try again.'**
  String get picksActionFailed;

  /// No description provided for @picksMatchScore.
  ///
  /// In en, this message translates to:
  /// **'Mevora match {score}%'**
  String picksMatchScore(int score);

  /// No description provided for @picksEmptyDoneMessage.
  ///
  /// In en, this message translates to:
  /// **'Mevora will choose new people for you tomorrow.'**
  String get picksEmptyDoneMessage;

  /// No description provided for @picksEmptyNoCandidatesMessage.
  ///
  /// In en, this message translates to:
  /// **'Rather than show you random profiles, we\'ll look again tomorrow.'**
  String get picksEmptyNoCandidatesMessage;

  /// No description provided for @learningCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s questions are ready'**
  String get learningCardTitle;

  /// No description provided for @learningCardTodayStart.
  ///
  /// In en, this message translates to:
  /// **'Today\'s {total} short questions help us choose people who fit you.'**
  String learningCardTodayStart(int total);

  /// No description provided for @learningCardTodayResume.
  ///
  /// In en, this message translates to:
  /// **'{answered} of {total} answered. Pick up where you left off.'**
  String learningCardTodayResume(int answered, int total);

  /// No description provided for @learningCardStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get learningCardStart;

  /// No description provided for @learningCardResume.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get learningCardResume;

  /// No description provided for @learningSkipToday.
  ///
  /// In en, this message translates to:
  /// **'Skip for today'**
  String get learningSkipToday;

  /// No description provided for @learningRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'First, let us get to know you'**
  String get learningRequiredTitle;

  /// No description provided for @learningRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Picks are chosen from your answers. {total} short questions, about two minutes.'**
  String learningRequiredBody(int total);

  /// No description provided for @learningIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Let Mevora get to know you a little more each day'**
  String get learningIntroTitle;

  /// No description provided for @learningIntroBody.
  ///
  /// In en, this message translates to:
  /// **'Today\'s {count} short questions help us choose people who fit you better.'**
  String learningIntroBody(int count);

  /// No description provided for @learningIntroMeta.
  ///
  /// In en, this message translates to:
  /// **'{count} short questions · about two minutes'**
  String learningIntroMeta(int count);

  /// No description provided for @learningIntroStart.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start'**
  String get learningIntroStart;

  /// No description provided for @learningProgress.
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String learningProgress(int current, int total);

  /// No description provided for @learningProgressSemantics.
  ///
  /// In en, this message translates to:
  /// **'Question {current} of {total}'**
  String learningProgressSemantics(int current, int total);

  /// No description provided for @learningPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get learningPrevious;

  /// No description provided for @learningNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get learningNext;

  /// No description provided for @learningSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your answer. Try again.'**
  String get learningSaveFailed;

  /// No description provided for @learningLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load the questions.'**
  String get learningLoadErrorTitle;

  /// No description provided for @learningDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'That\'s it for today.'**
  String get learningDoneTitle;

  /// No description provided for @learningDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora knows you a little better now.'**
  String get learningDoneBody;

  /// No description provided for @learningDoneContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get learningDoneContinue;

  /// No description provided for @learningDoneTomorrow.
  ///
  /// In en, this message translates to:
  /// **'New questions will be waiting tomorrow.'**
  String get learningDoneTomorrow;

  /// No description provided for @learningSkippedTitle.
  ///
  /// In en, this message translates to:
  /// **'Okay, see you tomorrow.'**
  String get learningSkippedTitle;

  /// No description provided for @learningSkippedBody.
  ///
  /// In en, this message translates to:
  /// **'You can still answer today\'s questions from Let Mevora get to know me in your profile.'**
  String get learningSkippedBody;

  /// No description provided for @learningProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Let Mevora get to know me'**
  String get learningProfileTitle;

  /// No description provided for @learningProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your answers help us choose people who fit you.'**
  String get learningProfileSubtitle;

  /// No description provided for @learningAfterHumorTitle.
  ///
  /// In en, this message translates to:
  /// **'We know your humor a little now.'**
  String get learningAfterHumorTitle;

  /// No description provided for @learningAfterHumorBody.
  ///
  /// In en, this message translates to:
  /// **'Now let\'s learn what matters to you in a relationship, with today\'s questions.'**
  String get learningAfterHumorBody;

  /// No description provided for @learningDashboardHeadline.
  ///
  /// In en, this message translates to:
  /// **'How well does Mevora know you?'**
  String get learningDashboardHeadline;

  /// No description provided for @learningDashboardPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String learningDashboardPercent(int percent);

  /// No description provided for @learningDashboardBody.
  ///
  /// In en, this message translates to:
  /// **'Your answers and your profile help us choose people who fit you.'**
  String get learningDashboardBody;

  /// No description provided for @learningDashboardThisMonth.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No questions answered this month yet} =1{1 question answered this month} other{{count} questions answered this month}}'**
  String learningDashboardThisMonth(int count);

  /// No description provided for @learningDashboardTotals.
  ///
  /// In en, this message translates to:
  /// **'{total, plural, =1{1 answer} other{{total} answers}} in total · {days, plural, =1{1 day} other{{days} days}} completed'**
  String learningDashboardTotals(int total, int days);

  /// No description provided for @learningDashboardToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s questions ({answered}/{total})'**
  String learningDashboardToday(int answered, int total);

  /// No description provided for @learningDashboardTodayDone.
  ///
  /// In en, this message translates to:
  /// **'Done for today. New questions arrive tomorrow.'**
  String get learningDashboardTodayDone;

  /// No description provided for @learningDashboardCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Compatibility areas'**
  String get learningDashboardCategoriesTitle;

  /// No description provided for @learningDashboardHighlightsTitle.
  ///
  /// In en, this message translates to:
  /// **'What we\'ve learned so far'**
  String get learningDashboardHighlightsTitle;

  /// No description provided for @learningDashboardHighlightsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From your own answers.'**
  String get learningDashboardHighlightsSubtitle;

  /// No description provided for @learningDashboardAnswersTitle.
  ///
  /// In en, this message translates to:
  /// **'Your answers'**
  String get learningDashboardAnswersTitle;

  /// No description provided for @learningDashboardAnswersFooter.
  ///
  /// In en, this message translates to:
  /// **'Changed your mind? Tap an answer to change it.'**
  String get learningDashboardAnswersFooter;

  /// No description provided for @learningCategoryRelationship.
  ///
  /// In en, this message translates to:
  /// **'Relationship expectations'**
  String get learningCategoryRelationship;

  /// No description provided for @learningCategoryCommunication.
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get learningCategoryCommunication;

  /// No description provided for @learningCategoryLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Lifestyle'**
  String get learningCategoryLifestyle;

  /// No description provided for @learningCategoryValues.
  ///
  /// In en, this message translates to:
  /// **'Values'**
  String get learningCategoryValues;

  /// No description provided for @learningCategoryHumor.
  ///
  /// In en, this message translates to:
  /// **'Humor'**
  String get learningCategoryHumor;

  /// No description provided for @learningCategoryMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get learningCategoryMusic;

  /// No description provided for @learningCategoryInterests.
  ///
  /// In en, this message translates to:
  /// **'Interests'**
  String get learningCategoryInterests;

  /// No description provided for @pickTypeBestOverall.
  ///
  /// In en, this message translates to:
  /// **'Best match'**
  String get pickTypeBestOverall;

  /// No description provided for @pickTypeValuesMatch.
  ///
  /// In en, this message translates to:
  /// **'Values match'**
  String get pickTypeValuesMatch;

  /// No description provided for @pickTypeHumorMatch.
  ///
  /// In en, this message translates to:
  /// **'Humor match'**
  String get pickTypeHumorMatch;

  /// No description provided for @pickTypeMusicMatch.
  ///
  /// In en, this message translates to:
  /// **'Music match'**
  String get pickTypeMusicMatch;

  /// No description provided for @pickTypeNearbyMatch.
  ///
  /// In en, this message translates to:
  /// **'Nearby match'**
  String get pickTypeNearbyMatch;

  /// No description provided for @pickTypeUnexpectedMatch.
  ///
  /// In en, this message translates to:
  /// **'Unexpected match'**
  String get pickTypeUnexpectedMatch;

  /// No description provided for @pickHeadlineBestOverallStrong.
  ///
  /// In en, this message translates to:
  /// **'Your overall compatibility is very high.'**
  String get pickHeadlineBestOverallStrong;

  /// No description provided for @pickHeadlineBestOverall.
  ///
  /// In en, this message translates to:
  /// **'Your overall compatibility is strong.'**
  String get pickHeadlineBestOverall;

  /// No description provided for @pickHeadlineValues.
  ///
  /// In en, this message translates to:
  /// **'Your relationship expectations and core values line up strongly.'**
  String get pickHeadlineValues;

  /// No description provided for @pickHeadlineHumorScore.
  ///
  /// In en, this message translates to:
  /// **'Your humor profiles are {score}% compatible.'**
  String pickHeadlineHumorScore(int score);

  /// No description provided for @pickHeadlineMusicArtists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You share an artist you both love.} other{You share {count} artists.}}'**
  String pickHeadlineMusicArtists(int count);

  /// No description provided for @pickHeadlineMusic.
  ///
  /// In en, this message translates to:
  /// **'There\'s a strong overlap in your music taste.'**
  String get pickHeadlineMusic;

  /// No description provided for @pickHeadlineNearby.
  ///
  /// In en, this message translates to:
  /// **'Close by — and a strong match.'**
  String get pickHeadlineNearby;

  /// No description provided for @pickHeadlineUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Someone you might otherwise overlook.'**
  String get pickHeadlineUnexpected;

  /// No description provided for @pickDetailUnexpected.
  ///
  /// In en, this message translates to:
  /// **'Your interests may not look alike, but your relationship expectations and communication style line up strongly.'**
  String get pickDetailUnexpected;

  /// No description provided for @pickWhyTitle.
  ///
  /// In en, this message translates to:
  /// **'Why {name}?'**
  String pickWhyTitle(String name);

  /// No description provided for @pickReasonOverall.
  ///
  /// In en, this message translates to:
  /// **'Your overall Mevora compatibility is {score}%.'**
  String pickReasonOverall(int score);

  /// No description provided for @pickReasonRelationship.
  ///
  /// In en, this message translates to:
  /// **'You\'re looking for the same kind of relationship.'**
  String get pickReasonRelationship;

  /// No description provided for @pickReasonViews.
  ///
  /// In en, this message translates to:
  /// **'You gave the same answer on {aligned} of {shared} relationship questions.'**
  String pickReasonViews(int aligned, int shared);

  /// No description provided for @pickReasonCommunication.
  ///
  /// In en, this message translates to:
  /// **'Your communication styles look compatible.'**
  String get pickReasonCommunication;

  /// No description provided for @pickReasonLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Your lifestyle preferences fit together.'**
  String get pickReasonLifestyle;

  /// No description provided for @pickReasonHumorTraits.
  ///
  /// In en, this message translates to:
  /// **'Humor styles you share: {traits}.'**
  String pickReasonHumorTraits(String traits);

  /// No description provided for @pickReasonMusicArtists.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Your music profiles share an artist.} other{Your music profiles share {count} artists.}}'**
  String pickReasonMusicArtists(int count);

  /// No description provided for @pickReasonMusicScore.
  ///
  /// In en, this message translates to:
  /// **'Your music compatibility is {score}%.'**
  String pickReasonMusicScore(int score);

  /// No description provided for @pickReasonDistance.
  ///
  /// In en, this message translates to:
  /// **'{distance} — close enough to meet easily.'**
  String pickReasonDistance(String distance);

  /// No description provided for @pickReasonInterests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You share an interest.} other{You share {count} interests.}}'**
  String pickReasonInterests(int count);

  /// No description provided for @compatScoreHeading.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get compatScoreHeading;

  /// Overall compatibility tier, score 80-100.
  ///
  /// In en, this message translates to:
  /// **'Strong match'**
  String get compatTierStrong;

  /// Overall compatibility tier, score 65-79.
  ///
  /// In en, this message translates to:
  /// **'Close on a lot of things'**
  String get compatTierClose;

  /// Overall compatibility tier, score 50-64.
  ///
  /// In en, this message translates to:
  /// **'Real things in common'**
  String get compatTierNotable;

  /// Overall compatibility tier, score 0-49. Never phrased as a negative.
  ///
  /// In en, this message translates to:
  /// **'A few things in common'**
  String get compatTierSome;

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
  /// **'Sign in to see who we picked for you.'**
  String get loginSubtitle;

  /// No description provided for @createAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createAccountTitle;

  /// No description provided for @registerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Join Mevora to meet people who may genuinely fit you.'**
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
  /// **'We couldn\'t verify this device. Check your connection, wait a few seconds and request a new code.'**
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

  /// No description provided for @authSessionUnverified.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your session. Please sign in again.'**
  String get authSessionUnverified;

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
  /// **'This account has been disabled. If you think this is a mistake, contact Mevora support at destek@mevora.com to appeal.'**
  String get authDisabled;

  /// No description provided for @authBanned.
  ///
  /// In en, this message translates to:
  /// **'This account has been closed for breaking our community guidelines. If you think this is a mistake, contact Mevora support at destek@mevora.com to appeal.'**
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
  /// **'Phone sign-in isn\'t available right now. Please use another way to sign in.'**
  String get authNotConfigured;

  /// No description provided for @authBillingNotEnabled.
  ///
  /// In en, this message translates to:
  /// **'We can\'t send verification codes right now. Please try again later or use another way to sign in.'**
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
  /// **'Let\'s get to know you'**
  String get onboardingTitle;

  /// No description provided for @onboardingMessage.
  ///
  /// In en, this message translates to:
  /// **'The better we know you, the more carefully we can choose who to show you.'**
  String get onboardingMessage;

  /// No description provided for @onboardingFirstName.
  ///
  /// In en, this message translates to:
  /// **'First name'**
  String get onboardingFirstName;

  /// No description provided for @onboardingLastName.
  ///
  /// In en, this message translates to:
  /// **'Last name'**
  String get onboardingLastName;

  /// No description provided for @onboardingLastNamePrivate.
  ///
  /// In en, this message translates to:
  /// **'Other members never see your last name.'**
  String get onboardingLastNamePrivate;

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

  /// No description provided for @onboardingErrorBirthday.
  ///
  /// In en, this message translates to:
  /// **'Add your birthday.'**
  String get onboardingErrorBirthday;

  /// No description provided for @onboardingErrorFirstName.
  ///
  /// In en, this message translates to:
  /// **'Add your first name.'**
  String get onboardingErrorFirstName;

  /// No description provided for @onboardingErrorLastName.
  ///
  /// In en, this message translates to:
  /// **'Add your last name.'**
  String get onboardingErrorLastName;

  /// No description provided for @onboardingErrorGender.
  ///
  /// In en, this message translates to:
  /// **'Choose how you identify.'**
  String get onboardingErrorGender;

  /// No description provided for @onboardingErrorInterestedIn.
  ///
  /// In en, this message translates to:
  /// **'Choose who you\'d like to meet.'**
  String get onboardingErrorInterestedIn;

  /// No description provided for @onboardingErrorCity.
  ///
  /// In en, this message translates to:
  /// **'Choose your city.'**
  String get onboardingErrorCity;

  /// No description provided for @onboardingErrorEducation.
  ///
  /// In en, this message translates to:
  /// **'Choose your education.'**
  String get onboardingErrorEducation;

  /// No description provided for @onboardingErrorRelationshipGoal.
  ///
  /// In en, this message translates to:
  /// **'Choose what you\'re looking for.'**
  String get onboardingErrorRelationshipGoal;

  /// No description provided for @onboardingErrorLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Answer all of the lifestyle questions.'**
  String get onboardingErrorLifestyle;

  /// No description provided for @onboardingErrorInterestsMax.
  ///
  /// In en, this message translates to:
  /// **'Choose up to {max} interests.'**
  String onboardingErrorInterestsMax(int max);

  /// No description provided for @onboardingErrorBioShort.
  ///
  /// In en, this message translates to:
  /// **'Write at least {min} characters about yourself.'**
  String onboardingErrorBioShort(int min);

  /// No description provided for @onboardingErrorBioLong.
  ///
  /// In en, this message translates to:
  /// **'Keep it to {max} characters or fewer.'**
  String onboardingErrorBioLong(int max);

  /// No description provided for @onboardingErrorPhotosMax.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {max} photos.'**
  String onboardingErrorPhotosMax(int max);

  /// No description provided for @onboardingErrorPhotosInReview.
  ///
  /// In en, this message translates to:
  /// **'Your photos are still being reviewed. Try again shortly.'**
  String get onboardingErrorPhotosInReview;

  /// No description provided for @onboardingErrorProfileIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some required details are missing. Go back and fill them in.'**
  String get onboardingErrorProfileIncomplete;

  /// No description provided for @onboardingErrorSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'Sign in again to finish setting up your profile.'**
  String get onboardingErrorSignInAgain;

  /// No description provided for @onboardingErrorNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This account can\'t finish setup.'**
  String get onboardingErrorNotAllowed;

  /// No description provided for @onboardingErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t finish setting up your profile. Please try again.'**
  String get onboardingErrorGeneric;

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

  /// No description provided for @onboardingLogoutBody.
  ///
  /// In en, this message translates to:
  /// **'The steps you\'ve finished are saved. Sign in again to pick up where you left off.'**
  String get onboardingLogoutBody;

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
  /// **'Pick at least 3. Shared interests help us find people you\'ll have something to talk about with.'**
  String get onboardingInterestsHint;

  /// No description provided for @onboardingBioHint.
  ///
  /// In en, this message translates to:
  /// **'Share a little about yourself.'**
  String get onboardingBioHint;

  /// No description provided for @onboardingPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Add at least 3 photos. Your face should be clearly visible in at least one. In the others you can show your hobbies, your travels, your pet or moments from your life.'**
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
  /// **'Your profile is ready. The better we get to know you, the more meaningful the people we pick for you will be.'**
  String get onboardingCompleteMessage;

  /// No description provided for @onboardingStartDiscovering.
  ///
  /// In en, this message translates to:
  /// **'See who we picked'**
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
  /// **'Find people near you'**
  String get locationPermissionTitle;

  /// No description provided for @locationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Mevora uses your location to pick people who fit you and are close enough to actually meet.'**
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
  /// **'Location helps us pick people near you. You can turn it on later in Settings.'**
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
  /// **'Turn on location services so we can pick people near you.'**
  String get gpsDisabledMessage;

  /// No description provided for @locationDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Without location permission we can\'t pick people near you.'**
  String get locationDeniedMessage;

  /// No description provided for @locationSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'All set. We can now pick people near you.'**
  String get locationSuccessTitle;

  /// No description provided for @locationLocating.
  ///
  /// In en, this message translates to:
  /// **'Finding your location...'**
  String get locationLocating;

  /// No description provided for @locationPreparingMatches.
  ///
  /// In en, this message translates to:
  /// **'Picking people near you...'**
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
  /// **'Your picks are on the way'**
  String get discoveryTitle;

  /// No description provided for @discoveryMessage.
  ///
  /// In en, this message translates to:
  /// **'People who may be right for you will appear here.'**
  String get discoveryMessage;

  /// No description provided for @discoveryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'That\'s everyone for now'**
  String get discoveryEmptyTitle;

  /// No description provided for @discoveryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When we find new people who may be right for you, you\'ll see them here. You can also widen your distance.'**
  String get discoveryEmptyMessage;

  /// No description provided for @discoverySeenEveryoneTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ve seen everyone we picked for now'**
  String get discoverySeenEveryoneTitle;

  /// No description provided for @discoverySeenEveryoneMessage.
  ///
  /// In en, this message translates to:
  /// **'New people who may be right for you will show up here as we find them.'**
  String get discoverySeenEveryoneMessage;

  /// No description provided for @exploreAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get exploreAgain;

  /// No description provided for @restartDemo.
  ///
  /// In en, this message translates to:
  /// **'Restart demo'**
  String get restartDemo;

  /// No description provided for @discoveryFiltersTitle.
  ///
  /// In en, this message translates to:
  /// **'Your preferences'**
  String get discoveryFiltersTitle;

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
  /// **'Why they could be right for you'**
  String get whyYoureSeeingThis;

  /// Heading above the real reasons a person was picked.
  ///
  /// In en, this message translates to:
  /// **'Why {name}?'**
  String compatWhyThisPerson(String name);

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
  /// **'For You'**
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
  /// **'Picked for you · {percent}% match'**
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
  /// **'You chose each other'**
  String get itsAMatch;

  /// No description provided for @youLikedEachOther.
  ///
  /// In en, this message translates to:
  /// **'You both said yes.'**
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
  /// **'Back to your picks'**
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

  /// No description provided for @spokenLanguageTurkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish 🇹🇷'**
  String get spokenLanguageTurkish;

  /// No description provided for @spokenLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English 🇬🇧'**
  String get spokenLanguageEnglish;

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
  /// **'Match preferences'**
  String get discoveryPreferences;

  /// No description provided for @settingsPersonalizeRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Personalize my recommendations based on my interactions'**
  String get settingsPersonalizeRecommendations;

  /// No description provided for @settingsPersonalizeRecommendationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We use signals such as likes, matches and conversation activity to gradually improve your recommendations. We never analyze the content of your messages for this.'**
  String get settingsPersonalizeRecommendationsSubtitle;

  /// No description provided for @settingsResetLearned.
  ///
  /// In en, this message translates to:
  /// **'Reset what Mevora learned from me'**
  String get settingsResetLearned;

  /// No description provided for @settingsResetLearnedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Clears what was learned from your interactions. Your answers stay.'**
  String get settingsResetLearnedSubtitle;

  /// No description provided for @settingsResetLearnedConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset what Mevora learned?'**
  String get settingsResetLearnedConfirmTitle;

  /// No description provided for @settingsResetLearnedConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora will forget what it learned from your likes, matches and conversation activity. Your answers and your profile don\'t change.'**
  String get settingsResetLearnedConfirmBody;

  /// No description provided for @settingsResetLearnedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetLearnedConfirm;

  /// No description provided for @settingsResetLearnedDone.
  ///
  /// In en, this message translates to:
  /// **'What Mevora learned has been reset.'**
  String get settingsResetLearnedDone;

  /// No description provided for @settingsResetLearnedFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reset. Try again.'**
  String get settingsResetLearnedFailed;

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
  /// **'Preferred distance (km)'**
  String get maxDistance;

  /// No description provided for @maxDistanceHint.
  ///
  /// In en, this message translates to:
  /// **'People inside this distance come first. When there are not enough, Mevora looks further, up to 100 km.'**
  String get maxDistanceHint;

  /// No description provided for @matchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Your matches'**
  String get matchesTitle;

  /// No description provided for @matchesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'People who chose you back, best match first.'**
  String get matchesSubtitle;

  /// No description provided for @matchesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your matches will show up here'**
  String get matchesEmptyTitle;

  /// No description provided for @matchesEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When you and someone choose each other, you\'ll find them here — along with what you have in common.'**
  String get matchesEmptyMessage;

  /// No description provided for @newMatch.
  ///
  /// In en, this message translates to:
  /// **'New match'**
  String get newMatch;

  /// No description provided for @connectionBadgeNew.
  ///
  /// In en, this message translates to:
  /// **'New match'**
  String get connectionBadgeNew;

  /// No description provided for @connectionBadgeActive.
  ///
  /// In en, this message translates to:
  /// **'Active conversation'**
  String get connectionBadgeActive;

  /// No description provided for @matchStrongestConnectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Strongest in {category}'**
  String matchStrongestConnectionLabel(String category);

  /// No description provided for @compatStrongestRelationship.
  ///
  /// In en, this message translates to:
  /// **'You want the same thing'**
  String get compatStrongestRelationship;

  /// No description provided for @compatStrongestValues.
  ///
  /// In en, this message translates to:
  /// **'You see life in similar ways'**
  String get compatStrongestValues;

  /// No description provided for @compatStrongestQuestions.
  ///
  /// In en, this message translates to:
  /// **'You answered a lot of questions alike'**
  String get compatStrongestQuestions;

  /// No description provided for @compatStrongestMusic.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes have a lot in common'**
  String get compatStrongestMusic;

  /// No description provided for @compatStrongestLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Your lifestyles fit together'**
  String get compatStrongestLifestyle;

  /// No description provided for @compatStrongestInterests.
  ///
  /// In en, this message translates to:
  /// **'You enjoy similar things'**
  String get compatStrongestInterests;

  /// No description provided for @compatStrongestCommunication.
  ///
  /// In en, this message translates to:
  /// **'You communicate in similar ways'**
  String get compatStrongestCommunication;

  /// No description provided for @compatStrongestLanguages.
  ///
  /// In en, this message translates to:
  /// **'You share a language'**
  String get compatStrongestLanguages;

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

  /// No description provided for @previewPhotoBody.
  ///
  /// In en, this message translates to:
  /// **'Your photo is sent end-to-end encrypted.'**
  String get previewPhotoBody;

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
  /// **'We won\'t show them to you again, and you won\'t be able to message or call each other.'**
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

  /// No description provided for @blockFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t block this person. Check your connection and try again.'**
  String get blockFailedMessage;

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

  /// No description provided for @reportChildSafety.
  ///
  /// In en, this message translates to:
  /// **'Child safety concern (sexual content or behaviour involving a minor)'**
  String get reportChildSafety;

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
  /// **'We won\'t show them to you again.'**
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

  /// No description provided for @exportMyDataShareSubject.
  ///
  /// In en, this message translates to:
  /// **'My Mevora data export'**
  String get exportMyDataShareSubject;

  /// No description provided for @exportMyDataShared.
  ///
  /// In en, this message translates to:
  /// **'Your data export was shared.'**
  String get exportMyDataShared;

  /// No description provided for @exportMyDataReady.
  ///
  /// In en, this message translates to:
  /// **'Your data export is ready. Choose an app to save or send it.'**
  String get exportMyDataReady;

  /// No description provided for @exportMyDataShareUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No app on this device can receive the export.'**
  String get exportMyDataShareUnavailable;

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
  /// **'You have a new match'**
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
  /// **'Smart Boost'**
  String get boostTitle;

  /// No description provided for @boostSubtitle.
  ///
  /// In en, this message translates to:
  /// **'While it\'s on, your profile is shown earlier — and a little further out — to people you\'re well matched with.'**
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

  /// Purchase disclosure under the Boost packs: not a subscription.
  ///
  /// In en, this message translates to:
  /// **'Boost is a one-time purchase. It does not renew.'**
  String get boostOneTimePurchaseNote;

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
  /// **'Boost is on'**
  String get boostSuccessTitle;

  /// No description provided for @boostSuccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Boost is on. While it lasts, your profile is shown earlier to people you\'re well matched with.'**
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
  /// **'Back to For You'**
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

  /// A bare percentage. Turkish puts the sign first (%60).
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String percentValue(int value);

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
  /// **'Mevora uses your location to show distance and pick people near you.'**
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

  /// No description provided for @photoNoneSelected.
  ///
  /// In en, this message translates to:
  /// **'No photo selected.'**
  String get photoNoneSelected;

  /// No description provided for @photoNeedSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in to upload a photo.'**
  String get photoNeedSignIn;

  /// No description provided for @photoInvalidFile.
  ///
  /// In en, this message translates to:
  /// **'This photo\'s type or size isn\'t supported.'**
  String get photoInvalidFile;

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

  /// No description provided for @settingsPhotoStillProcessing.
  ///
  /// In en, this message translates to:
  /// **'This photo is still being checked. Try again in a moment.'**
  String get settingsPhotoStillProcessing;

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

  /// No description provided for @settingsLastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required.'**
  String get settingsLastNameRequired;

  /// No description provided for @settingsLastNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'Last name is too long.'**
  String get settingsLastNameTooLong;

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

  /// No description provided for @settingsNoPasswordMessage.
  ///
  /// In en, this message translates to:
  /// **'This account has no password. You sign in with your phone number or a linked account.'**
  String get settingsNoPasswordMessage;

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
  /// **'Picking people for you...'**
  String get discoveryLoading;

  /// No description provided for @discoveryLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your picks'**
  String get discoveryLoadErrorTitle;

  /// No description provided for @discoveryLoadErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get discoveryLoadErrorMessage;

  /// No description provided for @discoveryChangePreferences.
  ///
  /// In en, this message translates to:
  /// **'Change your preferences'**
  String get discoveryChangePreferences;

  /// No description provided for @itsAMatchHeadline.
  ///
  /// In en, this message translates to:
  /// **'New match'**
  String get itsAMatchHeadline;

  /// No description provided for @matchCelebrationLead.
  ///
  /// In en, this message translates to:
  /// **'You chose each other'**
  String get matchCelebrationLead;

  /// No description provided for @matchCelebrationInsight.
  ///
  /// In en, this message translates to:
  /// **'You can start talking now. Here\'s what you have in common.'**
  String get matchCelebrationInsight;

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
  /// **'Connect Spotify'**
  String get musicConnectCta;

  /// No description provided for @musicConnected.
  ///
  /// In en, this message translates to:
  /// **'Spotify connected'**
  String get musicConnected;

  /// No description provided for @musicUnconnectedHeadline.
  ///
  /// In en, this message translates to:
  /// **'Let your music taste be part of your match'**
  String get musicUnconnectedHeadline;

  /// No description provided for @musicUnconnectedCopy.
  ///
  /// In en, this message translates to:
  /// **'Mevora looks at the artists and tracks you love to spot the taste you share with others. It\'s one part of your match — never the whole story.'**
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
  /// **'Spotify isn\'t available right now. Please try again later.'**
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
  /// **'Let your music taste be part of your match. Mevora doesn\'t play music.'**
  String get settingsSpotifySubtitle;

  /// No description provided for @likesYouTitle.
  ///
  /// In en, this message translates to:
  /// **'People who liked you'**
  String get likesYouTitle;

  /// No description provided for @likesYouEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'See why you might be a good match'**
  String get likesYouEntrySubtitle;

  /// No description provided for @likesYouInsightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap to see what you have in common before you decide.'**
  String get likesYouInsightSubtitle;

  /// No description provided for @likesYouCompatibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'{score}% match'**
  String likesYouCompatibilityLabel(int score);

  /// No description provided for @likesYouSeeWhy.
  ///
  /// In en, this message translates to:
  /// **'Why this person?'**
  String get likesYouSeeWhy;

  /// No description provided for @likesYouLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'See who\'s already interested'**
  String get likesYouLockedTitle;

  /// No description provided for @likesYouLockedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 person likes you} other{{count} people like you}}'**
  String likesYouLockedCount(int count);

  /// No description provided for @likesYouLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium to see who liked you and why you might be a good match. Photos and names stay hidden until then.'**
  String get likesYouLockedMessage;

  /// No description provided for @likesYouUnlockCta.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Premium'**
  String get likesYouUnlockCta;

  /// No description provided for @likesYouBlurredHint.
  ///
  /// In en, this message translates to:
  /// **'Each tile is a real person. Premium shows who, and why you fit.'**
  String get likesYouBlurredHint;

  /// No description provided for @likesYouHiddenName.
  ///
  /// In en, this message translates to:
  /// **'Hidden profile'**
  String get likesYouHiddenName;

  /// No description provided for @likesYouHiddenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock to see what you have in common'**
  String get likesYouHiddenSubtitle;

  /// No description provided for @likesYouEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No likes yet'**
  String get likesYouEmptyTitle;

  /// No description provided for @likesYouEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'When someone likes you, you\'ll see them here — with why you might fit.'**
  String get likesYouEmptyMessage;

  /// No description provided for @likesYouLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load likes. Please try again.'**
  String get likesYouLoadError;

  /// No description provided for @relationshipMatchBadge.
  ///
  /// In en, this message translates to:
  /// **'Similar answers'**
  String get relationshipMatchBadge;

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

  /// No description provided for @relationshipMatchesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Answer a few relationship questions to find people who think like you — distance does not matter here.'**
  String get relationshipMatchesEmpty;

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

  /// No description provided for @verificationProcessing.
  ///
  /// In en, this message translates to:
  /// **'We are checking your verification. This usually takes a minute.'**
  String get verificationProcessing;

  /// No description provided for @verificationUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Your verification is being reviewed. We will update this page when it is done.'**
  String get verificationUnderReview;

  /// No description provided for @verificationCheckAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get verificationCheckAgain;

  /// No description provided for @verificationExpired.
  ///
  /// In en, this message translates to:
  /// **'That verification session expired before it was finished. You can start a new one.'**
  String get verificationExpired;

  /// No description provided for @verificationTemporaryError.
  ///
  /// In en, this message translates to:
  /// **'We could not read your verification status just now. Try again in a moment.'**
  String get verificationTemporaryError;

  /// No description provided for @verificationDeclinedDocument.
  ///
  /// In en, this message translates to:
  /// **'We could not read your ID clearly. Try again in good light, with the whole document in frame.'**
  String get verificationDeclinedDocument;

  /// No description provided for @verificationDeclinedLiveness.
  ///
  /// In en, this message translates to:
  /// **'The selfie step did not complete. Try again somewhere well lit, looking straight at the camera.'**
  String get verificationDeclinedLiveness;

  /// No description provided for @verificationDeclinedFaceMatch.
  ///
  /// In en, this message translates to:
  /// **'The selfie did not match the photo on your ID. Try again, or use a different document.'**
  String get verificationDeclinedFaceMatch;

  /// No description provided for @verificationOpensProvider.
  ///
  /// In en, this message translates to:
  /// **'You will be taken to our verification partner to scan your ID and take a selfie, then brought back here.'**
  String get verificationOpensProvider;

  /// No description provided for @whyYouMatch.
  ///
  /// In en, this message translates to:
  /// **'Why they could be right for you'**
  String get whyYouMatch;

  /// No description provided for @compatWhyButton.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get compatWhyButton;

  /// No description provided for @compatDiscoverBadge.
  ///
  /// In en, this message translates to:
  /// **'{percent}% match'**
  String compatDiscoverBadge(int percent);

  /// No description provided for @compatCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating...'**
  String get compatCalculating;

  /// No description provided for @compatUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Match not available yet'**
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
  /// **'Answer a few relationship questions so people — and Mevora — can get to know you. You can edit them anytime.'**
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
  /// **'See what you have in common.'**
  String get questionAnswersMatchedSubtitle;

  /// No description provided for @questionAnswersPremiumRequired.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Premium to see their answers.'**
  String get questionAnswersPremiumRequired;

  /// No description provided for @questionAnswersPremiumLockedAnswer.
  ///
  /// In en, this message translates to:
  /// **'Unlock with Premium to see their answer'**
  String get questionAnswersPremiumLockedAnswer;

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
  /// **'{percent}% match'**
  String compatOverallLabel(int percent);

  /// No description provided for @compatNotEnoughData.
  ///
  /// In en, this message translates to:
  /// **'Not enough to go on yet'**
  String get compatNotEnoughData;

  /// No description provided for @compatStrongestConnection.
  ///
  /// In en, this message translates to:
  /// **'What you share most'**
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
  /// **'You want the same thing'**
  String get compatReasonSameRelationshipGoal;

  /// No description provided for @compatReasonGoalLongTerm.
  ///
  /// In en, this message translates to:
  /// **'You\'re both looking for a long-term relationship'**
  String get compatReasonGoalLongTerm;

  /// No description provided for @compatReasonGoalShortTerm.
  ///
  /// In en, this message translates to:
  /// **'You\'re both looking for something more casual'**
  String get compatReasonGoalShortTerm;

  /// No description provided for @compatReasonGoalFriendship.
  ///
  /// In en, this message translates to:
  /// **'You\'re both here to make new friends'**
  String get compatReasonGoalFriendship;

  /// No description provided for @compatReasonGoalNotSure.
  ///
  /// In en, this message translates to:
  /// **'You\'re both still figuring out what you want'**
  String get compatReasonGoalNotSure;

  /// No description provided for @compatReasonSharedInterests.
  ///
  /// In en, this message translates to:
  /// **'You\'re both into {interests}'**
  String compatReasonSharedInterests(String interests);

  /// No description provided for @compatReasonSomeSharedInterests.
  ///
  /// In en, this message translates to:
  /// **'You share some interests'**
  String get compatReasonSomeSharedInterests;

  /// No description provided for @compatReasonSimilarLifestyle.
  ///
  /// In en, this message translates to:
  /// **'Your lifestyles fit together'**
  String get compatReasonSimilarLifestyle;

  /// No description provided for @compatReasonSameAnswers.
  ///
  /// In en, this message translates to:
  /// **'You answered {aligned} of {shared} questions the same way'**
  String compatReasonSameAnswers(String aligned, String shared);

  /// No description provided for @compatReasonSimilarViews.
  ///
  /// In en, this message translates to:
  /// **'You answered relationship questions in similar ways'**
  String get compatReasonSimilarViews;

  /// No description provided for @compatReasonSimilarMusic.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes have a lot in common'**
  String get compatReasonSimilarMusic;

  /// No description provided for @compatReasonCommunication.
  ///
  /// In en, this message translates to:
  /// **'You communicate in similar ways'**
  String get compatReasonCommunication;

  /// No description provided for @hiddenCompatTitle.
  ///
  /// In en, this message translates to:
  /// **'Someone here thinks a lot like you'**
  String get hiddenCompatTitle;

  /// No description provided for @hiddenCompatMessage.
  ///
  /// In en, this message translates to:
  /// **'They answered {count} questions the same way you did.'**
  String hiddenCompatMessage(int count);

  /// No description provided for @hiddenCompatCompatibility.
  ///
  /// In en, this message translates to:
  /// **'{percent}% match'**
  String hiddenCompatCompatibility(int percent);

  /// No description provided for @hiddenCompatCta.
  ///
  /// In en, this message translates to:
  /// **'See who it is'**
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

  /// No description provided for @supportTicketNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Support request not found'**
  String get supportTicketNotFoundTitle;

  /// No description provided for @supportTicketNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This support request no longer exists or does not belong to your account.'**
  String get supportTicketNotFoundMessage;

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
  /// **'Go to Settings → Account → Delete Account. Confirm the dialog to permanently delete your Mevora account and associated data. This cannot be undone. Logging out alone does not delete your data.'**
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

  /// No description provided for @faqHowMatchQ.
  ///
  /// In en, this message translates to:
  /// **'How does matching work?'**
  String get faqHowMatchQ;

  /// No description provided for @faqHowMatchA.
  ///
  /// In en, this message translates to:
  /// **'Mevora picks people who may be right for you. When you and someone like each other, you match and can chat from the Matches tab.'**
  String get faqHowMatchA;

  /// No description provided for @faqMatchPercentQ.
  ///
  /// In en, this message translates to:
  /// **'What does the match percentage mean?'**
  String get faqMatchPercentQ;

  /// No description provided for @faqMatchPercentA.
  ///
  /// In en, this message translates to:
  /// **'It\'s an estimate of how well you might fit, based on your answers, interests, lifestyle, music taste and other signals. It helps explain why Mevora picked someone for you — it\'s never a guarantee.'**
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
  /// **'Boost and Premium are bought through your app store. Boost is a one-time purchase and does not renew. Premium is a subscription: it renews automatically at the price shown when you buy it until you cancel in your store account, and cancelling stops the next renewal. Refunds follow the store\'s policies unless required otherwise by law.'**
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
  /// **'For legal questions, contact support from Settings or email destek@mevora.com.'**
  String get termsContactBody;

  /// No description provided for @termsEffectiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Effective date'**
  String get termsEffectiveTitle;

  /// No description provided for @termsEffectiveBody.
  ///
  /// In en, this message translates to:
  /// **'These Terms are effective as of October 1, 2026.'**
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
  /// **'Profile details you provide (first name, date of birth, gender, who you want to meet, bio, preferences, relationship answers, humor ratings and photos) are stored in Firebase Firestore and Firebase Storage to display your profile and power matching. Other members see your age, not your date of birth, and your surname stays private.'**
  String get privacyProfileBody;

  /// No description provided for @privacyVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Photo and identity verification'**
  String get privacyVerificationTitle;

  /// No description provided for @privacyVerificationBody.
  ///
  /// In en, this message translates to:
  /// **'To confirm that a profile belongs to a real person, we may ask you for a selfie. It is sent to our verification provider, Didit, which checks that it shows a live person and that it matches your profile photo. We keep the result of that check, not the selfie, which is deleted when the check ends. Identity verification is optional: if you choose it, Didit processes your identity document and selfie directly and Mevora stores only the outcome.'**
  String get privacyVerificationBody;

  /// No description provided for @privacyLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Location data'**
  String get privacyLocationTitle;

  /// No description provided for @privacyLocationBody.
  ///
  /// In en, this message translates to:
  /// **'With your permission, we use your device location to show compatible people near you. Your coordinates are stored on our servers for that purpose and are never shown to other members, who see only your city and an approximate distance.'**
  String get privacyLocationBody;

  /// No description provided for @privacyMessagingTitle.
  ///
  /// In en, this message translates to:
  /// **'Messages and calls'**
  String get privacyMessagingTitle;

  /// No description provided for @privacyMessagingBody.
  ///
  /// In en, this message translates to:
  /// **'Message text, voice notes and images are end-to-end encrypted: they are encrypted on your device and our servers store only the encrypted form, which we cannot read. To deliver them we do store who sent a message to whom, when, its type and whether it was read, as well as call records.'**
  String get privacyMessagingBody;

  /// No description provided for @privacyMatchingTitle.
  ///
  /// In en, this message translates to:
  /// **'Matching and interactions'**
  String get privacyMatchingTitle;

  /// No description provided for @privacyMatchingBody.
  ///
  /// In en, this message translates to:
  /// **'Likes, passes, matches, your answers to daily questions, humor ratings, compatibility signals and interaction history are stored to operate discovery and matches.'**
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
  /// **'We process push notification tokens and, through Firebase Crashlytics and Google Analytics for Firebase, crash reports and usage statistics tied to an app installation, not to your name. Mevora shows no ads and does not use your advertising ID.'**
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
  /// **'We keep data while your account is active. When you delete your account, your profile, photos, messages, likes, answers and purchase records are deleted. Matches you were part of are closed and no longer show your name or photo, and records of safety and moderation actions may be kept where needed to protect members, prevent fraud or meet legal obligations.'**
  String get privacyRetentionBody;

  /// No description provided for @privacySharingTitle.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get privacySharingTitle;

  /// No description provided for @privacySharingBody.
  ///
  /// In en, this message translates to:
  /// **'We do not sell personal data. We share data only with the service providers needed to operate Mevora: Google (Firebase hosting, authentication, notifications, crash reporting and analytics, and Google Play for purchases), Spotify if you connect it, Didit for photo and identity verification, and GIPHY, from which your device loads humor content directly.'**
  String get privacySharingBody;

  /// No description provided for @privacyRightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your rights'**
  String get privacyRightsTitle;

  /// No description provided for @privacyRightsBody.
  ///
  /// In en, this message translates to:
  /// **'Depending on your region, you may request access, correction, deletion, or restriction of your data. You can download a copy of your data in Settings → Account → Download my data, and delete your account in Settings.'**
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
  /// **'We use access controls, encryption in transit, end-to-end encryption of message content, and Firebase security rules. No system is perfectly secure; report issues to support.'**
  String get privacySecurityBody;

  /// No description provided for @privacyChildrenTitle.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get privacyChildrenTitle;

  /// No description provided for @privacyChildrenBody.
  ///
  /// In en, this message translates to:
  /// **'Mevora is not for anyone under 18. Accounts found to belong to someone under 18 are closed.'**
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
  /// **'Privacy questions: destek@mevora.com or create a support request in Settings.'**
  String get privacyContactBody;

  /// No description provided for @musicMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Music match · {percent}%'**
  String musicMatchTitle(int percent);

  /// No description provided for @musicInsightBandHigh.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes have a lot in common.'**
  String get musicInsightBandHigh;

  /// No description provided for @musicInsightBandMid.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes share some clear common ground.'**
  String get musicInsightBandMid;

  /// No description provided for @musicInsightBandLow.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes overlap in places.'**
  String get musicInsightBandLow;

  /// No description provided for @musicInsightSharedTracks.
  ///
  /// In en, this message translates to:
  /// **'You have {count} shared songs.'**
  String musicInsightSharedTracks(int count);

  /// No description provided for @musicInsightSharedArtists.
  ///
  /// In en, this message translates to:
  /// **'You have {count} shared artists.'**
  String musicInsightSharedArtists(int count);

  /// No description provided for @musicInsightSharedPlaylistTracks.
  ///
  /// In en, this message translates to:
  /// **'Your playlists share {count} songs.'**
  String musicInsightSharedPlaylistTracks(int count);

  /// No description provided for @musicInsightSharedRecentTracks.
  ///
  /// In en, this message translates to:
  /// **'You recently listened to {count} of the same songs.'**
  String musicInsightSharedRecentTracks(int count);

  /// No description provided for @musicInsightTopSharedArtist.
  ///
  /// In en, this message translates to:
  /// **'You both listen to {name} a lot.'**
  String musicInsightTopSharedArtist(String name);

  /// No description provided for @musicInsightTopSharedGenres.
  ///
  /// In en, this message translates to:
  /// **'Your tastes overlap most in {genres}.'**
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
  /// **'Songs you both like'**
  String get musicSharedTracksHeading;

  /// No description provided for @musicSharedArtistsHeading.
  ///
  /// In en, this message translates to:
  /// **'Artists you both like'**
  String get musicSharedArtistsHeading;

  /// No description provided for @musicSharedGenresHeading.
  ///
  /// In en, this message translates to:
  /// **'Shared genres'**
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
  /// **'Help us get to know you'**
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

  /// No description provided for @profileHeightPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Select your height'**
  String get profileHeightPlaceholder;

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

  /// No description provided for @profileCompletionHeadline.
  ///
  /// In en, this message translates to:
  /// **'Help us get to know you'**
  String get profileCompletionHeadline;

  /// No description provided for @profileCompletionBody.
  ///
  /// In en, this message translates to:
  /// **'What you add to your profile helps us pick more meaningful people for you.'**
  String get profileCompletionBody;

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
  /// **'German 🇩🇪'**
  String get languageGerman;

  /// No description provided for @languageFrench.
  ///
  /// In en, this message translates to:
  /// **'French 🇫🇷'**
  String get languageFrench;

  /// No description provided for @languageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish 🇪🇸'**
  String get languageSpanish;

  /// No description provided for @languageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian 🇮🇹'**
  String get languageItalian;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian 🇷🇺'**
  String get languageRussian;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic 🌐'**
  String get languageArabic;

  /// No description provided for @languagePersian.
  ///
  /// In en, this message translates to:
  /// **'Persian 🌐'**
  String get languagePersian;

  /// No description provided for @languageKurdish.
  ///
  /// In en, this message translates to:
  /// **'Kurdish 🌐'**
  String get languageKurdish;

  /// No description provided for @languageGreek.
  ///
  /// In en, this message translates to:
  /// **'Greek 🇬🇷'**
  String get languageGreek;

  /// No description provided for @languageDutch.
  ///
  /// In en, this message translates to:
  /// **'Dutch 🇳🇱'**
  String get languageDutch;

  /// No description provided for @languagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese 🇵🇹'**
  String get languagePortuguese;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese 🌐'**
  String get languageChinese;

  /// No description provided for @languageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese 🇯🇵'**
  String get languageJapanese;

  /// No description provided for @languageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean 🇰🇷'**
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

  /// No description provided for @musicPrivacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Spotify data is used only to compute music compatibility and show shared listening on matches. Tokens stay on our servers — never on your device.'**
  String get musicPrivacyNotice;

  /// No description provided for @musicDisconnectCta.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Spotify'**
  String get musicDisconnectCta;

  /// No description provided for @musicDisconnectConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Spotify?'**
  String get musicDisconnectConfirmTitle;

  /// No description provided for @musicDisconnectConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll remove your Spotify link and clear cached music taste. Match music compatibility will stop showing until you reconnect.'**
  String get musicDisconnectConfirmBody;

  /// No description provided for @musicMatchTeaser.
  ///
  /// In en, this message translates to:
  /// **'Your music tastes may overlap. See the details with Premium.'**
  String get musicMatchTeaser;

  /// No description provided for @musicPremiumUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get musicPremiumUnlock;

  /// No description provided for @musicNoCommonTracks.
  ///
  /// In en, this message translates to:
  /// **'No shared songs yet'**
  String get musicNoCommonTracks;

  /// No description provided for @musicRecentlyPlayedHeading.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get musicRecentlyPlayedHeading;

  /// No description provided for @humorLabTitle.
  ///
  /// In en, this message translates to:
  /// **'Humor Lab'**
  String get humorLabTitle;

  /// No description provided for @humorLabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show us what makes you laugh.'**
  String get humorLabSubtitle;

  /// No description provided for @humorLabDiscoverCta.
  ///
  /// In en, this message translates to:
  /// **'Open Humor Lab'**
  String get humorLabDiscoverCta;

  /// No description provided for @humorLoadingFeed.
  ///
  /// In en, this message translates to:
  /// **'Preparing content…'**
  String get humorLoadingFeed;

  /// No description provided for @humorRatingVeryFunny.
  ///
  /// In en, this message translates to:
  /// **'Hilarious'**
  String get humorRatingVeryFunny;

  /// No description provided for @humorRatingFunny.
  ///
  /// In en, this message translates to:
  /// **'Funny'**
  String get humorRatingFunny;

  /// No description provided for @humorRatingNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get humorRatingNeutral;

  /// No description provided for @humorRatingNotFunny.
  ///
  /// In en, this message translates to:
  /// **'Not funny'**
  String get humorRatingNotFunny;

  /// No description provided for @humorRatingNotAtAll.
  ///
  /// In en, this message translates to:
  /// **'Not funny at all'**
  String get humorRatingNotAtAll;

  /// No description provided for @humorProfileBuilding.
  ///
  /// In en, this message translates to:
  /// **'Still learning your humor vibe…'**
  String get humorProfileBuilding;

  /// No description provided for @humorProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Your humor profile'**
  String get humorProfileTitle;

  /// No description provided for @humorEmptyFeed.
  ///
  /// In en, this message translates to:
  /// **'No new content to show right now.'**
  String get humorEmptyFeed;

  /// No description provided for @humorFeedError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load content. Try again.'**
  String get humorFeedError;

  /// No description provided for @humorTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get humorTryAgain;

  /// No description provided for @humorUndoRating.
  ///
  /// In en, this message translates to:
  /// **'Previous item'**
  String get humorUndoRating;

  /// No description provided for @humorCompatibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Humor match'**
  String get humorCompatibilityTitle;

  /// No description provided for @humorChatStarter.
  ///
  /// In en, this message translates to:
  /// **'Seems our humor lines up — what made you laugh today?'**
  String get humorChatStarter;

  /// No description provided for @humorChatStarterSarcasm.
  ///
  /// In en, this message translates to:
  /// **'Looks like we both enjoy a bit of irony — what made you laugh today?'**
  String get humorChatStarterSarcasm;

  /// No description provided for @humorChatStarterAbsurd.
  ///
  /// In en, this message translates to:
  /// **'Seems we both love absurd humor — what\'s the most absurd thing you\'ve seen lately?'**
  String get humorChatStarterAbsurd;

  /// No description provided for @humorChatStarterSilly.
  ///
  /// In en, this message translates to:
  /// **'Looks like we both laugh at silly stuff — what cracked you up last?'**
  String get humorChatStarterSilly;

  /// No description provided for @humorChatStarterRomantic.
  ///
  /// In en, this message translates to:
  /// **'Seems romantic humor works on both of us — what\'s your favorite rom-com?'**
  String get humorChatStarterRomantic;

  /// No description provided for @humorChatStarterDark.
  ///
  /// In en, this message translates to:
  /// **'Looks like we\'re both into dark humor — what\'s the last joke that got you?'**
  String get humorChatStarterDark;

  /// No description provided for @humorChatStarterMeme.
  ///
  /// In en, this message translates to:
  /// **'Looks like we\'re both meme people — what\'s your favorite meme right now?'**
  String get humorChatStarterMeme;

  /// No description provided for @humorChatStarterDry.
  ///
  /// In en, this message translates to:
  /// **'Seems we both like dry humor — what\'s the best deadpan line you know?'**
  String get humorChatStarterDry;

  /// No description provided for @humorChatStarterWordplay.
  ///
  /// In en, this message translates to:
  /// **'Looks like we both love wordplay — got a favorite pun?'**
  String get humorChatStarterWordplay;

  /// No description provided for @humorChatStarterSituational.
  ///
  /// In en, this message translates to:
  /// **'Seems everyday mishaps make us both laugh — what\'s the funniest thing that happened to you lately?'**
  String get humorChatStarterSituational;

  /// No description provided for @humorChatStarterCringe.
  ///
  /// In en, this message translates to:
  /// **'Looks like cringe content gets us both — what\'s the most cringe thing you\'ve seen lately?'**
  String get humorChatStarterCringe;

  /// No description provided for @humorChatStarterTeasing.
  ///
  /// In en, this message translates to:
  /// **'Seems we both enjoy a bit of playful teasing — should I start, or will you?'**
  String get humorChatStarterTeasing;

  /// No description provided for @humorCompatibilityLevelHigh.
  ///
  /// In en, this message translates to:
  /// **'Your sense of humor is very close'**
  String get humorCompatibilityLevelHigh;

  /// No description provided for @humorCompatibilityLevelMedium.
  ///
  /// In en, this message translates to:
  /// **'You laugh at a lot of the same things'**
  String get humorCompatibilityLevelMedium;

  /// No description provided for @humorCompatibilityLevelLow.
  ///
  /// In en, this message translates to:
  /// **'Your humor overlaps in places'**
  String get humorCompatibilityLevelLow;

  /// No description provided for @humorCompatibilityBuilding.
  ///
  /// In en, this message translates to:
  /// **'You\'ll both need to finish your humor profiles to see your humor match.'**
  String get humorCompatibilityBuilding;

  /// No description provided for @humorCompatibilitySharedStyles.
  ///
  /// In en, this message translates to:
  /// **'Humor styles you share'**
  String get humorCompatibilitySharedStyles;

  /// No description provided for @humorCompatibilityNote.
  ///
  /// In en, this message translates to:
  /// **'A light signal from how you each reacted to humor content — not a verdict on the two of you.'**
  String get humorCompatibilityNote;

  /// No description provided for @humorTopVibes.
  ///
  /// In en, this message translates to:
  /// **'Top vibes'**
  String get humorTopVibes;

  /// No description provided for @humorReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get humorReport;

  /// No description provided for @humorReportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Thanks — we\'ll review this content.'**
  String get humorReportSuccess;

  /// No description provided for @humorHowFunny.
  ///
  /// In en, this message translates to:
  /// **'How funny is this?'**
  String get humorHowFunny;

  /// No description provided for @humorReportReasonOffensive.
  ///
  /// In en, this message translates to:
  /// **'Offensive'**
  String get humorReportReasonOffensive;

  /// No description provided for @humorReportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get humorReportReasonSpam;

  /// No description provided for @humorReportReasonMisleading.
  ///
  /// In en, this message translates to:
  /// **'Misleading'**
  String get humorReportReasonMisleading;

  /// No description provided for @humorReportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get humorReportReasonOther;

  /// No description provided for @humorCategorySarcasm.
  ///
  /// In en, this message translates to:
  /// **'Sarcasm'**
  String get humorCategorySarcasm;

  /// No description provided for @humorCategoryAbsurd.
  ///
  /// In en, this message translates to:
  /// **'Absurd'**
  String get humorCategoryAbsurd;

  /// No description provided for @humorCategorySilly.
  ///
  /// In en, this message translates to:
  /// **'Silly'**
  String get humorCategorySilly;

  /// No description provided for @humorCategoryRomantic.
  ///
  /// In en, this message translates to:
  /// **'Romantic'**
  String get humorCategoryRomantic;

  /// No description provided for @humorCategoryDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get humorCategoryDark;

  /// No description provided for @humorCategoryMeme.
  ///
  /// In en, this message translates to:
  /// **'Meme'**
  String get humorCategoryMeme;

  /// No description provided for @humorCategoryDry.
  ///
  /// In en, this message translates to:
  /// **'Dry'**
  String get humorCategoryDry;

  /// No description provided for @humorCategoryWordplay.
  ///
  /// In en, this message translates to:
  /// **'Wordplay'**
  String get humorCategoryWordplay;

  /// No description provided for @humorCategorySituational.
  ///
  /// In en, this message translates to:
  /// **'Situational'**
  String get humorCategorySituational;

  /// No description provided for @humorCategoryCringe.
  ///
  /// In en, this message translates to:
  /// **'Cringe'**
  String get humorCategoryCringe;

  /// No description provided for @humorCategoryTeasing.
  ///
  /// In en, this message translates to:
  /// **'Teasing'**
  String get humorCategoryTeasing;

  /// No description provided for @humorMediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This content can\'t be shown right now.'**
  String get humorMediaUnavailable;

  /// No description provided for @humorVideoLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Video couldn\'t load'**
  String get humorVideoLoadFailed;

  /// No description provided for @humorMediaNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get humorMediaNext;

  /// No description provided for @humorAttributionVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified creator'**
  String get humorAttributionVerified;

  /// No description provided for @boostResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Boost results'**
  String get boostResultsTitle;

  /// No description provided for @boostResultsPending.
  ///
  /// In en, this message translates to:
  /// **'Counting results…'**
  String get boostResultsPending;

  /// No description provided for @boostReachedPeople.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Reached no one yet} =1{Reached 1 person} other{Reached {count} people}}'**
  String boostReachedPeople(int count);

  /// No description provided for @boostLikesReceived.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 likes} =1{1 like} other{{count} likes}}'**
  String boostLikesReceived(int count);

  /// No description provided for @boostMatchesCreated.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 matches} =1{1 match} other{{count} matches}}'**
  String boostMatchesCreated(int count);

  /// No description provided for @boostCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Boost finished'**
  String get boostCompletedTitle;

  /// No description provided for @boostCompletedEmpty.
  ///
  /// In en, this message translates to:
  /// **'This Boost did not reach anyone.'**
  String get boostCompletedEmpty;

  /// No description provided for @boostResultsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Results are not available for this Boost.'**
  String get boostResultsUnavailable;

  /// No description provided for @boostResultsDelayNote.
  ///
  /// In en, this message translates to:
  /// **'Counts can lag a little behind live activity.'**
  String get boostResultsDelayNote;

  /// No description provided for @onboardingMusicTitle.
  ///
  /// In en, this message translates to:
  /// **'Let your music taste be part of your match'**
  String get onboardingMusicTitle;

  /// No description provided for @onboardingMusicBody.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify and Mevora will also look at the artists and tracks you love, then show you the taste you share with someone. Music never decides a match on its own.'**
  String get onboardingMusicBody;

  /// No description provided for @onboardingMusicConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect Spotify'**
  String get onboardingMusicConnect;

  /// No description provided for @onboardingMusicSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get onboardingMusicSkip;

  /// No description provided for @onboardingMusicSkipNote.
  ///
  /// In en, this message translates to:
  /// **'You can connect Spotify later from the Music tab.'**
  String get onboardingMusicSkipNote;

  /// No description provided for @onboardingMusicCancelled.
  ///
  /// In en, this message translates to:
  /// **'Spotify connection was cancelled. You can try again or skip.'**
  String get onboardingMusicCancelled;

  /// No description provided for @publicMusicTitle.
  ///
  /// In en, this message translates to:
  /// **'We picked up your Spotify taste'**
  String get publicMusicTitle;

  /// No description provided for @publicMusicSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what you want to show on your profile.'**
  String get publicMusicSubtitle;

  /// No description provided for @publicMusicArtistsHeading.
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get publicMusicArtistsHeading;

  /// No description provided for @publicMusicTracksHeading.
  ///
  /// In en, this message translates to:
  /// **'Songs'**
  String get publicMusicTracksHeading;

  /// No description provided for @publicMusicArtistCount.
  ///
  /// In en, this message translates to:
  /// **'{count}/{max} artists selected'**
  String publicMusicArtistCount(int count, int max);

  /// No description provided for @publicMusicTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count}/{max} songs selected'**
  String publicMusicTrackCount(int count, int max);

  /// No description provided for @publicMusicLimitReached.
  ///
  /// In en, this message translates to:
  /// **'That is the maximum. Deselect one to choose another.'**
  String get publicMusicLimitReached;

  /// No description provided for @publicMusicSave.
  ///
  /// In en, this message translates to:
  /// **'Add to my profile'**
  String get publicMusicSave;

  /// No description provided for @publicMusicSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t save your selection. Please try again.'**
  String get publicMusicSaveFailed;

  /// No description provided for @publicMusicEmpty.
  ///
  /// In en, this message translates to:
  /// **'Spotify didn\'t return enough listening data yet. Your music is still connected and used for compatibility.'**
  String get publicMusicEmpty;

  /// No description provided for @publicMusicVisibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Show Music Taste on my profile'**
  String get publicMusicVisibilityTitle;

  /// No description provided for @publicMusicVisibilityBody.
  ///
  /// In en, this message translates to:
  /// **'Turn this off to keep your selection private. Spotify stays connected and still improves your matches.'**
  String get publicMusicVisibilityBody;

  /// No description provided for @publicMusicHiddenNotice.
  ///
  /// In en, this message translates to:
  /// **'Your Music Taste is hidden from other people.'**
  String get publicMusicHiddenNotice;

  /// No description provided for @publicMusicEditCta.
  ///
  /// In en, this message translates to:
  /// **'Edit my Music Taste'**
  String get publicMusicEditCta;

  /// No description provided for @profileMusicTasteHeading.
  ///
  /// In en, this message translates to:
  /// **'Music taste'**
  String get profileMusicTasteHeading;

  /// No description provided for @profileMusicOpenInSpotify.
  ///
  /// In en, this message translates to:
  /// **'Open in Spotify'**
  String get profileMusicOpenInSpotify;

  /// No description provided for @musicLimitedData.
  ///
  /// In en, this message translates to:
  /// **'Spotify is connected, but there isn\'t much listening history yet.'**
  String get musicLimitedData;

  /// No description provided for @humorCalibrationIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Let\'s learn what makes you laugh'**
  String get humorCalibrationIntroTitle;

  /// No description provided for @humorCalibrationIntroBody.
  ///
  /// In en, this message translates to:
  /// **'React to a few short pieces. Your reactions help us understand your sense of humor, so we can show you the humor you share with your matches.'**
  String get humorCalibrationIntroBody;

  /// No description provided for @humorCalibrationIntroMeta.
  ///
  /// In en, this message translates to:
  /// **'{count} short pieces · about a minute'**
  String humorCalibrationIntroMeta(int count);

  /// No description provided for @humorCalibrationPausedTitle.
  ///
  /// In en, this message translates to:
  /// **'That\'s it for today'**
  String get humorCalibrationPausedTitle;

  /// No description provided for @humorCalibrationPausedBody.
  ///
  /// In en, this message translates to:
  /// **'One piece would not play. The rest will be waiting tomorrow, and your humor profile will be completed then.'**
  String get humorCalibrationPausedBody;

  /// No description provided for @humorLabCalibratedBody.
  ///
  /// In en, this message translates to:
  /// **'From here on we continue with a few new pieces each day.'**
  String get humorLabCalibratedBody;

  /// No description provided for @humorCalibrationStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get humorCalibrationStart;

  /// No description provided for @humorCalibrationSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get humorCalibrationSkip;

  /// No description provided for @humorCalibrationResume.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get humorCalibrationResume;

  /// No description provided for @humorCalibrationProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} / {total}'**
  String humorCalibrationProgress(int completed, int total);

  /// No description provided for @humorCalibrationHintEarly.
  ///
  /// In en, this message translates to:
  /// **'Getting to know you…'**
  String get humorCalibrationHintEarly;

  /// No description provided for @humorCalibrationHintMiddle.
  ///
  /// In en, this message translates to:
  /// **'Your humor style is taking shape.'**
  String get humorCalibrationHintMiddle;

  /// No description provided for @humorCalibrationHintFinal.
  ///
  /// In en, this message translates to:
  /// **'Just a few more.'**
  String get humorCalibrationHintFinal;

  /// No description provided for @humorCalibrationResumeNote.
  ///
  /// In en, this message translates to:
  /// **'Picking up where you left off.'**
  String get humorCalibrationResumeNote;

  /// No description provided for @humorCalibrationCatalogGap.
  ///
  /// In en, this message translates to:
  /// **'Not enough content right now. Please try again later.'**
  String get humorCalibrationCatalogGap;

  /// No description provided for @humorProfileEntryNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Let\'s learn what makes you laugh'**
  String get humorProfileEntryNotStarted;

  /// No description provided for @humorProfileEntryInProgress.
  ///
  /// In en, this message translates to:
  /// **'{completed} / {total} completed'**
  String humorProfileEntryInProgress(int completed, int total);

  /// No description provided for @humorProfileEntryComplete.
  ///
  /// In en, this message translates to:
  /// **'Your humor profile is ready'**
  String get humorProfileEntryComplete;

  /// No description provided for @humorFeedAllCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'That is all for now. New content will show up here.'**
  String get humorFeedAllCaughtUp;

  /// No description provided for @humorFeedNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content to show right now.'**
  String get humorFeedNoContent;

  /// No description provided for @humorResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Your humor profile is ready'**
  String get humorResultTitle;

  /// No description provided for @humorResultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We got to know you a little. Here is what stands out.'**
  String get humorResultSubtitle;

  /// No description provided for @humorResultSummaryTwo.
  ///
  /// In en, this message translates to:
  /// **'{first} and {second} are what land with you.'**
  String humorResultSummaryTwo(String first, String second);

  /// No description provided for @humorResultSummaryOne.
  ///
  /// In en, this message translates to:
  /// **'{first} in particular is your thing.'**
  String humorResultSummaryOne(String first);

  /// No description provided for @humorResultSummaryNone.
  ///
  /// In en, this message translates to:
  /// **'Your humor style is not clear yet; it will sharpen as you explore.'**
  String get humorResultSummaryNone;

  /// No description provided for @humorResultContrast.
  ///
  /// In en, this message translates to:
  /// **'{weakest} does not do much for you.'**
  String humorResultContrast(String weakest);

  /// No description provided for @humorResultDone.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get humorResultDone;

  /// No description provided for @humorResultEvolvesNote.
  ///
  /// In en, this message translates to:
  /// **'Your profile keeps evolving as you react to new content.'**
  String get humorResultEvolvesNote;

  /// No description provided for @humorResultStrengthHigh.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get humorResultStrengthHigh;

  /// No description provided for @humorResultStrengthMedium.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get humorResultStrengthMedium;

  /// No description provided for @humorResultStrengthLow.
  ///
  /// In en, this message translates to:
  /// **'Slight'**
  String get humorResultStrengthLow;

  /// No description provided for @musicTasteGeneralHeading.
  ///
  /// In en, this message translates to:
  /// **'Generally listens to'**
  String get musicTasteGeneralHeading;

  /// No description provided for @musicTasteDominant.
  ///
  /// In en, this message translates to:
  /// **'Mostly around {genres}.'**
  String musicTasteDominant(String genres);

  /// No description provided for @musicTasteSignature.
  ///
  /// In en, this message translates to:
  /// **'Keeps coming back to {artists}.'**
  String musicTasteSignature(String artists);

  /// No description provided for @musicTasteStable.
  ///
  /// In en, this message translates to:
  /// **'{count} artists that have stayed with them for months.'**
  String musicTasteStable(int count);

  /// No description provided for @humorSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get humorSaved;

  /// No description provided for @premiumTitle.
  ///
  /// In en, this message translates to:
  /// **'Mevora Premium'**
  String get premiumTitle;

  /// Paywall hero subtitle.
  ///
  /// In en, this message translates to:
  /// **'See who likes you, and more.'**
  String get premiumSubtitle;

  /// No description provided for @premiumSubscribeCta.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get premiumSubscribeCta;

  /// No description provided for @premiumRestoreCta.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get premiumRestoreCta;

  /// No description provided for @premiumLoadingPlans.
  ///
  /// In en, this message translates to:
  /// **'Loading plans…'**
  String get premiumLoadingPlans;

  /// No description provided for @premiumUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Premium is not available right now'**
  String get premiumUnavailableTitle;

  /// Shown when the store returned no purchasable plans.
  ///
  /// In en, this message translates to:
  /// **'Plans could not be loaded from the store. Check your connection and try again.'**
  String get premiumUnavailableBody;

  /// No description provided for @premiumPurchasing.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the store…'**
  String get premiumPurchasing;

  /// No description provided for @premiumVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking your purchase…'**
  String get premiumVerifying;

  /// No description provided for @premiumRestoring.
  ///
  /// In en, this message translates to:
  /// **'Restoring…'**
  String get premiumRestoring;

  /// No description provided for @premiumPurchasedTitle.
  ///
  /// In en, this message translates to:
  /// **'You are Premium'**
  String get premiumPurchasedTitle;

  /// No description provided for @premiumPurchasedBody.
  ///
  /// In en, this message translates to:
  /// **'Your subscription is active. Enjoy.'**
  String get premiumPurchasedBody;

  /// No description provided for @premiumCancelled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled.'**
  String get premiumCancelled;

  /// No description provided for @premiumFailed.
  ///
  /// In en, this message translates to:
  /// **'The purchase could not be completed.'**
  String get premiumFailed;

  /// Backend verified the purchase and did not grant Premium. Deliberately vague.
  ///
  /// In en, this message translates to:
  /// **'We could not confirm this purchase.'**
  String get premiumRejected;

  /// No description provided for @premiumNothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'No previous purchase was found for this store account.'**
  String get premiumNothingToRestore;

  /// No description provided for @premiumStoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The store is unavailable on this device.'**
  String get premiumStoreUnavailable;

  /// No description provided for @premiumAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'You already have Premium.'**
  String get premiumAlreadyActive;

  /// No description provided for @premiumRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get premiumRetry;

  /// Auto-renew disclosure required by both stores.
  ///
  /// In en, this message translates to:
  /// **'Renews automatically. Cancel anytime in the store.'**
  String get premiumRenewsLabel;

  /// Billing period shown on a monthly Premium plan, next to the store price.
  ///
  /// In en, this message translates to:
  /// **'Billed monthly'**
  String get premiumPlanBilledMonthly;

  /// Billing period shown on a yearly Premium plan, next to the store price.
  ///
  /// In en, this message translates to:
  /// **'Billed yearly'**
  String get premiumPlanBilledYearly;

  /// Store price with its billing period. The price is the store's own formatted string.
  ///
  /// In en, this message translates to:
  /// **'{price} / month'**
  String premiumPricePerMonth(String price);

  /// Store price with its billing period. The price is the store's own formatted string.
  ///
  /// In en, this message translates to:
  /// **'{price} / year'**
  String premiumPricePerYear(String price);

  /// Auto-renewal disclosure for the selected monthly plan, shown by the Subscribe button.
  ///
  /// In en, this message translates to:
  /// **'Your subscription renews automatically every month at {price} until you cancel.'**
  String premiumRenewalMonthly(String price);

  /// Auto-renewal disclosure for the selected yearly plan, shown by the Subscribe button.
  ///
  /// In en, this message translates to:
  /// **'Your subscription renews automatically every year at {price} until you cancel.'**
  String premiumRenewalYearly(String price);

  /// Auto-renewal disclosure when the store did not say how long the billing period is.
  ///
  /// In en, this message translates to:
  /// **'Your subscription renews automatically at {price} each billing period until you cancel.'**
  String premiumRenewalGeneric(String price);

  /// How to cancel. store is the store's brand name: Google Play or App Store.
  ///
  /// In en, this message translates to:
  /// **'Cancel anytime in {store} > Subscriptions. You keep Premium until the end of the period you paid for.'**
  String premiumCancelHow(String store);

  /// Button for Premium members. Opens the store's own subscription page.
  ///
  /// In en, this message translates to:
  /// **'Manage subscription'**
  String get premiumManageSubscription;

  /// Shown when the store's subscription page could not be opened.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t open {store}. To manage your subscription, go to {store} > Subscriptions.'**
  String premiumManageSubscriptionFailed(String store);

  /// No description provided for @musicFollowedArtistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Artists you follow'**
  String get musicFollowedArtistsTitle;

  /// No description provided for @musicTopArtistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your top artists'**
  String get musicTopArtistsTitle;

  /// No description provided for @musicTopTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Your top tracks'**
  String get musicTopTracksTitle;

  /// No description provided for @musicPlaylistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your playlists'**
  String get musicPlaylistsTitle;

  /// No description provided for @musicFollowedArtistsReconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect Spotify to show the artists you follow.'**
  String get musicFollowedArtistsReconnect;

  /// No description provided for @musicPlaylistTrackCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks'**
  String musicPlaylistTrackCount(int count);

  /// No description provided for @musicSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get musicSectionEmpty;

  /// No description provided for @profileSectionSignals.
  ///
  /// In en, this message translates to:
  /// **'Your compatibility signals'**
  String get profileSectionSignals;

  /// No description provided for @profileSectionTrust.
  ///
  /// In en, this message translates to:
  /// **'Trust & visibility'**
  String get profileSectionTrust;

  /// No description provided for @premiumBenefitsHeading.
  ///
  /// In en, this message translates to:
  /// **'What Premium adds'**
  String get premiumBenefitsHeading;

  /// No description provided for @premiumBenefitLikesTitle.
  ///
  /// In en, this message translates to:
  /// **'See who liked you'**
  String get premiumBenefitLikesTitle;

  /// No description provided for @premiumBenefitLikesBody.
  ///
  /// In en, this message translates to:
  /// **'Everyone who liked you in one list — and why you might fit.'**
  String get premiumBenefitLikesBody;

  /// No description provided for @premiumBenefitMusicTitle.
  ///
  /// In en, this message translates to:
  /// **'Your full music match'**
  String get premiumBenefitMusicTitle;

  /// No description provided for @premiumBenefitMusicBody.
  ///
  /// In en, this message translates to:
  /// **'The songs, artists and genres you share with each match.'**
  String get premiumBenefitMusicBody;

  /// No description provided for @premiumPlansHeading.
  ///
  /// In en, this message translates to:
  /// **'Choose a plan'**
  String get premiumPlansHeading;

  /// No description provided for @chatPreviewEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message'**
  String get chatPreviewEncrypted;

  /// No description provided for @streakTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily streak'**
  String get streakTitle;

  /// No description provided for @streakIndicatorTooltip.
  ///
  /// In en, this message translates to:
  /// **'Your daily streak'**
  String get streakIndicatorTooltip;

  /// No description provided for @streakIndicatorSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Daily streak: 1 day} other{Daily streak: {count} days}}'**
  String streakIndicatorSemantics(int count);

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1-day streak} other{{count}-day streak}}'**
  String streakDays(int count);

  /// No description provided for @streakDetailsBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You came to Mevora today. Come back tomorrow to keep it going.} other{You have come back to Mevora {count} days in a row.}}'**
  String streakDetailsBody(int count);

  /// No description provided for @streakLongest.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Longest streak: 1 day} other{Longest streak: {count} days}}'**
  String streakLongest(int count);

  /// No description provided for @streakTotalDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day on Mevora in total} other{{count} days on Mevora in total}}'**
  String streakTotalDays(int count);

  /// No description provided for @streakLastSevenDays.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get streakLastSevenDays;

  /// No description provided for @streakWeekSemantics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You came back on 1 of the last 7 days} other{You came back on {count} of the last 7 days}}'**
  String streakWeekSemantics(int count);

  /// No description provided for @streakHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'Your streak grows by one on each day you come back to Mevora. Opening the app again on the same day does not add to it.'**
  String get streakHowItWorks;

  /// No description provided for @streakMissedDayNote.
  ///
  /// In en, this message translates to:
  /// **'Skip a day and a new streak begins. Your longest streak always stays on record.'**
  String get streakMissedDayNote;

  /// No description provided for @streakStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your streak has started'**
  String get streakStartedTitle;

  /// No description provided for @streakStartedBody.
  ///
  /// In en, this message translates to:
  /// **'You came to Mevora today. Come back tomorrow to keep it going.'**
  String get streakStartedBody;

  /// No description provided for @streakContinuedBody.
  ///
  /// In en, this message translates to:
  /// **'You kept your streak going today.'**
  String get streakContinuedBody;

  /// No description provided for @streakRestartedTitle.
  ///
  /// In en, this message translates to:
  /// **'A new streak has started'**
  String get streakRestartedTitle;

  /// No description provided for @streakRestartedBody.
  ///
  /// In en, this message translates to:
  /// **'Today is day 1 again. Your longest streak is still on record.'**
  String get streakRestartedBody;

  /// No description provided for @streakPersonalBest.
  ///
  /// In en, this message translates to:
  /// **'New personal best'**
  String get streakPersonalBest;

  /// No description provided for @streakMilestone.
  ///
  /// In en, this message translates to:
  /// **'Milestone'**
  String get streakMilestone;

  /// No description provided for @streakCelebrationDismiss.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get streakCelebrationDismiss;

  /// No description provided for @onboardingSmokingVapeOnly.
  ///
  /// In en, this message translates to:
  /// **'Only e-cigarettes'**
  String get onboardingSmokingVapeOnly;

  /// No description provided for @onboardingSmokingQuitting.
  ///
  /// In en, this message translates to:
  /// **'Trying to quit'**
  String get onboardingSmokingQuitting;

  /// No description provided for @onboardingAlcoholSober.
  ///
  /// In en, this message translates to:
  /// **'I quit drinking'**
  String get onboardingAlcoholSober;

  /// No description provided for @onboardingExerciseAthlete.
  ///
  /// In en, this message translates to:
  /// **'Very active / athlete'**
  String get onboardingExerciseAthlete;

  /// No description provided for @onboardingLifestyleBird.
  ///
  /// In en, this message translates to:
  /// **'Bird'**
  String get onboardingLifestyleBird;

  /// No description provided for @onboardingLifestyleFish.
  ///
  /// In en, this message translates to:
  /// **'Fish'**
  String get onboardingLifestyleFish;

  /// No description provided for @onboardingPetsWant.
  ///
  /// In en, this message translates to:
  /// **'None yet, but I\'d like one'**
  String get onboardingPetsWant;

  /// No description provided for @onboardingPetsAllergic.
  ///
  /// In en, this message translates to:
  /// **'I\'m allergic'**
  String get onboardingPetsAllergic;

  /// No description provided for @onboardingDiet.
  ///
  /// In en, this message translates to:
  /// **'Diet'**
  String get onboardingDiet;

  /// No description provided for @dietOmnivore.
  ///
  /// In en, this message translates to:
  /// **'I eat everything'**
  String get dietOmnivore;

  /// No description provided for @dietVegetarian.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get dietVegetarian;

  /// No description provided for @dietVegan.
  ///
  /// In en, this message translates to:
  /// **'Vegan'**
  String get dietVegan;

  /// No description provided for @dietPescatarian.
  ///
  /// In en, this message translates to:
  /// **'Pescatarian'**
  String get dietPescatarian;

  /// No description provided for @dietHalal.
  ///
  /// In en, this message translates to:
  /// **'Halal'**
  String get dietHalal;

  /// No description provided for @dietGlutenFree.
  ///
  /// In en, this message translates to:
  /// **'Gluten-free'**
  String get dietGlutenFree;

  /// No description provided for @onboardingAboutYouSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional. Answer what you like; it sharpens who we pick for you.'**
  String get onboardingAboutYouSubtitle;

  /// No description provided for @sharedTraitsTitle.
  ///
  /// In en, this message translates to:
  /// **'What you have in common'**
  String get sharedTraitsTitle;

  /// No description provided for @sharedTraitGoal.
  ///
  /// In en, this message translates to:
  /// **'Looking for'**
  String get sharedTraitGoal;

  /// No description provided for @sharedTraitQuestions.
  ///
  /// In en, this message translates to:
  /// **'Relationship questions'**
  String get sharedTraitQuestions;

  /// No description provided for @sharedTraitQuestionsValue.
  ///
  /// In en, this message translates to:
  /// **'Same answer on {aligned} of {shared}'**
  String sharedTraitQuestionsValue(int aligned, int shared);

  /// No description provided for @sharedTraitChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get sharedTraitChildren;

  /// No description provided for @sharedTraitAge.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get sharedTraitAge;

  /// No description provided for @sharedTraitAgeValue.
  ///
  /// In en, this message translates to:
  /// **'{mine} and {theirs}, close in age'**
  String sharedTraitAgeValue(int mine, int theirs);

  /// No description provided for @sharedTraitExpectations.
  ///
  /// In en, this message translates to:
  /// **'Smoking and drinking expectations'**
  String get sharedTraitExpectations;

  /// No description provided for @sharedTraitExpectationsValue.
  ///
  /// In en, this message translates to:
  /// **'You each fit what the other hopes for'**
  String get sharedTraitExpectationsValue;

  /// No description provided for @sharedTraitRhythm.
  ///
  /// In en, this message translates to:
  /// **'Daily rhythm'**
  String get sharedTraitRhythm;

  /// No description provided for @sharedTraitHobbies.
  ///
  /// In en, this message translates to:
  /// **'Hobbies'**
  String get sharedTraitHobbies;

  /// No description provided for @sharedTraitLanguages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get sharedTraitLanguages;

  /// No description provided for @humorDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Humor Round 🎭'**
  String get humorDailyTitle;

  /// No description provided for @humorDailyBody.
  ///
  /// In en, this message translates to:
  /// **'Every day, a few short videos help us get to know you a little better.'**
  String get humorDailyBody;

  /// No description provided for @humorDailySecondary.
  ///
  /// In en, this message translates to:
  /// **'The more we learn what makes you laugh, the better Mevora knows you.'**
  String get humorDailySecondary;

  /// No description provided for @humorDailyMeta.
  ///
  /// In en, this message translates to:
  /// **'{count} short videos'**
  String humorDailyMeta(int count);

  /// No description provided for @humorDailyStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get humorDailyStart;

  /// No description provided for @humorDailyResume.
  ///
  /// In en, this message translates to:
  /// **'Continue · {answered}/{total}'**
  String humorDailyResume(int answered, int total);

  /// No description provided for @humorDailyDone.
  ///
  /// In en, this message translates to:
  /// **'Done for today ✓'**
  String get humorDailyDone;

  /// No description provided for @humorDailyLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get humorDailyLater;

  /// No description provided for @humorDailyStartsTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Your daily humor round starts tomorrow.'**
  String get humorDailyStartsTomorrow;

  /// No description provided for @humorDailyProgress.
  ///
  /// In en, this message translates to:
  /// **'{position}/{total}'**
  String humorDailyProgress(int position, int total);

  /// No description provided for @humorDailyHintStart.
  ///
  /// In en, this message translates to:
  /// **'Today\'s humor round has begun.'**
  String get humorDailyHintStart;

  /// No description provided for @humorDailyHintMiddle.
  ///
  /// In en, this message translates to:
  /// **'Getting to know you a little more 👀'**
  String get humorDailyHintMiddle;

  /// No description provided for @humorDailyHintEnd.
  ///
  /// In en, this message translates to:
  /// **'Almost done.'**
  String get humorDailyHintEnd;

  /// No description provided for @humorDailyCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'All done for today 🎭'**
  String get humorDailyCompletedTitle;

  /// No description provided for @humorDailyCompletedBody.
  ///
  /// In en, this message translates to:
  /// **'Your humor profile just got a little clearer.'**
  String get humorDailyCompletedBody;

  /// No description provided for @humorDailyCompletedTomorrow.
  ///
  /// In en, this message translates to:
  /// **'A new round will be waiting tomorrow.'**
  String get humorDailyCompletedTomorrow;

  /// No description provided for @humorDailySequenceComplete.
  ///
  /// In en, this message translates to:
  /// **'You have been through everything for now. The round continues when new pieces are added.'**
  String get humorDailySequenceComplete;

  /// No description provided for @humorDailyNotReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Today\'s round is being prepared'**
  String get humorDailyNotReadyTitle;

  /// No description provided for @humorDailyNotReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Check back a little later.'**
  String get humorDailyNotReadyBody;

  /// No description provided for @humorDailyLockedBody.
  ///
  /// In en, this message translates to:
  /// **'The daily humor round begins once your humor profile is ready.'**
  String get humorDailyLockedBody;

  /// No description provided for @appOpsMaintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'A short maintenance break'**
  String get appOpsMaintenanceTitle;

  /// No description provided for @appOpsMaintenanceMessage.
  ///
  /// In en, this message translates to:
  /// **'Mevora is briefly down for maintenance. We\'ll be right back.'**
  String get appOpsMaintenanceMessage;

  /// No description provided for @appOpsMaintenanceSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get appOpsMaintenanceSupport;

  /// No description provided for @appOpsMaintenanceAccount.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get appOpsMaintenanceAccount;

  /// No description provided for @appOpsUpdateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Time to update'**
  String get appOpsUpdateRequiredTitle;

  /// No description provided for @appOpsUpdateRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'This version of Mevora is no longer supported. Update the app to keep going.'**
  String get appOpsUpdateRequiredMessage;

  /// No description provided for @appOpsUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get appOpsUpdateAction;

  /// No description provided for @appOpsUpdateFromStore.
  ///
  /// In en, this message translates to:
  /// **'Update Mevora from {store}.'**
  String appOpsUpdateFromStore(String store);

  /// No description provided for @appOpsGenericStore.
  ///
  /// In en, this message translates to:
  /// **'your app store'**
  String get appOpsGenericStore;

  /// No description provided for @appOpsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A new version of Mevora is available.'**
  String get appOpsUpdateAvailable;

  /// No description provided for @appOpsFeatureUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Temporarily unavailable'**
  String get appOpsFeatureUnavailableTitle;

  /// No description provided for @appOpsFeatureUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'This feature is taking a short break. Please check back a little later.'**
  String get appOpsFeatureUnavailableMessage;

  /// No description provided for @appOpsSpotifyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Connecting Spotify is temporarily unavailable. You can connect it later from the Music tab.'**
  String get appOpsSpotifyUnavailable;

  /// No description provided for @supportTicketRepliesTitle.
  ///
  /// In en, this message translates to:
  /// **'Replies'**
  String get supportTicketRepliesTitle;

  /// No description provided for @supportTicketNoRepliesYet.
  ///
  /// In en, this message translates to:
  /// **'No reply yet. Mevora Support will answer you here.'**
  String get supportTicketNoRepliesYet;

  /// No description provided for @supportTicketRepliesError.
  ///
  /// In en, this message translates to:
  /// **'Replies could not be loaded. Try again later.'**
  String get supportTicketRepliesError;

  /// No description provided for @supportTicketDefaultAuthor.
  ///
  /// In en, this message translates to:
  /// **'Mevora Support'**
  String get supportTicketDefaultAuthor;

  /// No description provided for @supportTicketRepliedBadge.
  ///
  /// In en, this message translates to:
  /// **'Support replied'**
  String get supportTicketRepliedBadge;

  /// No description provided for @supportTicketNoComposerHint.
  ///
  /// In en, this message translates to:
  /// **'Want to add something? Send a new request and mention this one.'**
  String get supportTicketNoComposerHint;

  /// No description provided for @accountRestrictedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account restricted'**
  String get accountRestrictedTitle;

  /// No description provided for @accountRestrictedHeadline.
  ///
  /// In en, this message translates to:
  /// **'Your account is restricted'**
  String get accountRestrictedHeadline;

  /// No description provided for @accountRestrictedBody.
  ///
  /// In en, this message translates to:
  /// **'While your account is restricted you can\'t use Discover, matches or chat. You can still see why, appeal the decision, contact support or manage your data.'**
  String get accountRestrictedBody;

  /// No description provided for @accountRestrictedUntil.
  ///
  /// In en, this message translates to:
  /// **'The restriction ends on {date}.'**
  String accountRestrictedUntil(String date);

  /// No description provided for @accountRestrictedOpenEnded.
  ///
  /// In en, this message translates to:
  /// **'The restriction stays in place until our team reviews it.'**
  String get accountRestrictedOpenEnded;

  /// No description provided for @accountRestrictedReleaseNote.
  ///
  /// In en, this message translates to:
  /// **'When the restriction is lifted, you\'ll be taken back to Mevora automatically.'**
  String get accountRestrictedReleaseNote;

  /// No description provided for @accountRestrictedWhy.
  ///
  /// In en, this message translates to:
  /// **'Why is my account restricted?'**
  String get accountRestrictedWhy;

  /// No description provided for @accountRestrictedContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get accountRestrictedContactSupport;

  /// No description provided for @accountRestrictedManageData.
  ///
  /// In en, this message translates to:
  /// **'Your data and account deletion'**
  String get accountRestrictedManageData;

  /// No description provided for @moderationStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Account status'**
  String get moderationStatusTitle;

  /// No description provided for @moderationStatusSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Warnings, restrictions and appeals'**
  String get moderationStatusSettingsSubtitle;

  /// No description provided for @moderationStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Your account is in good standing.'**
  String get moderationStatusActive;

  /// No description provided for @moderationStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Your account is restricted.'**
  String get moderationStatusSuspended;

  /// No description provided for @moderationStatusBanned.
  ///
  /// In en, this message translates to:
  /// **'Your account is closed.'**
  String get moderationStatusBanned;

  /// No description provided for @moderationStatusInactive.
  ///
  /// In en, this message translates to:
  /// **'Your account is not active.'**
  String get moderationStatusInactive;

  /// No description provided for @moderationStatusReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {category}'**
  String moderationStatusReason(String category);

  /// No description provided for @moderationStatusLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Your account status could not be loaded. Pull down to try again.'**
  String get moderationStatusLoadFailed;

  /// No description provided for @moderationDecisionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Decisions about your account'**
  String get moderationDecisionsTitle;

  /// No description provided for @moderationDecisionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no moderation decisions on your account.'**
  String get moderationDecisionsEmpty;

  /// No description provided for @moderationDecisionUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String moderationDecisionUntil(String date);

  /// No description provided for @moderationDecisionReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get moderationDecisionReversed;

  /// No description provided for @moderationTypeWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get moderationTypeWarning;

  /// No description provided for @moderationTypeTemporarySuspension.
  ///
  /// In en, this message translates to:
  /// **'Temporary restriction'**
  String get moderationTypeTemporarySuspension;

  /// No description provided for @moderationTypePermanentBan.
  ///
  /// In en, this message translates to:
  /// **'Account closure'**
  String get moderationTypePermanentBan;

  /// No description provided for @moderationTypePhotoRejected.
  ///
  /// In en, this message translates to:
  /// **'Photo not approved'**
  String get moderationTypePhotoRejected;

  /// No description provided for @moderationTypePhotoRemoved.
  ///
  /// In en, this message translates to:
  /// **'Photo removed'**
  String get moderationTypePhotoRemoved;

  /// No description provided for @moderationTypeRequireReverification.
  ///
  /// In en, this message translates to:
  /// **'Verification needed again'**
  String get moderationTypeRequireReverification;

  /// No description provided for @moderationTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Moderation decision'**
  String get moderationTypeOther;

  /// No description provided for @moderationReasonHarmfulBehavior.
  ///
  /// In en, this message translates to:
  /// **'Harmful or abusive behavior'**
  String get moderationReasonHarmfulBehavior;

  /// No description provided for @moderationReasonScamOrFraud.
  ///
  /// In en, this message translates to:
  /// **'Scams or fraud'**
  String get moderationReasonScamOrFraud;

  /// No description provided for @moderationReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get moderationReasonSpam;

  /// No description provided for @moderationReasonAuthenticity.
  ///
  /// In en, this message translates to:
  /// **'Profile authenticity'**
  String get moderationReasonAuthenticity;

  /// No description provided for @moderationReasonAgeRequirement.
  ///
  /// In en, this message translates to:
  /// **'Age requirement'**
  String get moderationReasonAgeRequirement;

  /// No description provided for @moderationReasonContentRules.
  ///
  /// In en, this message translates to:
  /// **'Content rules'**
  String get moderationReasonContentRules;

  /// No description provided for @moderationReasonPhotoRequirements.
  ///
  /// In en, this message translates to:
  /// **'Photo requirements'**
  String get moderationReasonPhotoRequirements;

  /// No description provided for @moderationReasonWellbeing.
  ///
  /// In en, this message translates to:
  /// **'Safety and wellbeing'**
  String get moderationReasonWellbeing;

  /// No description provided for @moderationReasonGeneral.
  ///
  /// In en, this message translates to:
  /// **'Community guidelines'**
  String get moderationReasonGeneral;

  /// No description provided for @moderationAppealAction.
  ///
  /// In en, this message translates to:
  /// **'Appeal this decision'**
  String get moderationAppealAction;

  /// No description provided for @moderationAppealOpen.
  ///
  /// In en, this message translates to:
  /// **'Appeal received. We\'ll review it and show the result here.'**
  String get moderationAppealOpen;

  /// No description provided for @moderationAppealInReview.
  ///
  /// In en, this message translates to:
  /// **'Your appeal is being reviewed.'**
  String get moderationAppealInReview;

  /// No description provided for @moderationAppealAccepted.
  ///
  /// In en, this message translates to:
  /// **'Appeal accepted'**
  String get moderationAppealAccepted;

  /// No description provided for @moderationAppealRejected.
  ///
  /// In en, this message translates to:
  /// **'Appeal not accepted'**
  String get moderationAppealRejected;

  /// No description provided for @moderationAppealResolved.
  ///
  /// In en, this message translates to:
  /// **'Appeal reviewed'**
  String get moderationAppealResolved;

  /// No description provided for @moderationAppealWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'The 30-day appeal window for this decision has closed.'**
  String get moderationAppealWindowClosed;

  /// No description provided for @moderationAppealSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Tell us why you think this decision is wrong. Someone on our team who did not make the decision will review it.'**
  String get moderationAppealSheetBody;

  /// No description provided for @moderationAppealReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Your appeal'**
  String get moderationAppealReasonLabel;

  /// No description provided for @moderationAppealReasonHint.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters'**
  String get moderationAppealReasonHint;

  /// No description provided for @moderationAppealReasonTooShort.
  ///
  /// In en, this message translates to:
  /// **'Please write at least 10 characters.'**
  String get moderationAppealReasonTooShort;

  /// No description provided for @moderationAppealSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send appeal'**
  String get moderationAppealSubmit;

  /// No description provided for @moderationAppealSent.
  ///
  /// In en, this message translates to:
  /// **'Your appeal was sent. We\'ll show the result here.'**
  String get moderationAppealSent;

  /// No description provided for @moderationAppealAlreadySent.
  ///
  /// In en, this message translates to:
  /// **'You have already appealed this decision.'**
  String get moderationAppealAlreadySent;

  /// No description provided for @moderationAppealNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This decision can\'t be appealed.'**
  String get moderationAppealNotAllowed;

  /// No description provided for @moderationAppealInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please write between 10 and 2,000 characters.'**
  String get moderationAppealInvalid;

  /// No description provided for @moderationAppealFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t send your appeal. Check your connection and try again.'**
  String get moderationAppealFailed;

  /// No description provided for @faceAnchorRequiredNotice.
  ///
  /// In en, this message translates to:
  /// **'To continue, verify one photo where your face is clearly visible.'**
  String get faceAnchorRequiredNotice;

  /// No description provided for @faceAnchorVerifyAction.
  ///
  /// In en, this message translates to:
  /// **'Verify your photo'**
  String get faceAnchorVerifyAction;

  /// No description provided for @faceAnchorVerifyShort.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get faceAnchorVerifyShort;

  /// No description provided for @faceAnchorVerified.
  ///
  /// In en, this message translates to:
  /// **'This photo is verified'**
  String get faceAnchorVerified;

  /// No description provided for @faceAnchorVerifiedShort.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get faceAnchorVerifiedShort;

  /// No description provided for @faceAnchorPending.
  ///
  /// In en, this message translates to:
  /// **'Verification pending'**
  String get faceAnchorPending;

  /// No description provided for @faceAnchorPhotoInReview.
  ///
  /// In en, this message translates to:
  /// **'Photo in review'**
  String get faceAnchorPhotoInReview;

  /// No description provided for @faceAnchorNotVerified.
  ///
  /// In en, this message translates to:
  /// **'Not verified'**
  String get faceAnchorNotVerified;

  /// No description provided for @faceAnchorRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get faceAnchorRetry;

  /// No description provided for @faceAnchorMismatch.
  ///
  /// In en, this message translates to:
  /// **'This photo did not match the selfie you took.'**
  String get faceAnchorMismatch;

  /// No description provided for @faceAnchorLivenessFailed.
  ///
  /// In en, this message translates to:
  /// **'The liveness check could not be completed. Try again in good light, looking straight at the camera.'**
  String get faceAnchorLivenessFailed;

  /// No description provided for @faceAnchorPhotoUnclear.
  ///
  /// In en, this message translates to:
  /// **'Your face is not clearly visible on its own in this photo. Choose one that shows only you.'**
  String get faceAnchorPhotoUnclear;

  /// No description provided for @faceAnchorSelfieInvalid.
  ///
  /// In en, this message translates to:
  /// **'That selfie could not be used. Take a new one with your camera and try again.'**
  String get faceAnchorSelfieInvalid;

  /// No description provided for @faceAnchorTechnicalError.
  ///
  /// In en, this message translates to:
  /// **'Verification could not be completed right now. Your photo was not verified; try again shortly.'**
  String get faceAnchorTechnicalError;

  /// No description provided for @faceAnchorPrimaryRequiresVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify this photo before making it your main photo.'**
  String get faceAnchorPrimaryRequiresVerify;

  /// No description provided for @faceAnchorLastAnchorDelete.
  ///
  /// In en, this message translates to:
  /// **'You can\'t remove your last verified photo. Verify another photo first.'**
  String get faceAnchorLastAnchorDelete;

  /// No description provided for @faceAnchorExplainBody.
  ///
  /// In en, this message translates to:
  /// **'We run a short selfie check to make sure your photo is really you.'**
  String get faceAnchorExplainBody;

  /// No description provided for @faceAnchorExplainSteps.
  ///
  /// In en, this message translates to:
  /// **'You\'ll take a selfie with your front camera. It is used only for this check, never appears on your profile and is deleted when the check ends.'**
  String get faceAnchorExplainSteps;

  /// No description provided for @faceAnchorConsent.
  ///
  /// In en, this message translates to:
  /// **'I agree to my selfie being processed to compare it with this photo.'**
  String get faceAnchorConsent;

  /// No description provided for @faceAnchorTakeSelfie.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie'**
  String get faceAnchorTakeSelfie;

  /// No description provided for @faceAnchorOpening.
  ///
  /// In en, this message translates to:
  /// **'Getting ready…'**
  String get faceAnchorOpening;

  /// No description provided for @faceAnchorCapturing.
  ///
  /// In en, this message translates to:
  /// **'Opening the camera…'**
  String get faceAnchorCapturing;

  /// No description provided for @faceAnchorUploading.
  ///
  /// In en, this message translates to:
  /// **'Sending your selfie…'**
  String get faceAnchorUploading;

  /// No description provided for @faceAnchorVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get faceAnchorVerifying;

  /// No description provided for @faceAnchorSuccessBody.
  ///
  /// In en, this message translates to:
  /// **'This photo can now be your main photo.'**
  String get faceAnchorSuccessBody;

  /// No description provided for @faceAnchorDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get faceAnchorDone;

  /// No description provided for @faceAnchorChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another photo'**
  String get faceAnchorChooseAnother;

  /// No description provided for @faceAnchorPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Verify one photo where your face is clearly visible to show your profile is really you.'**
  String get faceAnchorPromptBody;

  /// No description provided for @faceAnchorProfileVerifiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your profile photo is verified'**
  String get faceAnchorProfileVerifiedTitle;

  /// No description provided for @faceAnchorPromptTileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Verify a photo of your face with a short selfie'**
  String get faceAnchorPromptTileSubtitle;

  /// No description provided for @faceAnchorErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Photo verification isn\'t available right now. Please try again later.'**
  String get faceAnchorErrorUnavailable;

  /// No description provided for @faceAnchorErrorPhotoNotApproved.
  ///
  /// In en, this message translates to:
  /// **'This photo is still in review. You can verify it once the review is finished.'**
  String get faceAnchorErrorPhotoNotApproved;

  /// No description provided for @faceAnchorErrorCooldown.
  ///
  /// In en, this message translates to:
  /// **'Wait a moment and try again.'**
  String get faceAnchorErrorCooldown;

  /// No description provided for @faceAnchorErrorAttemptLimit.
  ///
  /// In en, this message translates to:
  /// **'You\'ve used today\'s attempts. You can try again tomorrow.'**
  String get faceAnchorErrorAttemptLimit;

  /// No description provided for @faceAnchorErrorCamera.
  ///
  /// In en, this message translates to:
  /// **'The camera couldn\'t be opened. Check the camera permission and try again.'**
  String get faceAnchorErrorCamera;

  /// No description provided for @faceAnchorErrorUpload.
  ///
  /// In en, this message translates to:
  /// **'Your selfie couldn\'t be sent. Check your connection and try again.'**
  String get faceAnchorErrorUpload;

  /// No description provided for @faceAnchorErrorInProgress.
  ///
  /// In en, this message translates to:
  /// **'A verification is already running. Please wait for the result.'**
  String get faceAnchorErrorInProgress;

  /// No description provided for @faceAnchorErrorConsent.
  ///
  /// In en, this message translates to:
  /// **'You need to agree before continuing.'**
  String get faceAnchorErrorConsent;

  /// No description provided for @faceAnchorErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Verification couldn\'t be started. Please try again.'**
  String get faceAnchorErrorGeneric;
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
