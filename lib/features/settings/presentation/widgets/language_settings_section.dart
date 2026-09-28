import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/language_scope.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/settings/presentation/widgets/settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';

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
        Widget option(AppLanguage value, String label) {
          final selected = language.language == value;
          return Semantics(
            inMutuallyExclusiveGroup: true,
            selected: selected,
            child: MevoraListRow(
              title: label,
              showChevron: false,
              trailing: selected
                  ? Icon(
                      MevoraIcons.check,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : SizedBox.square(
                      dimension: 20,
                      child: ColoredBox(color: context.palette.surface),
                    ),
              onTap: selected
                  ? null
                  : () => unawaited(language.setLanguage(value)),
            ),
          );
        }

        return SettingsSection(
          title: l10n.language,
          children: [
            option(AppLanguage.turkish, l10n.languageTurkish),
            option(AppLanguage.english, l10n.languageEnglish),
          ],
        );
      },
    );
  }
}
