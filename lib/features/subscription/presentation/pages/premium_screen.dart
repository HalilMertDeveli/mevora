import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/premium_scope.dart';
import 'package:mevora/features/subscription/domain/config/premium_pack_catalog.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Premium paywall — store purchase + server verify → Firestore entitlement.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, this.controller});

  final PremiumPurchaseController? controller;

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumPurchaseController? _owned;
  PremiumPurchaseController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final provided = widget.controller;
    if (provided != null) {
      _controller = provided;
      unawaited(provided.load());
      return;
    }
    final repo = PremiumScope.maybeOf(context)?.purchaseRepository;
    if (repo == null) return;
    final owned = PremiumPurchaseController(repository: repo);
    _owned = owned;
    _controller = owned;
    owned.addListener(_onChanged);
    unawaited(owned.load());
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _owned?.removeListener(_onChanged);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.humorPremiumAdFree)),
      body: controller == null
          ? MevoraLoading.page(message: l10n.humorLoadingFeed)
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    l10n.humorAdInfoPremiumHint,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (controller.state == PremiumPurchaseUiState.loading)
                    const MevoraLoading(),
                  if (controller.state == PremiumPurchaseUiState.unavailable)
                    Text(
                      l10n.humorFeedError,
                      style: theme.textTheme.bodyLarge,
                    ),
                  if (controller.state == PremiumPurchaseUiState.pending)
                    Text(
                      'Purchase pending — Premium unlocks after store confirmation.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  if (controller.state == PremiumPurchaseUiState.success)
                    Text(
                      l10n.humorPremiumActiveBadge,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (controller.errorCode != null &&
                      controller.state == PremiumPurchaseUiState.failed)
                    Text(
                      controller.errorCode!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(
                    label: 'Premium — 1 month',
                    onPressed: controller.state == PremiumPurchaseUiState.purchasing
                        ? null
                        : () => unawaited(controller.buyMonth()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MevoraButton(
                    label: 'Premium — 1 year',
                    onPressed: controller.state == PremiumPurchaseUiState.purchasing
                        ? null
                        : () => unawaited(controller.buyYear()),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () => unawaited(controller.restore()),
                    child: const Text('Restore purchases'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Products: ${PremiumPackCatalog.productIds.join(', ')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
    );
  }
}
