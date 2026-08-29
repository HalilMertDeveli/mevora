import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mevora/features/humor/domain/config/humor_ad_network_config.dart';
import 'package:mevora/features/humor/domain/services/humor_ad_service.dart';

/// AdMob interstitial adapter for [HumorAdService].
///
/// Soft-fails on load/show errors so Humor Lab never locks the feed.
/// Interstitials may become skippable after the network's own delay —
/// we do not fake an unskippable overlay on top of AdMob.
class AdMobInterstitialHumorAdService implements HumorAdService {
  AdMobInterstitialHumorAdService({
    HumorAdNetworkConfig? config,
    this.loadTimeout = const Duration(seconds: 12),
  }) : config = config ??
            HumorAdNetworkConfig.resolve(isProduction: false);

  final HumorAdNetworkConfig config;
  final Duration loadTimeout;

  static var _sdkInitialized = false;
  InterstitialAd? _preloaded;
  var _loading = false;

  /// Call once from bootstrap (non-blocking failures are OK).
  static Future<void> ensureSdkInitialized() async {
    if (_sdkInitialized) return;
    try {
      await MobileAds.instance.initialize();
      _sdkInitialized = true;
    } catch (_) {
      _sdkInitialized = false;
    }
  }

  @override
  bool get isAvailable => _sdkInitialized;

  String get _unitId => config.interstitialUnitId(isAndroid: Platform.isAndroid);

  Future<void> preload() async {
    if (!_sdkInitialized || _loading || _preloaded != null) return;
    _loading = true;
    try {
      final completer = Completer<void>();
      await InterstitialAd.load(
        adUnitId: _unitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _preloaded = ad;
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            _preloaded = null;
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
        ),
      );
      await completer.future.timeout(loadTimeout);
    } catch (_) {
      _preloaded = null;
    } finally {
      _loading = false;
    }
  }

  @override
  Future<HumorAdResult> show(
    HumorAdRequest request, {
    BuildContext? hostContext,
  }) async {
    if (request.isPremium) {
      return HumorAdResult.completedOk;
    }
    if (!_sdkInitialized) {
      await ensureSdkInitialized();
    }
    if (!_sdkInitialized) {
      return const HumorAdResult(
        completed: false,
        failed: true,
        errorCode: 'sdk_unavailable',
      );
    }

    InterstitialAd? ad = _preloaded;
    _preloaded = null;
    if (ad == null) {
      final loaded = Completer<InterstitialAd?>();
      try {
        await InterstitialAd.load(
          adUnitId: _unitId,
          request: const AdRequest(),
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: (loadedAd) {
              if (!loaded.isCompleted) loaded.complete(loadedAd);
            },
            onAdFailedToLoad: (error) {
              if (!loaded.isCompleted) loaded.complete(null);
            },
          ),
        );
        ad = await loaded.future.timeout(
          loadTimeout,
          onTimeout: () => null,
        );
      } catch (_) {
        ad = null;
      }
    }

    if (ad == null) {
      return const HumorAdResult(
        completed: false,
        failed: true,
        errorCode: 'load_failed',
      );
    }

    final shown = Completer<HumorAdResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) {},
      onAdDismissedFullScreenContent: (dismissed) {
        dismissed.dispose();
        if (!shown.isCompleted) {
          shown.complete(HumorAdResult.completedOk);
        }
        unawaited(preload());
      },
      onAdFailedToShowFullScreenContent: (failed, error) {
        failed.dispose();
        if (!shown.isCompleted) {
          shown.complete(
            HumorAdResult(
              completed: false,
              failed: true,
              errorCode: 'show_failed',
            ),
          );
        }
        unawaited(preload());
      },
    );

    try {
      await ad.show();
    } catch (_) {
      ad.dispose();
      return const HumorAdResult(
        completed: false,
        failed: true,
        errorCode: 'show_threw',
      );
    }

    return shown.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () {
        ad?.dispose();
        return const HumorAdResult(
          completed: false,
          failed: true,
          errorCode: 'show_timeout',
        );
      },
    );
  }

  void dispose() {
    _preloaded?.dispose();
    _preloaded = null;
  }
}
