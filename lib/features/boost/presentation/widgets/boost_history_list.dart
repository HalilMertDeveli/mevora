import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
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
    final pack = _packLabel(l10n, entry.productId);
    final platform = switch (entry.platform) {
      'ios' => l10n.boostHistoryPlatformIos,
      'android' => l10n.boostHistoryPlatformAndroid,
      _ => null,
    };
    final date = DateFormat.yMMMd(l10n.localeName).format(entry.createdAt);
    final status = entry.status ?? '';
    final subtitle = [
      pack,
      date,
      if (platform != null) platform,
      if (status.isNotEmpty) status,
    ].join(' · ');
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

  String _packLabel(AppLocalizations l10n, String productId) {
    return switch (productId) {
      BoostPackCatalog.week => l10n.boostPackWeek,
      BoostPackCatalog.month => l10n.boostPackMonth,
      BoostPackCatalog.year => l10n.boostPackYear,
      BoostPackCatalog.pack5 => l10n.boostPackFive,
      BoostPackCatalog.pack10 => l10n.boostPackTen,
      _ => l10n.boostPackOne,
    };
  }
}
