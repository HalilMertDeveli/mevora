/// Bundled demo portraits and leftover `mock://` URL mapping.
///
/// Demo decks use Unsplash License portraits under `assets/images/portraits/`
/// so discovery cards show real photos instead of letter placeholders.
abstract final class MevoraPhotoImages {
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

  /// Asset path for bundled portraits or leftover `mock://uid/index` URLs.
  static String? assetPath(String? url) {
    if (url == null || url.isEmpty) {
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
