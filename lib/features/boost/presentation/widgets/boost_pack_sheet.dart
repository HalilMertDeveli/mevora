import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/config/boost_pack_catalog.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

class BoostPackSheet extends StatelessWidget {
  const BoostPackSheet({
    super.key,
    required this.products,
    this.onSelect,
  });

  final List<BoostProduct> products;
  final ValueChanged<BoostProduct>? onSelect;

  static Future<BoostProduct?> show(
    BuildContext context, {
    required List<BoostProduct> products,
  }) {
    return showModalBottomSheet<BoostProduct>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return BoostPackSheet(
          products: products,
          onSelect: (product) => Navigator.of(context).pop(product),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.sm,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.boostBuy,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final product in products)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: BoostPackTile(
                  product: product,
                  onTap: onSelect == null ? null : () => onSelect!(product),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BoostPackTile extends StatelessWidget {
  const BoostPackTile({super.key, required this.product, this.onTap});

  final BoostProduct product;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = boostPackTitle(l10n, product);
    final subtitle = boostPackSubtitle(l10n, product);
    final price = product.displayPrice.isEmpty
        ? l10n.boostPriceUnavailable
        : product.displayPrice;
    final featured = product.featured ||
        product.productId == BoostPackCatalog.year;
    return MevoraCard(
      emphasis: MevoraCardEmphasis.elevated,
      onTap: product.available && onTap != null ? onTap : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (featured)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    l10n.boostBestValue,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                price,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (onTap != null)
                MevoraButton(
                  label: l10n.boostBuyPack,
                  onPressed: product.available ? onTap : null,
                  isExpanded: false,
                  size: MevoraButtonSize.small,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class BoostPackList extends StatelessWidget {
  const BoostPackList({
    super.key,
    required this.products,
    required this.onSelect,
  });

  final List<BoostProduct> products;
  final ValueChanged<BoostProduct> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final product in products)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: BoostPackTile(
              product: product,
              onTap: () => onSelect(product),
            ),
          ),
      ],
    );
  }
}

class BoostBalanceChip extends StatelessWidget {
  const BoostBalanceChip({super.key, required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    if (balance < 1) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        AppLocalizations.of(context).boostBalance(balance),
        style: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

String boostPackTitle(AppLocalizations l10n, BoostProduct product) {
  return switch (product.durationDays) {
    7 => l10n.boostPackWeek,
    30 => l10n.boostPackMonth,
    365 => l10n.boostPackYear,
    _ => switch (product.boostCount) {
      1 => l10n.boostPackOne,
      5 => l10n.boostPackFive,
      10 => l10n.boostPackTen,
      _ when product.boostCount > 0 => l10n.boostPackCount(product.boostCount),
      _ => product.title.isNotEmpty ? product.title : l10n.boostTitle,
    },
  };
}

String boostPackSubtitle(AppLocalizations l10n, BoostProduct product) {
  return switch (product.durationDays) {
    7 => l10n.boostPackWeekSubtitle,
    30 => l10n.boostPackMonthSubtitle,
    365 => l10n.boostPackYearSubtitle,
    _ => l10n.boostDuration,
  };
}
