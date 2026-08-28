import 'package:mevora/features/humor/domain/config/humor_ads_settings.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';

/// Mixed feed entry: humor content or an ad breakpoint.
sealed class HumorFeedEntry {
  const HumorFeedEntry();
}

class HumorContentEntry extends HumorFeedEntry {
  const HumorContentEntry(this.content);
  final HumorContent content;
}

class HumorAdEntry extends HumorFeedEntry {
  const HumorAdEntry({required this.placementId});
  final String placementId;
}

/// Tracks free-user ad eligibility across the Humor Lab session.
class HumorAdPolicyController {
  HumorAdPolicyController({
    HumorAdsSettings settings = HumorAdsSettings.defaults,
  }) : _settings = settings;

  HumorAdsSettings _settings;
  var _contentViewedSinceLastAd = 0;
  var _sessionContentViews = 0;
  var _adsShownInSession = 0;
  DateTime? _lastAdAt;
  var _adInFlight = false;

  HumorAdsSettings get settings => _settings;
  int get contentViewedSinceLastAd => _contentViewedSinceLastAd;
  int get sessionContentViews => _sessionContentViews;
  int get adsShownInSession => _adsShownInSession;

  void updateSettings(HumorAdsSettings settings) {
    _settings = settings;
  }

  void onContentViewed() {
    _contentViewedSinceLastAd += 1;
    _sessionContentViews += 1;
  }

  void resetCounters() {
    _contentViewedSinceLastAd = 0;
    _sessionContentViews = 0;
    _adsShownInSession = 0;
    _lastAdAt = null;
    _adInFlight = false;
  }

  bool get isAdInFlight => _adInFlight;

  bool isEligible({required bool isPremium}) {
    if (_adInFlight) {
      return false;
    }
    return _settings.shouldShowAd(
      isPremium: isPremium,
      contentViewedSinceLastAd: _contentViewedSinceLastAd,
      sessionContentViews: _sessionContentViews,
      adsShownInSession: _adsShownInSession,
      lastAdAt: _lastAdAt,
    );
  }

  void markAdStarted() {
    _adInFlight = true;
  }

  void markAdFinished({required bool completed}) {
    _adInFlight = false;
    if (completed) {
      _contentViewedSinceLastAd = 0;
      _lastAdAt = DateTime.now();
      _adsShownInSession += 1;
    }
  }
}
