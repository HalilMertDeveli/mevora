import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Settings language picker. Language logic lives on [LanguageController].
class LanguageSettingsSection extends StatelessWidget {
  const LanguageSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = LanguageScope.of(context);
    return ListenableBuilder(
      listenable: language,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.language, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            RadioListTile<AppLanguage>(
              title: Text(
                l10n.languageTurkish,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: AppLanguage.turkish,
              groupValue: language.language,
              onChanged: (value) {
                if (value != null) {
                  unawaited(language.setLanguage(value));
                }
              },
            ),
            RadioListTile<AppLanguage>(
              title: Text(
                l10n.languageEnglish,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: AppLanguage.english,
              groupValue: language.language,
              onChanged: (value) {
                if (value != null) {
                  unawaited(language.setLanguage(value));
                }
              },
            ),
          ],
        );
      },
    );
  }
}
