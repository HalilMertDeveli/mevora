import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost_product.dart';
import 'package:mevora/l10n/app_localizations.dart';
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
    final label = switch (product.boostCount) {
      1 => l10n.boostPackOne,
      5 => l10n.boostPackFive,
      10 => l10n.boostPackTen,
      _ => l10n.boostPackCount(product.boostCount),
    };
    final price = product.displayPrice;
    return MevoraCard(
      emphasis: MevoraCardEmphasis.elevated,
      onTap: product.available ? onTap : null,
      child: Row(
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
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  l10n.boostDuration,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (onTap != null)
                Text(
                  l10n.boostBuyPack,
                  style: Theme.of(context).textTheme.labelSmall,
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
