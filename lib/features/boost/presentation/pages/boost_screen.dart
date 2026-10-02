import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
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
import 'package:mevora/features/boost/presentation/widgets/boost_results_panel.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_history_list.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_pack_sheet.dart';
import 'package:mevora/features/subscription/presentation/widgets/purchase_legal_links.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

String _boostStatusMessage(AppLocalizations l10n, PurchaseViewState state) {
  final kind = state.errorKind;
  if (kind != null) {
    return L10nErrors.purchase(l10n, kind);
  }
  return switch (state.status) {
    PurchaseUiStatus.initial ||
    PurchaseUiStatus.loading => l10n.boostLoadingProduct,
    PurchaseUiStatus.purchasing => l10n.boostPurchasing,
    PurchaseUiStatus.verifying => l10n.boostVerifying,
    PurchaseUiStatus.activating => l10n.boostActivating,
    PurchaseUiStatus.cancelled => l10n.boostPurchaseCancelled,
    PurchaseUiStatus.unavailable => l10n.boostStoreUnavailable,
    PurchaseUiStatus.failed => l10n.boostPurchaseFailed,
    PurchaseUiStatus.credited => l10n.boostCreditedTitle,
    PurchaseUiStatus.success => l10n.boostSuccessTitle,
    PurchaseUiStatus.productLoaded => l10n.boostSubtitle,
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
      // The page's serif headline names it; the bar only carries back.
      appBar: AppBar(),
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
          onRetry: () => unawaited(controller.load()),
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
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.sm,
        AppSpacing.screenPadding,
        AppSpacing.xl,
      ),
      children: [
        const Center(child: MevoraBoostBurst(size: 112)),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          header: true,
          child: Text(
            l10n.boostTitle,
            style: theme.textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.boostSubtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            BoostActiveBadge(boost: state.activeBoost),
            if (state.balance > 0) BoostBalanceChip(balance: state.balance),
          ],
        ),
        if (state.hasActiveBoost) ...[
          const SizedBox(height: AppSpacing.md),
          MevoraBanner(message: l10n.boostAlreadyActive, tone: MevoraTone.info),
        ],
        if (state.status == PurchaseUiStatus.credited) ...[
          const SizedBox(height: AppSpacing.md),
          MevoraBanner(
            message: l10n.boostCreditedTitle,
            tone: MevoraTone.success,
          ),
        ],
        if (state.activeBoost != null) ...[
          const SizedBox(height: AppSpacing.md),
          BoostResultsPanel(boost: state.activeBoost),
        ] else if (state.finishedBoost != null) ...[
          const SizedBox(height: AppSpacing.md),
          BoostResultsPanel(boost: state.finishedBoost),
        ],
        if (state.canActivate) ...[
          const SizedBox(height: AppSpacing.lg),
          MevoraButton(
            label: l10n.boostActivate,
            icon: MevoraIcons.boostActive,
            size: MevoraButtonSize.large,
            onPressed: () => unawaited(controller.activate()),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        MevoraSectionHeader(title: l10n.boostBuy),
        const SizedBox(height: AppSpacing.s12),
        BoostPackList(
          products: products,
          onSelect: (product) => unawaited(controller.purchase(product)),
        ),
        // Said beside the prices: a pack is paid for once and is not a
        // subscription.
        Text(
          l10n.boostOneTimePurchaseNote,
          key: const Key('boostOneTimePurchaseNote'),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        MevoraButton(
          label: l10n.restorePurchases,
          onPressed: () => unawaited(controller.restore()),
          variant: MevoraButtonVariant.ghost,
        ),
        const PurchaseLegalLinks(),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        children: [
          const Spacer(),
          const MevoraBoostBurst(size: 144),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(
              l10n.boostSuccessTitle,
              style: theme.textTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.boostSuccessMessage,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: context.palette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          MevoraButton(
            label: l10n.boostBackToDiscovery,
            size: MevoraButtonSize.large,
            onPressed: onDone,
          ),
        ],
      ),
    );
  }
}
