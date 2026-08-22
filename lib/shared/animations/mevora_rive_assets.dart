/// Expected `.riv` paths. Missing files fall back to Flutter widgets.
///
/// Mapping follows `assets/rive/Riv-files/` source inventory (see ASSETS.md):
/// cloudy-walk → search/load, yippee → match, look → profile/relationship,
/// interactive character → Spotify/login, girl cursor → chat empty,
/// 2d-girl → splash/empty profiles. Black-cat is intentionally unused (size).
abstract final class MevoraRiveAssets {
  /// Shared loading / discovery search (cloudy-walk).
  static const String loading = 'assets/rive/common/searching.riv';
  static const String success = 'assets/rive/common/success.riv';
  static const String error = 'assets/rive/common/error.riv';
  static const String empty = 'assets/rive/common/empty.riv';
  static const String splash = 'assets/rive/common/splash.riv';

  /// Liquid download / sync graphic — music analysis and Spotify link.
  static const String sync = 'assets/rive/common/loading.riv';

  static const String loginAmbient =
      'assets/rive/authentication/login_ambient.riv';

  static const String onboardingComplete =
      'assets/rive/onboarding/complete.riv';
  static const String photoUpload = 'assets/rive/onboarding/photo_upload.riv';
  static const String locationLocating = 'assets/rive/onboarding/location.riv';

  /// Mutual like celebration (yippee).
  static const String match = 'assets/rive/matching/match.riv';
  static const String emptyProfiles = 'assets/rive/matching/empty_profiles.riv';
  static const String emptyMatches = 'assets/rive/matching/empty_matches.riv';

  static const String chatEmpty = 'assets/rive/chat/empty.riv';

  static const String profileAccent = 'assets/rive/profile/accent.riv';

  static const String callConnecting = loading;

  /// Music taste sync / analysis (liquid download).
  static const String musicAnalyzing = sync;

  /// Spotify OAuth in progress (liquid download).
  static const String spotifyConnecting = sync;

  /// Spotify connect idle accent (interactive character).
  static const String spotifyIdle = loginAmbient;

  /// Relationship-answer overlap result (look character).
  static const String relationshipResult = onboardingComplete;

  /// Profile / account hydrate (look character).
  static const String profileLoading = profileAccent;

  /// Short route / tab micro-accent (never full-screen).
  static const String pageAccent = loading;
}
