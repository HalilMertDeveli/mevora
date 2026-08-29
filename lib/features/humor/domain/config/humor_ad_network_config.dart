/// Environment-safe AdMob / interstitial unit IDs for Humor Lab.
///
/// Non-production always uses Google sample (test) IDs.
/// Production IDs come only from `--dart-define` (never hard-coded secrets).
class HumorAdNetworkConfig {
  const HumorAdNetworkConfig({
    required this.useTestIds,
    required this.androidAppId,
    required this.iosAppId,
    required this.androidInterstitialUnitId,
    required this.iosInterstitialUnitId,
  });

  final bool useTestIds;
  final String androidAppId;
  final String iosAppId;
  final String androidInterstitialUnitId;
  final String iosInterstitialUnitId;

  /// Google sample AdMob app / interstitial IDs (safe for debug/QA).
  static const String googleTestAndroidAppId =
      'ca-app-pub-3940256099942544~3347511713';
  static const String googleTestIosAppId =
      'ca-app-pub-3940256099942544~1458002511';
  static const String googleTestAndroidInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String googleTestIosInterstitial =
      'ca-app-pub-3940256099942544/4411468910';

  static HumorAdNetworkConfig resolve({
    required bool isProduction,
    String androidAppIdDefine = const String.fromEnvironment(
      'ADMOB_ANDROID_APP_ID',
      defaultValue: '',
    ),
    String iosAppIdDefine = const String.fromEnvironment(
      'ADMOB_IOS_APP_ID',
      defaultValue: '',
    ),
    String androidUnitDefine = const String.fromEnvironment(
      'ADMOB_INTERSTITIAL_ANDROID',
      defaultValue: '',
    ),
    String iosUnitDefine = const String.fromEnvironment(
      'ADMOB_INTERSTITIAL_IOS',
      defaultValue: '',
    ),
    bool forceTestAds = const bool.fromEnvironment(
      'ADMOB_USE_TEST_ADS',
      defaultValue: false,
    ),
  }) {
    final useTest = forceTestAds || !isProduction;
    if (useTest) {
      return const HumorAdNetworkConfig(
        useTestIds: true,
        androidAppId: googleTestAndroidAppId,
        iosAppId: googleTestIosAppId,
        androidInterstitialUnitId: googleTestAndroidInterstitial,
        iosInterstitialUnitId: googleTestIosInterstitial,
      );
    }
    return HumorAdNetworkConfig(
      useTestIds: false,
      androidAppId: androidAppIdDefine.trim().isEmpty
          ? googleTestAndroidAppId
          : androidAppIdDefine.trim(),
      iosAppId:
          iosAppIdDefine.trim().isEmpty ? googleTestIosAppId : iosAppIdDefine.trim(),
      androidInterstitialUnitId: androidUnitDefine.trim().isEmpty
          ? googleTestAndroidInterstitial
          : androidUnitDefine.trim(),
      iosInterstitialUnitId: iosUnitDefine.trim().isEmpty
          ? googleTestIosInterstitial
          : iosUnitDefine.trim(),
    );
  }

  String interstitialUnitId({required bool isAndroid}) =>
      isAndroid ? androidInterstitialUnitId : iosInterstitialUnitId;

  bool get hasProductionUnitConfigured {
    if (useTestIds) return false;
    return androidInterstitialUnitId != googleTestAndroidInterstitial ||
        iosInterstitialUnitId != googleTestIosInterstitial;
  }

  bool get hasProductionAppIdConfigured {
    if (useTestIds) return false;
    return androidAppId != googleTestAndroidAppId ||
        iosAppId != googleTestIosAppId;
  }
}
