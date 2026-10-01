import 'package:flutter/painting.dart';
import 'package:mevora/core/cache/image_disk_cache.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Safe photo helpers. Never hands unknown `mock://` or other non-http
/// schemes to [NetworkImage] (unsupported URI resolution causes UI jank).
abstract final class MevoraNetworkImages {
  static const _productionStorageHost = 'firebasestorage.googleapis.com';

  /// `http://<host>:<port>` of the Storage emulator, set by the bootstrap
  /// only when the app runs against the Emulator Suite; null otherwise.
  ///
  /// The backend builds published photo URLs for the production host even
  /// under the emulator (photoVariants.ts), so on a device they pointed at a
  /// bucket that does not hold the file and every approved photo was a
  /// placeholder. Path and token are the same on both hosts.
  static String? emulatorStorageOrigin;

  /// [url] as this build can actually fetch it.
  static String? resolve(String? url) {
    final origin = emulatorStorageOrigin;
    if (origin == null || !isStorageDownloadUrl(url)) {
      return url;
    }
    final uri = Uri.parse(url!);
    if (uri.host != _productionStorageHost) {
      return url;
    }
    final target = Uri.parse(origin);
    return uri
        .replace(scheme: target.scheme, host: target.host, port: target.port)
        .toString();
  }

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

  /// A Firebase Storage download URL (production or emulator):
  /// `/v0/b/<bucket>/o/<path>?alt=media&token=…`. Profile photos and their
  /// variants are published this way and never change behind their URL, so
  /// they are safe to keep on disk.
  static bool isStorageDownloadUrl(String? url) {
    if (!isHttpUrl(url)) {
      return false;
    }
    final uri = Uri.parse(url!);
    return uri.path.startsWith('/v0/b/') &&
        uri.path.contains('/o/') &&
        uri.queryParameters['alt'] == 'media';
  }

  /// Bundled asset, known demo portrait, or http(s) [ImageProvider].
  /// Storage photos go through the bounded disk cache; any other http image
  /// (humor media, album art) stays a plain [NetworkImage].
  static ImageProvider? provider(String? url) {
    final asset = MevoraPhotoImages.assetPath(url);
    if (asset != null) {
      return AssetImage(asset);
    }
    if (!isHttpUrl(url)) {
      return null;
    }
    if (isStorageDownloadUrl(url)) {
      return DiskCachedNetworkImage(resolve(url)!);
    }
    return NetworkImage(url!);
  }
}
