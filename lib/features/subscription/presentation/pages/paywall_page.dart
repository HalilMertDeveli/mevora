import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/features/subscription/domain/entities/premium_plan.dart';
import 'package:mevora/features/subscription/domain/repositories/premium_billing_repository.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Where Premium is sold.
///
/// Two independent sources feed this screen and they are never conflated:
/// [SubscriptionScope] answers "is this user Premium" (server-written), while
/// [PremiumPurchaseController] answers "how is the current purchase going".
/// When the scope says Premium, the screen stops selling — whatever the
/// controller thinks.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, required this.controller});

  final PremiumPurchaseController controller;

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
    final isPremium = SubscriptionScope.isPremiumOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                _Hero(isPremium: isPremium),
                const SizedBox(height: AppSpacing.lg),
                if (isPremium)
                  _AlreadyPremium(l10n: l10n)
                else
                  ..._sellingBody(context, l10n),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _sellingBody(BuildContext context, AppLocalizations l10n) {
    final controller = widget.controller;
    final theme = Theme.of(context);

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
            icon: Icons.check_circle_outline,
            title: l10n.premiumPurchasedTitle,
            body: l10n.premiumPurchasedBody,
            tone: theme.colorScheme.primary,
          ),
        ];

      case PremiumPurchaseStage.unavailable:
        return [
          _Notice(
            icon: Icons.storefront_outlined,
            title: l10n.premiumUnavailableTitle,
            body: controller.failure == PremiumPurchaseFailure.storeUnavailable
                ? l10n.premiumStoreUnavailable
                : l10n.premiumUnavailableBody,
            tone: theme.colorScheme.onSurfaceVariant,
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
      for (final plan in controller.plans) ...[
        _PlanTile(
          plan: plan,
          selected: controller.selected?.planKey == plan.planKey,
          onTap: () => controller.select(plan),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      const SizedBox(height: AppSpacing.md),
      MevoraButton(
        label: l10n.premiumSubscribeCta,
        onPressed: controller.selected == null ? null : controller.buySelected,
      ),
      const SizedBox(height: AppSpacing.sm),
      _RestoreButton(controller: controller, l10n: l10n),
      const SizedBox(height: AppSpacing.md),
      Text(
        l10n.premiumRenewsLabel,
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ];
  }

  String _failureText(
    AppLocalizations l10n,
    PremiumPurchaseController controller,
  ) {
    return switch (controller.failure) {
      PremiumPurchaseFailure.cancelled => l10n.premiumCancelled,
      PremiumPurchaseFailure.storeUnavailable => l10n.premiumStoreUnavailable,
      PremiumPurchaseFailure.productsUnavailable =>
        l10n.premiumUnavailableBody,
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

class _Hero extends StatelessWidget {
  const _Hero({required this.isPremium});

  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Icon(
          isPremium ? Icons.workspace_premium : Icons.workspace_premium_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.premiumTitle,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.premiumSubtitle,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AlreadyPremium extends StatelessWidget {
  const _AlreadyPremium({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.verified_outlined,
      title: l10n.premiumAlreadyActive,
      body: l10n.premiumRenewsLabel,
      tone: Theme.of(context).colorScheme.primary,
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final PremiumPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        selected: selected,
        title: Text(plan.title),
        subtitle: plan.description.isEmpty ? null : Text(plan.description),
        // The store's own formatted price, shown verbatim.
        trailing: Text(
          plan.formattedPrice,
          style: theme.textTheme.titleMedium,
        ),
      ),
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
    return Column(
      children: [
        const MevoraLoading(),
        const SizedBox(height: AppSpacing.sm),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 40, color: tone),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(body, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
