import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/features/subscription/presentation/widgets/manage_subscription.dart';
import 'package:mevora/features/subscription/presentation/widgets/purchase_legal_links.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_banner.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';
import 'package:mevora/shared/widgets/mevora_selectable_tile.dart';

/// Where Premium is sold.
///
/// Two independent sources feed this screen and they are never conflated:
/// [SubscriptionScope] answers "is this user Premium" (server-written), while
/// [PremiumPurchaseController] answers "how is the current purchase going".
/// When the scope says Premium, the screen stops selling — whatever the
/// controller thinks.
class PaywallPage extends StatefulWidget {
  const PaywallPage({
    super.key,
    required this.controller,
    this.storeLauncher = launchSubscriptionStore,
  });

  final PremiumPurchaseController controller;

  /// Opens the store's subscription page. Injected so a test can capture the
  /// link instead of leaving the app.
  final SubscriptionStoreLauncher storeLauncher;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends State<PaywallPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.loadPlans());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Entitlement, not purchase progress. This is the line that decides
    // whether the user is looking at a paywall at all.
    final status = SubscriptionScope.statusOf(context);
    final isPremium = status.isPremium;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                0,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              children: [
                _Hero(isPremium: isPremium),
                const SizedBox(height: AppSpacing.lg),
                if (isPremium)
                  _AlreadyPremium(
                    l10n: l10n,
                    onManage: () => unawaited(
                      openManageSubscription(
                        context,
                        status: status,
                        launcher: widget.storeLauncher,
                      ),
                    ),
                  )
                else ...[
                  const _Benefits(),
                  const SizedBox(height: AppSpacing.lg),
                  ..._sellingBody(context, l10n),
                ],
                // Terms and Privacy stay reachable in every state, sold or not.
                const SizedBox(height: AppSpacing.sm),
                const PurchaseLegalLinks(),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _sellingBody(BuildContext context, AppLocalizations l10n) {
    final controller = widget.controller;

    switch (controller.stage) {
      case PremiumPurchaseStage.idle:
      case PremiumPurchaseStage.loadingPlans:
        return [_Busy(message: l10n.premiumLoadingPlans)];

      case PremiumPurchaseStage.purchasing:
        return [_Busy(message: l10n.premiumPurchasing)];

      case PremiumPurchaseStage.verifying:
        return [_Busy(message: l10n.premiumVerifying)];

      case PremiumPurchaseStage.restoring:
        return [_Busy(message: l10n.premiumRestoring)];

      case PremiumPurchaseStage.purchased:
        // The store and the backend both said yes, but the entitlement stream
        // has not arrived yet. Confirm the purchase without claiming access —
        // the scope flips the screen over as soon as it lands.
        return [
          _Notice(
            success: true,
            title: l10n.premiumPurchasedTitle,
            body: l10n.premiumPurchasedBody,
          ),
        ];

      case PremiumPurchaseStage.unavailable:
        return [
          _Notice(
            art: MevoraArt.offline,
            title: l10n.premiumUnavailableTitle,
            body: controller.failure == PremiumPurchaseFailure.storeUnavailable
                ? l10n.premiumStoreUnavailable
                : l10n.premiumUnavailableBody,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            label: l10n.premiumRetry,
            onPressed: controller.loadPlans,
          ),
          const SizedBox(height: AppSpacing.sm),
          _RestoreButton(controller: controller, l10n: l10n),
        ];

      case PremiumPurchaseStage.cancelled:
      case PremiumPurchaseStage.failed:
        return [
          _ErrorBanner(text: _failureText(l10n, controller)),
          const SizedBox(height: AppSpacing.md),
          ..._plansAndCta(context, l10n),
        ];

      case PremiumPurchaseStage.ready:
        return _plansAndCta(context, l10n);
    }
  }

  List<Widget> _plansAndCta(BuildContext context, AppLocalizations l10n) {
    final controller = widget.controller;
    return [
      MevoraSectionHeader(title: l10n.premiumPlansHeading),
      const SizedBox(height: AppSpacing.s12),
      for (final plan in controller.plans) ...[
        MevoraSelectableTile(
          title: plan.title,
          // How often the price is charged, then the store's own description.
          subtitle: _planSubtitle(l10n, plan),
          // The store's own formatted price, shown verbatim.
          trailing: plan.formattedPrice,
          selected: controller.selected?.planKey == plan.planKey,
          onTap: () => controller.select(plan),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.md),
      MevoraButton(
        label: l10n.premiumSubscribeCta,
        size: MevoraButtonSize.large,
        onPressed: controller.selected == null ? null : controller.buySelected,
      ),
      const SizedBox(height: AppSpacing.md),
      _RenewalDisclosure(plan: controller.selected),
      const SizedBox(height: AppSpacing.sm),
      _RestoreButton(controller: controller, l10n: l10n),
    ];
  }

  String _planSubtitle(AppLocalizations l10n, PremiumPlan plan) {
    final billed = switch (billingPeriodOf(plan)) {
      PremiumPlanPeriod.monthly => l10n.premiumPlanBilledMonthly,
      PremiumPlanPeriod.yearly => l10n.premiumPlanBilledYearly,
      PremiumPlanPeriod.unknown => null,
    };
    final description = plan.description.trim();
    return [
      billed,
      if (description.isNotEmpty) description,
    ].nonNulls.join('\n');
  }

  String _failureText(
    AppLocalizations l10n,
    PremiumPurchaseController controller,
  ) {
    return switch (controller.failure) {
      PremiumPurchaseFailure.cancelled => l10n.premiumCancelled,
      PremiumPurchaseFailure.storeUnavailable => l10n.premiumStoreUnavailable,
      PremiumPurchaseFailure.productsUnavailable => l10n.premiumUnavailableBody,
      // Deliberately not echoing the backend's reason string. "owned_by_other"
      // would tell one user something about another user's account.
      PremiumPurchaseFailure.verificationRejected =>
        controller.reason == 'nothing_to_restore'
            ? l10n.premiumNothingToRestore
            : l10n.premiumRejected,
      PremiumPurchaseFailure.transient => l10n.premiumFailed,
      PremiumPurchaseFailure.unknown || null => l10n.premiumFailed,
    };
  }
}

/// How often [plan] is billed.
///
/// The store repository only recognises English product names, so a plan whose
/// period it could not read is looked at once more here — base plan id and
/// Turkish store titles included. A plan that still says nothing stays
/// [PremiumPlanPeriod.unknown], and the paywall then names no period rather
/// than guess one.
@visibleForTesting
PremiumPlanPeriod billingPeriodOf(PremiumPlan plan) {
  if (plan.period != PremiumPlanPeriod.unknown) {
    return plan.period;
  }
  final haystack = '${plan.productId} ${plan.basePlanId ?? ''} ${plan.title}'
      .toLowerCase();
  bool has(List<String> needles) => needles.any(haystack.contains);
  if (has(const ['year', 'annual', 'yıllık', 'yillik', '1 yıl', '1 yil'])) {
    return PremiumPlanPeriod.yearly;
  }
  if (has(const ['month', 'aylık', 'aylik', '1 ay'])) {
    return PremiumPlanPeriod.monthly;
  }
  return PremiumPlanPeriod.unknown;
}

/// What the member agrees to by subscribing, next to the button that does it:
/// the price and its period, that it renews until cancelled, and where to
/// cancel. Follows the selected plan, so the sentence always names the price
/// about to be charged.
class _RenewalDisclosure extends StatelessWidget {
  const _RenewalDisclosure({required this.plan});

  final PremiumPlan? plan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = this.plan;
    if (plan == null) {
      // Nothing is selected, so there is no price to name yet.
      return Text(
        l10n.premiumRenewsLabel,
        style: theme.textTheme.bodySmall,
        textAlign: TextAlign.center,
      );
    }
    final cancel = l10n.premiumCancelHow(
      SubscriptionStore.forDevice().brandName,
    );
    final price = plan.formattedPrice;
    final period = billingPeriodOf(plan);
    final priceLine = switch (period) {
      PremiumPlanPeriod.monthly => l10n.premiumPricePerMonth(price),
      PremiumPlanPeriod.yearly => l10n.premiumPricePerYear(price),
      PremiumPlanPeriod.unknown => price,
    };
    final renewal = switch (period) {
      PremiumPlanPeriod.monthly => l10n.premiumRenewalMonthly(price),
      PremiumPlanPeriod.yearly => l10n.premiumRenewalYearly(price),
      PremiumPlanPeriod.unknown => l10n.premiumRenewalGeneric(price),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          priceLine,
          key: const Key('paywallSelectedPrice'),
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$renewal $cancel',
          key: const Key('paywallRenewalDisclosure'),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Premium's promise, on the ink surface with a single brass accent — the
/// one place in Mevora that is allowed to feel a little formal.
class _Hero extends StatelessWidget {
  const _Hero({required this.isPremium});

  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: p.premiumSurface,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.premium, width: 1.5),
            ),
            child: Icon(
              isPremium ? MevoraIcons.premiumActive : MevoraIcons.premium,
              color: p.premium,
              size: 26,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            header: true,
            child: Text(
              l10n.premiumTitle,
              style: theme.textTheme.displaySmall?.copyWith(
                color: p.onPremiumSurface,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.premiumSubtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: p.onPremiumSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// What Premium actually unlocks — only features the backend gates.
class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget benefit(IconData icon, MevoraTone tone, String title, String body) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MevoraIconBadge(icon: icon, tone: tone, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(body, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MevoraSectionHeader(title: l10n.premiumBenefitsHeading),
        const SizedBox(height: AppSpacing.md),
        benefit(
          MevoraIcons.liked,
          MevoraTone.match,
          l10n.premiumBenefitLikesTitle,
          l10n.premiumBenefitLikesBody,
        ),
        benefit(
          MevoraIcons.musicActive,
          MevoraTone.music,
          l10n.premiumBenefitMusicTitle,
          l10n.premiumBenefitMusicBody,
        ),
      ],
    );
  }
}

class _AlreadyPremium extends StatelessWidget {
  const _AlreadyPremium({required this.l10n, required this.onManage});

  final AppLocalizations l10n;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(
          success: true,
          title: l10n.premiumAlreadyActive,
          body: l10n.premiumRenewsLabel,
        ),
        // The store owns billing: changing or cancelling the plan happens
        // there, and this is the way in.
        MevoraButton(
          key: const Key('paywallManageSubscription'),
          label: l10n.premiumManageSubscription,
          variant: MevoraButtonVariant.secondary,
          onPressed: onManage,
        ),
      ],
    );
  }
}

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.controller, required this.l10n});

  final PremiumPurchaseController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return MevoraButton(
      label: l10n.premiumRestoreCta,
      variant: MevoraButtonVariant.ghost,
      onPressed: controller.isBusy ? null : controller.restore,
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: MevoraLoading(message: message),
    );
  }
}

/// A resolved state: a success mark for "you are Premium", a spot
/// illustration for everything else.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.title,
    required this.body,
    this.art = MevoraArt.premium,
    this.success = false,
  });

  final String title;
  final String body;
  final MevoraArt art;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!success) {
      return MevoraEmptyState(
        art: art,
        compact: true,
        title: title,
        message: body,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          MevoraSuccessMark(size: 96, color: context.palette.premium),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return MevoraBanner(message: text, tone: MevoraTone.error);
  }
}
