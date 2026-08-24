import 'package:flutter/material.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';
import 'package:mevora/features/support/presentation/pages/legal_document_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

class CommunityGuidelinesPage extends StatelessWidget {
  const CommunityGuidelinesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.communityGuidelines,
      intro: l10n.guidelinesIntro,
      sections: SupportContent.communityGuidelines(l10n),
    );
  }
}

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.termsOfService,
      intro: l10n.termsIntro,
      sections: SupportContent.termsOfService(l10n),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LegalDocumentPage(
      title: l10n.privacyPolicy,
      intro: l10n.privacyIntroBody,
      sections: SupportContent.privacyPolicy(l10n),
    );
  }
}
