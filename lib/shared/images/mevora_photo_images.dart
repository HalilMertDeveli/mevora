import 'package:flutter/foundation.dart';

/// Demo portraits and the `mock://` URL mapping that goes with them.
///
/// The development demo deck uses Unsplash License portraits under
/// `assets/images/portraits/` so its cards show photos instead of letter
/// placeholders. The files are bundled into the development flavor only
/// (`pubspec.yaml`), and the mapping below answers only where the demo deck
/// itself is allowed.
abstract final class MevoraPhotoImages {
  /// Whether this build carries the demo portraits. Set once at start-up from
  /// the same rule that decides whether the demo deck exists; off until then,
  /// so a build that never says so maps nothing.
  static bool demoPortraitsAvailable = false;

  static const Map<String, String> portraits = {
    'mock-01': 'assets/images/portraits/mock-01.jpg',
    'mock-02': 'assets/images/portraits/mock-02.jpg',
    'mock-03': 'assets/images/portraits/mock-03.jpg',
    'mock-04': 'assets/images/portraits/mock-04.jpg',
    'mock-05': 'assets/images/portraits/mock-05.jpg',
    'mock-06': 'assets/images/portraits/mock-06.jpg',
    'mock-07': 'assets/images/portraits/mock-07.jpg',
    'mock-08': 'assets/images/portraits/mock-08.jpg',
    'mock-09': 'assets/images/portraits/mock-09.jpg',
    'mock-10': 'assets/images/portraits/mock-10.jpg',
  };

  static bool isAssetPath(String? url) =>
      url != null && url.startsWith('assets/');

  static String? portraitForUid(String uid) => portraits[uid];

  /// Asset path for a demo portrait or a `mock://uid/index` URL — null for
  /// everything in a build without the demo deck, where a photo is an http
  /// URL or it is not a photo.
  static String? assetPath(String? url) {
    // The constant comes first so a release build drops the mapping, and the
    // portrait paths with it.
    if (kReleaseMode || !demoPortraitsAvailable || url == null || url.isEmpty) {
      return null;
    }
    if (isAssetPath(url)) {
      return url;
    }
    if (url.startsWith('mock://')) {
      final uid = url.replaceFirst('mock://', '').split('/').first;
      return portraits[uid];
    }
    return null;
  }
}
