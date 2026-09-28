import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/features/subscription/presentation/controllers/premium_purchase_controller.dart';
import 'package:mevora/features/subscription/presentation/pages/paywall_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Builds the paywall's controller from whatever billing the app was wired
/// with, and owns its lifetime.
///
/// When Premium is switched off there is no billing to hand it, so the route
/// says Premium is unavailable rather than constructing a paywall that could
/// only fail. That is the same answer the store gives for an unconfigured
/// build, which keeps one code path for "nothing to sell here".
class PaywallRoute extends StatefulWidget {
  const PaywallRoute({super.key});

  @override
  State<PaywallRoute> createState() => _PaywallRouteState();
}

class _PaywallRouteState extends State<PaywallRoute> {
  PremiumPurchaseController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) {
      return;
    }
    final billing = SubscriptionScope.billingOf(context);
    if (billing != null) {
      _controller = PremiumPurchaseController(
        billing: billing,
        analytics: SubscriptionScope.maybeOf(context)?.analytics,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const _PremiumOffPage();
    }
    return PaywallPage(controller: controller);
  }
}

class _PremiumOffPage extends StatelessWidget {
  const _PremiumOffPage();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.premiumTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                MevoraIcons.store,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.premiumUnavailableTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.premiumUnavailableBody,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
