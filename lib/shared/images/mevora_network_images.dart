import 'package:flutter/painting.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Safe photo helpers. Never hands unknown `mock://` or other non-http
/// schemes to [NetworkImage] (unsupported URI resolution causes UI jank).
abstract final class MevoraNetworkImages {
  static bool isHttpUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  /// Bundled asset, known demo portrait, or http(s) [ImageProvider].
  static ImageProvider? provider(String? url) {
    final asset = MevoraPhotoImages.assetPath(url);
    if (asset != null) {
      return AssetImage(asset);
    }
    if (!isHttpUrl(url)) {
      return null;
    }
    return NetworkImage(url!);
  }
}
