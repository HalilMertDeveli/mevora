import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMP consent gate for Humor Lab AdMob requests.
///
/// Does not fake consent. If gathering fails, [canRequestAds] decides whether
/// ad requests are allowed. Humor Lab soft-fails when ads cannot be requested.
class HumorAdConsent {
  HumorAdConsent({ConsentInformation? information})
      : _information = information ?? ConsentInformation.instance;

  final ConsentInformation _information;
  static var _gathered = false;

  /// Returns whether ads may be requested after consent steps.
  Future<bool> ensureReady({bool debugGeographyEea = false}) async {
    if (_gathered) {
      return _information.canRequestAds();
    }

    final updateDone = Completer<void>();
    _information.requestConsentInfoUpdate(
      ConsentRequestParameters(
        consentDebugSettings: debugGeographyEea
            ? ConsentDebugSettings(
                debugGeography: DebugGeography.debugGeographyEea,
              )
            : null,
      ),
      () {
        if (!updateDone.isCompleted) updateDone.complete();
      },
      (error) {
        if (!updateDone.isCompleted) updateDone.completeError(error);
      },
    );
    try {
      await updateDone.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      // Soft-fail into canRequestAds().
    }

    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
    } catch (_) {
      // Soft-fail — must not lock Humor Lab.
    }

    _gathered = true;
    return _information.canRequestAds();
  }

  /// Test-only reset of in-process gather flag.
  static void debugResetGathered() {
    _gathered = false;
  }
}
