import 'package:flutter/widgets.dart';
import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/repositories/humor_repository.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

class HumorScope extends InheritedWidget {
  const HumorScope({
    super.key,
    required this.repository,
    required super.child,
    this.adService,
    this.subscriptionRepository,
    this.adsSettings = HumorAdsSettings.defaults,
  });

  final HumorRepository repository;
  final HumorAdService? adService;
  final SubscriptionRepository? subscriptionRepository;
  final HumorAdsSettings adsSettings;

  static HumorScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<HumorScope>();
    assert(scope != null, 'HumorScope not found');
    return scope!;
  }

  static HumorScope? maybeScopeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<HumorScope>();
  }

  static HumorRepository? maybeOf(BuildContext context) {
    return maybeScopeOf(context)?.repository;
  }

  @override
  bool updateShouldNotify(HumorScope oldWidget) {
    return repository != oldWidget.repository ||
        adService != oldWidget.adService ||
        subscriptionRepository != oldWidget.subscriptionRepository ||
        adsSettings != oldWidget.adsSettings;
  }
}
