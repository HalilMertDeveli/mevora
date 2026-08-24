import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';
import 'package:mevora/l10n/app_localizations_en.dart';

void main() {
  test('unauthenticated users can open public legal routes', () {
    for (final route in [
      AppRoutes.legalTerms,
      AppRoutes.legalPrivacy,
      AppRoutes.legalGuidelines,
    ]) {
      expect(
        AuthRedirector.redirect(
          status: const Unauthenticated(),
          location: route,
        ),
        isNull,
      );
    }
  });

  test('support content exposes FAQ and legal sections', () {
    final l10n = AppLocalizationsEn();
    expect(SupportContent.faqEntries(l10n), isNotEmpty);
    expect(SupportContent.communityGuidelines(l10n).length, greaterThan(5));
    expect(SupportContent.termsOfService(l10n).length, greaterThan(5));
    expect(SupportContent.privacyPolicy(l10n).length, greaterThan(5));
  });
}
