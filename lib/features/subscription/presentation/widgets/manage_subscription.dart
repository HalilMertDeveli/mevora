import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] outside the app; true when something handled it.
typedef SubscriptionStoreLauncher = Future<bool> Function(Uri uri);

Future<bool> launchSubscriptionStore(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The store a subscription is managed in. Mevora cannot cancel or change a
/// plan itself — the store owns billing — so the app's job is to name the
/// right place and open it.
enum SubscriptionStore {
  googlePlay('Google Play'),
  appStore('App Store');

  const SubscriptionStore(this.brandName);

  /// A brand name, the same in every language.
  final String brandName;

  /// The store this device buys from.
  static SubscriptionStore forDevice() {
    return defaultTargetPlatform == TargetPlatform.iOS
        ? SubscriptionStore.appStore
        : SubscriptionStore.googlePlay;
  }

  /// The store that holds [status]'s subscription: where it was bought when
  /// the backend recorded that, otherwise this device's store.
  static SubscriptionStore forStatus(PremiumStatus status) {
    return switch (status.platform) {
      'android' => SubscriptionStore.googlePlay,
      'ios' => SubscriptionStore.appStore,
      _ => forDevice(),
    };
  }
}

/// The store page where the member changes or cancels their plan.
///
/// On Google Play, [productId] deep-links to that one subscription; without
/// it Play shows the member's whole subscription list, which still works.
Uri manageSubscriptionUri({
  required SubscriptionStore store,
  required String packageName,
  String? productId,
}) {
  switch (store) {
    case SubscriptionStore.appStore:
      return Uri.https('apps.apple.com', '/account/subscriptions');
    case SubscriptionStore.googlePlay:
      final sku = productId?.trim() ?? '';
      return Uri.https('play.google.com', '/store/account/subscriptions', {
        'package': packageName,
        if (sku.isNotEmpty) 'sku': sku,
      });
  }
}

/// Opens the store's subscription page for [status], or says where to find
/// it when nothing on the device could open the link.
Future<void> openManageSubscription(
  BuildContext context, {
  required PremiumStatus status,
  SubscriptionStoreLauncher launcher = launchSubscriptionStore,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final store = SubscriptionStore.forStatus(status);
  final uri = manageSubscriptionUri(
    store: store,
    packageName:
        AppScope.maybeOf(context)?.config.packageName ??
        AppConstants.packageName,
    productId: status.productId,
  );
  var opened = false;
  try {
    opened = await launcher(uri);
  } on Object {
    opened = false;
  }
  if (!opened) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.premiumManageSubscriptionFailed(store.brandName)),
      ),
    );
  }
}
