import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/boost/domain/entities/boost_history_entry.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

class BoostHistoryList extends StatelessWidget {
  const BoostHistoryList({super.key, required this.entries});

  final List<BoostHistoryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.boostHistoryEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.boostHistoryTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: BoostHistoryTile(entry: entry),
          ),
      ],
    );
  }
}

class BoostHistoryTile extends StatelessWidget {
  const BoostHistoryTile({super.key, required this.entry});

  final BoostHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isPurchase = entry.type == BoostHistoryType.purchase;
    final title = isPurchase
        ? l10n.boostHistoryPurchase
        : l10n.boostHistoryActivation;
    final subtitle = isPurchase
        ? l10n.boostPackCount(entry.boostCount)
        : (entry.status ?? '');
    return MevoraCard(
      child: Row(
        children: [
          Icon(
            isPurchase ? Icons.shopping_bag_outlined : Icons.bolt_rounded,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
