import 'package:mevora/l10n/app_localizations.dart';

class LegalSection {
  const LegalSection({required this.title, required this.body});

  final String title;
  final String body;
}

class FaqEntry {
  const FaqEntry({
    required this.categoryId,
    required this.question,
    required this.answer,
  });

  final String categoryId;
  final String question;
  final String answer;
}

class SupportContent {
  static List<LegalSection> communityGuidelines(AppLocalizations l10n) {
    return [
      LegalSection(title: l10n.guidelinesRespectTitle, body: l10n.guidelinesRespectBody),
      LegalSection(title: l10n.guidelinesHarassmentTitle, body: l10n.guidelinesHarassmentBody),
      LegalSection(title: l10n.guidelinesHateTitle, body: l10n.guidelinesHateBody),
      LegalSection(title: l10n.guidelinesThreatsTitle, body: l10n.guidelinesThreatsBody),
      LegalSection(title: l10n.guidelinesSpamTitle, body: l10n.guidelinesSpamBody),
      LegalSection(title: l10n.guidelinesFakeTitle, body: l10n.guidelinesFakeBody),
      LegalSection(title: l10n.guidelinesScamTitle, body: l10n.guidelinesScamBody),
      LegalSection(title: l10n.guidelinesInappropriateTitle, body: l10n.guidelinesInappropriateBody),
      LegalSection(title: l10n.guidelinesSexualTitle, body: l10n.guidelinesSexualBody),
      LegalSection(title: l10n.guidelinesMinorsTitle, body: l10n.guidelinesMinorsBody),
      LegalSection(title: l10n.guidelinesPrivacyTitle, body: l10n.guidelinesPrivacyBody),
      LegalSection(title: l10n.guidelinesMisuseTitle, body: l10n.guidelinesMisuseBody),
      LegalSection(title: l10n.guidelinesReportTitle, body: l10n.guidelinesReportBody),
      LegalSection(title: l10n.guidelinesEnforcementTitle, body: l10n.guidelinesEnforcementBody),
    ];
  }

  static List<LegalSection> termsOfService(AppLocalizations l10n) {
    return [
      LegalSection(title: l10n.termsScopeTitle, body: l10n.termsScopeBody),
      LegalSection(title: l10n.termsAccountTitle, body: l10n.termsAccountBody),
      LegalSection(title: l10n.termsResponsibilitiesTitle, body: l10n.termsResponsibilitiesBody),
      LegalSection(title: l10n.termsContentTitle, body: l10n.termsContentBody),
      LegalSection(title: l10n.termsProhibitedTitle, body: l10n.termsProhibitedBody),
      LegalSection(title: l10n.termsMatchingTitle, body: l10n.termsMatchingBody),
      LegalSection(title: l10n.termsSafetyTitle, body: l10n.termsSafetyBody),
      LegalSection(title: l10n.termsSuspensionTitle, body: l10n.termsSuspensionBody),
      LegalSection(title: l10n.termsDeletionTitle, body: l10n.termsDeletionBody),
      LegalSection(title: l10n.termsPaidTitle, body: l10n.termsPaidBody),
      LegalSection(title: l10n.termsThirdPartyTitle, body: l10n.termsThirdPartyBody),
      LegalSection(title: l10n.termsAvailabilityTitle, body: l10n.termsAvailabilityBody),
      LegalSection(title: l10n.termsLiabilityTitle, body: l10n.termsLiabilityBody),
      LegalSection(title: l10n.termsChangesTitle, body: l10n.termsChangesBody),
      LegalSection(title: l10n.termsContactTitle, body: l10n.termsContactBody),
      LegalSection(title: l10n.termsEffectiveTitle, body: l10n.termsEffectiveBody),
    ];
  }

  static List<LegalSection> privacyPolicy(AppLocalizations l10n) {
    return [
      LegalSection(title: l10n.privacyIntroTitle, body: l10n.privacyIntroBody),
      LegalSection(title: l10n.privacyDataCollectedTitle, body: l10n.privacyDataCollectedBody),
      LegalSection(title: l10n.privacyAuthTitle, body: l10n.privacyAuthBody),
      LegalSection(title: l10n.privacyProfileTitle, body: l10n.privacyProfileBody),
      LegalSection(title: l10n.privacyLocationTitle, body: l10n.privacyLocationBody),
      LegalSection(title: l10n.privacyMessagingTitle, body: l10n.privacyMessagingBody),
      LegalSection(title: l10n.privacyMatchingTitle, body: l10n.privacyMatchingBody),
      LegalSection(title: l10n.privacyPreferencesTitle, body: l10n.privacyPreferencesBody),
      LegalSection(title: l10n.privacySpotifyTitle, body: l10n.privacySpotifyBody),
      LegalSection(title: l10n.privacyDeviceTitle, body: l10n.privacyDeviceBody),
      LegalSection(title: l10n.privacyWhyTitle, body: l10n.privacyWhyBody),
      LegalSection(title: l10n.privacyStorageTitle, body: l10n.privacyStorageBody),
      LegalSection(title: l10n.privacyRetentionTitle, body: l10n.privacyRetentionBody),
      LegalSection(title: l10n.privacySharingTitle, body: l10n.privacySharingBody),
      LegalSection(title: l10n.privacyRightsTitle, body: l10n.privacyRightsBody),
      LegalSection(title: l10n.privacyDeletionTitle, body: l10n.privacyDeletionBody),
      LegalSection(title: l10n.privacySecurityTitle, body: l10n.privacySecurityBody),
      LegalSection(title: l10n.privacyChildrenTitle, body: l10n.privacyChildrenBody),
      LegalSection(title: l10n.privacyChangesTitle, body: l10n.privacyChangesBody),
      LegalSection(title: l10n.privacyContactTitle, body: l10n.privacyContactBody),
    ];
  }

  static List<FaqEntry> faqEntries(AppLocalizations l10n) {
    return [
      FaqEntry(categoryId: 'account', question: l10n.faqDeleteAccountQ, answer: l10n.faqDeleteAccountA),
      FaqEntry(categoryId: 'account', question: l10n.faqChangePhotoQ, answer: l10n.faqChangePhotoA),
      FaqEntry(categoryId: 'account', question: l10n.faqCloseAccountQ, answer: l10n.faqCloseAccountA),
      FaqEntry(categoryId: 'matches', question: l10n.faqHowMatchQ, answer: l10n.faqHowMatchA),
      FaqEntry(categoryId: 'matches', question: l10n.faqMatchPercentQ, answer: l10n.faqMatchPercentA),
      FaqEntry(categoryId: 'messaging', question: l10n.faqCantMessageQ, answer: l10n.faqCantMessageA),
      FaqEntry(categoryId: 'messaging', question: l10n.faqNotificationsQ, answer: l10n.faqNotificationsA),
      FaqEntry(categoryId: 'safety', question: l10n.faqBlockQ, answer: l10n.faqBlockA),
      FaqEntry(categoryId: 'safety', question: l10n.faqReportQ, answer: l10n.faqReportA),
      FaqEntry(categoryId: 'safety', question: l10n.faqStaySafeQ, answer: l10n.faqStaySafeA),
    ];
  }

  static String faqCategoryLabel(AppLocalizations l10n, String categoryId) {
    return switch (categoryId) {
      'account' => l10n.supportCategoryAccount,
      'matches' => l10n.supportCategoryMatches,
      'messaging' => l10n.supportCategoryMessaging,
      'photos' => l10n.supportCategoryPhotos,
      'safety' => l10n.supportCategorySafety,
      'technical' => l10n.supportCategoryTechnical,
      _ => l10n.supportCategoryOther,
    };
  }
}
