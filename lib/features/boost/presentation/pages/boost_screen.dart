import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/features/boost/domain/entities/purchase_flow_state.dart';
import 'package:mevora/features/boost/domain/usecases/activate_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_active_boost.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_history.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_product.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_products.dart';
import 'package:mevora/features/boost/domain/usecases/get_boost_wallet.dart';
import 'package:mevora/features/boost/domain/usecases/purchase_boost.dart';
import 'package:mevora/features/boost/domain/usecases/verify_boost_purchase.dart';
import 'package:mevora/features/boost/presentation/controllers/purchase_controller.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_active_badge.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_history_list.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_pack_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

String _boostStatusMessage(AppLocalizations l10n, PurchaseViewState state) {
  final kind = state.errorKind;
  if (kind != null) {
    return L10nErrors.purchase(l10n, kind);
  }
  return switch (state.status) {
    PurchaseUiStatus.initial || PurchaseUiStatus.loading =>
      l10n.boostLoadingProduct,
    PurchaseUiStatus.purchasing => l10n.boostPurchasing,
    PurchaseUiStatus.verifying => l10n.boostVerifying,
    PurchaseUiStatus.activating => l10n.boostActivating,
    PurchaseUiStatus.cancelled => l10n.boostPurchaseCancelled,
    PurchaseUiStatus.unavailable => l10n.boostStoreUnavailable,
    PurchaseUiStatus.failed => l10n.boostPurchaseFailed,
    PurchaseUiStatus.credited => l10n.boostCreditedTitle,
    PurchaseUiStatus.success => l10n.boostSuccessTitle,
    PurchaseUiStatus.productLoaded =>
      state.hasActiveBoost ? l10n.boostAlreadyActive : l10n.boostSubtitle,
  };
}

class BoostScreen extends StatefulWidget {
  const BoostScreen({super.key, this.controller});

  final PurchaseController? controller;

  @override
  State<BoostScreen> createState() => _BoostScreenState();
}

class _BoostScreenState extends State<BoostScreen> {
  PurchaseController? _owned;

  PurchaseController? get _controller => widget.controller ?? _owned;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.controller != null || _owned != null) {
      return;
    }
    final scope = BoostScope.maybeOf(context);
    final uid = AuthScope.maybeOf(context)?.user?.id ?? 'local';
    if (scope == null) {
      return;
    }
    _owned = PurchaseController(
      userId: uid,
      getBoostProduct: GetBoostProduct(scope.repository),
      getBoostProducts: GetBoostProducts(scope.repository),
      purchaseBoost: PurchaseBoost(scope.repository),
      verifyBoostPurchase: VerifyBoostPurchase(scope.repository),
      getActiveBoost: GetActiveBoost(scope.repository),
      getBoostWallet: GetBoostWallet(scope.repository),
      getBoostHistory: GetBoostHistory(scope.repository),
      activateBoost: ActivateBoost(scope.repository),
      repository: scope.repository,
      analytics: scope.analytics,
    )..addListener(_onController);
    unawaited(_owned!.load());
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onController);
    if (widget.controller?.state.status == PurchaseUiStatus.initial) {
      unawaited(widget.controller?.load());
    }
  }

  void _onController() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _owned?.removeListener(_onController);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.boostTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: controller == null
            ? MevoraLoading.page(message: l10n.boostLoadingProduct)
            : _body(controller, l10n),
      ),
    );
  }

  Widget _body(PurchaseController controller, AppLocalizations l10n) {
    final state = controller.state;
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      switchInCurve: Curves.easeOut,
      child: switch (state.status) {
        PurchaseUiStatus.initial || PurchaseUiStatus.loading =>
          MevoraLoading.page(message: l10n.boostLoadingProduct),
        PurchaseUiStatus.purchasing => MevoraLoading.page(
          message: l10n.boostPurchasing,
        ),
        PurchaseUiStatus.verifying => MevoraLoading.page(
          message: l10n.boostVerifying,
        ),
        PurchaseUiStatus.activating => MevoraLoading.page(
          message: l10n.boostActivating,
        ),
        PurchaseUiStatus.success => _SuccessView(
          onDone: () => Navigator.of(context).maybePop(),
        ),
        PurchaseUiStatus.cancelled ||
        PurchaseUiStatus.failed ||
        PurchaseUiStatus.unavailable => MevoraErrorView(
          title: l10n.boostTitle,
          message: _boostStatusMessage(l10n, state),
          onRetry: state.status == PurchaseUiStatus.unavailable
              ? () => unawaited(controller.load())
              : () => unawaited(controller.load()),
        ),
        PurchaseUiStatus.credited ||
        PurchaseUiStatus.productLoaded => _ProductView(controller: controller),
      },
    );
  }
}

class _ProductView extends StatelessWidget {
  const _ProductView({required this.controller});

  final PurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final l10n = AppLocalizations.of(context);
    final products = state.products.isNotEmpty
        ? state.products
        : [if (state.product != null) state.product!];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        MevoraCard(
          emphasis: MevoraCardEmphasis.elevated,
          child: Column(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.boostTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.boostSubtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              BoostActiveBadge(boost: state.activeBoost),
              const SizedBox(height: AppSpacing.sm),
              BoostBalanceChip(balance: state.balance),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.boostDuration,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (state.status == PurchaseUiStatus.credited) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.boostCreditedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              if (state.hasActiveBoost) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.boostAlreadyActive,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        MevoraButton(
          label: l10n.boostActivate,
          onPressed: state.canActivate
              ? () => unawaited(controller.activate())
              : null,
        ),
        if (!state.canActivate && !state.hasActiveBoost) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.boostNoBalance,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        BoostPackList(
          products: products,
          onSelect: (product) => unawaited(controller.purchase(product)),
        ),
        const SizedBox(height: AppSpacing.lg),
        BoostHistoryList(entries: state.history),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({this.onDone});

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: AppDurations.medium,
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          children: [
            const Spacer(),
            Text(
              l10n.boostSuccessTitle,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.boostSuccessMessage,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            MevoraButton(
              label: l10n.boostBackToDiscovery,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}
