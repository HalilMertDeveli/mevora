import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Reason picker for reporting humor content.
class HumorReportSheet {
  HumorReportSheet._();

  static Future<String?> show(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final reasons = <(String, String)>[
          ('offensive', l10n.humorReportReasonOffensive),
          ('spam', l10n.humorReportReasonSpam),
          ('misleading', l10n.humorReportReasonMisleading),
          ('other', l10n.humorReportReasonOther),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.humorReport,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final entry in reasons)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.$2),
                    onTap: () => Navigator.of(context).pop(entry.$1),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
