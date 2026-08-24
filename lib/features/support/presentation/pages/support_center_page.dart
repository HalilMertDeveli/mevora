import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/settings/presentation/widgets/settings_section.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';
import 'package:mevora/l10n/app_localizations.dart';

class SupportCenterPage extends StatelessWidget {
  const SupportCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportCenterTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Text(
            l10n.supportCenterSubtitle,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsSection(
            title: l10n.supportHelpSection,
            children: [
              SettingsNavTile(
                title: l10n.supportFaqTitle,
                subtitle: l10n.supportFaqSubtitle,
                onTap: () => context.push(AppRoutes.supportFaq),
              ),
              SettingsNavTile(
                title: l10n.supportCreateTicket,
                subtitle: l10n.supportCreateTicketSubtitle,
                onTap: () => context.push(AppRoutes.supportTicketCreate),
              ),
              SettingsNavTile(
                title: l10n.supportMyTickets,
                onTap: () => context.push(AppRoutes.supportTickets),
              ),
            ],
          ),
          SettingsSection(
            title: l10n.supportTopicsSection,
            children: [
              for (final category in const [
                'account',
                'matches',
                'messaging',
                'photos',
                'safety',
                'technical',
              ])
                SettingsNavTile(
                  title: SupportContent.faqCategoryLabel(l10n, category),
                  onTap: () => context.push(
                    '${AppRoutes.supportFaq}?category=$category',
                  ),
                ),
            ],
          ),
          SettingsSection(
            title: l10n.settingsSupport,
            children: [
              SettingsNavTile(
                title: l10n.communityGuidelines,
                onTap: () => context.push(AppRoutes.communityGuidelines),
              ),
              SettingsNavTile(
                title: l10n.termsOfService,
                onTap: () => context.push(AppRoutes.termsOfService),
              ),
              SettingsNavTile(
                title: l10n.privacyPolicy,
                onTap: () => context.push(AppRoutes.privacyPolicy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
